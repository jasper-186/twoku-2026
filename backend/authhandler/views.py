
from django.shortcuts import render
from django.http import HttpResponse
import requests
import logging
import json
from django.conf import settings
from .models import Device
from django.http import JsonResponse
from django.shortcuts import redirect
from django.views.decorators.csrf import csrf_exempt
import subprocess
from urllib.parse import urlsplit, urlunsplit

logger = logging.getLogger(__name__)

# Keys whose values are credentials and must never reach the log unless
# LOG_SENSITIVE_DATA is switched on.
SECRET_KEYS = frozenset([
    'access_token',
    'refresh_token',
    'device_code',
    'user_code',
    'code',
])


def redact(value):
    """A short, non-reversible hint for a credential."""
    if settings.LOG_SENSITIVE_DATA:
        return str(value)
    text = str(value or '')
    if not text:
        return ''
    if len(text) <= 8:
        return '*' * len(text)
    return '%s...(%d chars)' % (text[:4], len(text))


def summarize(payload):
    """A copy of a JSON payload with the credential material redacted."""
    if settings.LOG_SENSITIVE_DATA:
        return payload
    if not isinstance(payload, dict):
        return payload
    safe = {}
    for key, value in payload.items():
        if key.lower() in SECRET_KEYS:
            safe[key] = redact(value)
        else:
            safe[key] = value
    return safe


def redact_url(url):
    """A URL without its query string - the signed parameters are credentials."""
    if settings.LOG_SENSITIVE_DATA:
        return url
    if not url:
        return ''
    parts = urlsplit(url)
    return urlunsplit((parts.scheme, parts.netloc, parts.path, '', ''))


def summarize_stream(stream_data):
    """The streamlink payload, without tokens or signed URLs."""
    if settings.LOG_SENSITIVE_DATA:
        return stream_data
    metadata = stream_data.get('metadata', {})
    streams = stream_data.get('streams', {})
    best = streams.get('best') or streams.get('worst') or {}
    return {
        'plugin': stream_data.get('plugin'),
        'metadata': {
            'id': metadata.get('id'),
            'author': metadata.get('author'),
            'category': metadata.get('category'),
            'title': metadata.get('title'),
        },
        'qualities': sorted(
            key for key in streams
            if key not in ('audio_only', 'best', 'worst')
        ),
        'master': redact_url(best.get('master', '')),
    }


def get_client_ip(request):
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        ip = x_forwarded_for.split(',')[0]
    else:
        ip = request.META.get('REMOTE_ADDR')
    return ip

def device(request):
    """Present user with form to enter device user code"""
    return render(request, 'authhandler/device.html')

def deviceredirect(request):
    if request.method != 'POST':
        return HttpResponse("Method not allowed", status=405)
    
    try:
        user_code = request.POST.get('user_code')
        
        if not user_code:
            return JsonResponse({'error': 'Missing user_code parameter'}, status=400)
        
        device = Device.objects.get(user_code=user_code)
        
        # Redirect to verification URI
        return redirect(device.verification_uri)
    except Device.DoesNotExist:
        return JsonResponse({'error': 'Device not found'}, status=404)
    except Exception as e:
        logger.error(f"Device redirect error: {str(e)}")
        return JsonResponse({'error': str(e)}, status=400)

