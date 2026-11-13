from django.db import models

# Create your models here.
class Device(models.Model):
    id = models.AutoField(primary_key=True)
    device_code = models.CharField(max_length=255, unique=True)
    device_name = models.CharField(max_length=255,null=True, blank=True)
    device_ip = models.GenericIPAddressField(null=True, blank=True)
    user_code = models.CharField(max_length=255, unique=True)
    verification_uri = models.CharField(max_length=255)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.device_name} ({self.device_code})"


class VODProxySession(models.Model):
    """A fragmented-MP4 broadcast that is being remuxed for the device.

    The Roku player will not start a fragmented-MP4 stream, and Twitch stores
    some broadcasts in that format and others as MPEG-TS. The session holds
    the source playlist so that any worker can serve the remuxed segments;
    the token is what the device is handed.
    """
    id = models.AutoField(primary_key=True)
    token = models.CharField(max_length=64, unique=True)
    source_url = models.CharField(max_length=1024)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"{self.token} ({self.source_url})"