# Create your views here.
def register(request):
    if request.method != 'GET':
        return HttpResponse("Method not allowed", status=405)
    
    logger.info(f"request.META.REMOTE_HOST: {(request.META.get('REMOTE_HOST'))}")
    logger.info(f"request.META.REMOTE_ADDR: {(request.META.get('REMOTE_ADDR'))}")
    try:
        # Request device code from Twitch
        scopes = [
            'user:read:email',
            'user:read:follows',
            'user:read:chat',
            'user:write:chat', 
            'chat:read',
            'chat:edit',           
        ]
        
        device_response = requests.post(
            'https://id.twitch.tv/oauth2/device',
            data={
                'client_id': settings.TWITCH_CLIENT_ID,
                'scopes': ' '.join(scopes)
            }
        )
        
        device_data = device_response.json()
        logger.info(f"device_data: {json.dumps(summarize(device_data))}")
        device_code = device_data.get('device_code')
        user_code = device_data.get('user_code')
        verification_uri=device_data.get('verification_uri')
        
        device_name = request.META.get('REMOTE_HOST')
        device_ip = get_client_ip(request)
        logger.info(f"Registering device: {device_name} with device_code: {redact(device_code)}")
        
        
        # Create and save the Device
        device = Device(
            device_code=device_code,
            user_code=user_code,
            device_name=device_name,
            device_ip=device_ip,
            verification_uri=verification_uri
        )

        device.save()
        
        return HttpResponse(user_code,status=200)
    except Exception as e:
        logger.error(f"Device registration error: {str(e)}")
        return JsonResponse({'error': str(e)}, status=400)

@csrf_exempt
def unregister(request):
    logger.info(f"unregister request received")
    if request.method != 'POST':
        return HttpResponse("Method not allowed", status=405)
    
    try:
        data = json.loads(request.body)
        logger.info(f"unregister request body: {json.dumps(summarize(data))}")
        user_code = data.get('code')
        logger.info(f"user_code: {redact(user_code)}")
        if not user_code:
            return JsonResponse({'error': 'Missing code parameter'}, status=400)
        
        device = Device.objects.get(user_code=user_code)
        
        logger.info(f"device_code: {redact(device.device_code)}")
        # Post to Twitch token endpoint
        token_response = requests.post(
            'https://id.twitch.tv/oauth2/token',
            data={
                'client_id': settings.TWITCH_CLIENT_ID,
                #'scope': 'channel:manage:broadcast',
                'device_code': device.device_code,
                'grant_type': 'urn:ietf:params:oauth:grant-type:device_code'
            }
        )
        
        #device.delete()        
        logger.info(f"Device unregistered: {redact(user_code)}")
        return JsonResponse(token_response.json())
    except Device.DoesNotExist:
        return JsonResponse({'error': 'Device not found'}, status=404)
    except Exception as e:
        logger.error(f"Device unregistration error: {str(e)}")
        logger.error(f"request body: {str(request.body)}")
        return JsonResponse({'error': str(e)}, status=400)
    
@csrf_exempt
def refresh(request):
    if request.method != 'POST':
        return HttpResponse("Method not allowed", status=405)
    
    logger.info(f"request.META.REMOTE_HOST: {(request.META.get('REMOTE_HOST'))}")
    logger.info(f"request.META.REMOTE_ADDR: {(request.META.get('REMOTE_ADDR'))}")
    try:
        # Request refresh token from Twitch
        token_response = requests.post(
            'https://id.twitch.tv/oauth2/token',
            data={
                'client_id': settings.TWITCH_CLIENT_ID,
                'client_secret': settings.TWITCH_CLIENT_SECRET,
                'grant_type': 'refresh_token',
                'refresh_token': request.POST.get('code')
            }
        )
        
        token_data = token_response.json()
        logger.info(f"token_data: {json.dumps(summarize(token_data))}")

        return JsonResponse(token_data, status=token_response.status_code)
    except Exception as e:
        logger.error(f"Device registration error: {str(e)}")
        return JsonResponse({'error': str(e)}, status=400)


@csrf_exempt
def apptoken(request):
    if request.method != 'GET':
        return HttpResponse("Method not allowed", status=405)
    
    try:
        # Request refresh token from Twitch
        token_response = requests.post(
            'https://id.twitch.tv/oauth2/token',
            data={
                'client_id': settings.TWITCH_CLIENT_ID,
                'client_secret': settings.TWITCH_CLIENT_SECRET,
                'grant_type': 'client_credentials'
            }
        )
        
        token_data = token_response.json()
        token_data['client_id'] = settings.TWITCH_CLIENT_ID
        logger.info(f"token_data: {json.dumps(summarize(token_data))}")

        return JsonResponse(token_data, status=token_response.status_code)
    except Exception as e:
        logger.error(f"Device registration error: {str(e)}")
        return JsonResponse({'error': str(e)}, status=400)

@csrf_exempt
def getlivestream(request):
    if request.method != 'POST':
        return HttpResponse("Method not allowed", status=405)
    
    try:
        data = json.loads(request.body)
    
        twitch_channel = data.get('twitch_channel')
        access_token = data.get('access_token')
        resolution = data.get('resolution')
        
        logger.info(f"Getting stream link for channel: {twitch_channel} @ {resolution} with access token: {redact(access_token)}")
    
        try:
            result = subprocess.run(
                [
                    "streamlink",
                    f"https://www.twitch.tv/{twitch_channel}",
                    "--default-stream",
                    f"{resolution},best",
                    "--http-header",
                    f"Authorization=\"OAuth {access_token}\"",
                    "--stream-url",
                    "--twitch-disable-ads",
                    "--twitch-supported-codecs",
                    "h264,h265",
                    "--twitch-low-latency",
                    "--json"
                ],
                capture_output=True
            )
            
            if result.returncode != 0:
                error_message = "Return code: " + str(result.returncode) + " - " + result.stderr.decode('utf-8')
                logger.error(f"Streamlink error(stderr): {error_message}")
                logger.error(f"Streamlink error(stdout): {result.stdout.decode('utf-8')}")
                return JsonResponse({'error': error_message}, status=500)
            
            stream_data = json.loads(result.stdout.decode('utf-8'))
            logger.info(f"Stream URL: {summarize_stream(stream_data)}")
            return JsonResponse({'stream_data': stream_data})
        
        except Exception as e:
            logger.error(f"Subprocess error: {str(e)}")
            return JsonResponse({'error': str(e)}, status=500)
        
    except Exception as e:
        logger.error(f"Get Stream Links error: {str(e)}")
        return JsonResponse({'error': str(e)}, status=400)
    

@csrf_exempt
def getvod(request):
    if request.method != 'POST':
        return HttpResponse("Method not allowed", status=405)
    
    try:
        data = json.loads(request.body)
    
        video_id = data.get('video_id')
        access_token = data.get('access_token')
        resolution = data.get('resolution')
        
        logger.info(f"Getting video link for Id: {video_id} @ {resolution} with access token: {redact(access_token)}")
    
        try:
            result = subprocess.run(
                [
                    "streamlink",
                    f"https://www.twitch.tv/videos/{video_id}",
                    "--default-stream",
                    f"{resolution},best",
                    "--http-header",
                    f"Authorization=\"OAuth {access_token}\"",
                    "--stream-url",
                    "--twitch-disable-ads",
                    "--twitch-supported-codecs",
                    "h264,h265",
                    "--json"
                ],
                capture_output=True
            )
            
            if result.returncode != 0:
                error_message = "Return code: " + str(result.returncode) + " - " + result.stderr.decode('utf-8')
                logger.error(f"Streamlink error(stderr): {error_message}")
                logger.error(f"Streamlink error(stdout): {result.stdout.decode('utf-8')}")
                return JsonResponse({'error': error_message}, status=500)
            
            stream_data = json.loads(result.stdout.decode('utf-8'))
            logger.info(f"Stream URL: {summarize_stream(stream_data)}")
            return JsonResponse({'stream_data': stream_data})
        
        except Exception as e:
            logger.error(f"Subprocess error: {str(e)}")
            return JsonResponse({'error': str(e)}, status=500)
        
    except Exception as e:
        logger.error(f"Get Stream Links error: {str(e)}")
        return JsonResponse({'error': str(e)}, status=400)
    

    