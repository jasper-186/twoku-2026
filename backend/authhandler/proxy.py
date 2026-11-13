"""Serve Twitch broadcasts that are stored as fragmented MP4.

The Roku's HLS player will not start a fragmented-MP4 stream, and Twitch
stores some broadcasts in that format and others as MPEG-TS - the choice is
per broadcast, and every rendition of a fragmented-MP4 broadcast is
fragmented MP4. There is no parameter that asks for the other container.

So the segments are remuxed to MPEG-TS as they are requested. That keeps
the device on a format it plays, without holding a whole broadcast on disk
or in memory: a ten second segment takes about a tenth of a second to
remux.

The segments are plain CDN files, so nothing here needs the viewer's
credentials.
"""

import logging
import subprocess
import uuid
from collections import OrderedDict

import requests
from django.conf import settings
from django.utils import timezone

from .models import VODProxySession

logger = logging.getLogger(__name__)

# A remuxed segment is around ten megabytes, so a small window covers the
# player looking ahead without holding much on disk.
CACHE_SEGMENTS = 24

# Only the Twitch CDN is fetched through this path.
ALLOWED_HOSTS = (
    'usher.ttvnw.net',
    'vod-secure.twitch.tv',
    'playlist.ttvnw.net',
)

FETCH_TIMEOUT = 30

# How long a proxy session stays usable.
SESSION_TTL_MINUTES = 120

# The remuxer is cached per worker. The session row is what makes the
# proxy visible to all of them; this is only a cache.
_REMUXERS = {}


def is_allowed_source(url):
    """True for a URL this proxy is willing to fetch."""
    if not url or not url.startswith('https://'):
        return False
    host = url.split('://', 1)[1].split('/', 1)[0].split(':')[0].lower()
    if host in ALLOWED_HOSTS:
        return True
    # The CDN hosts are numbered per cluster, so match the suffix.
    return host.endswith('.cloudfront.net') or host.endswith('.ttvnw.net')


def is_fragmented_mp4(playlist_url):
    """True when the playlist is fragmented MP4 rather than MPEG-TS."""
    if not playlist_url or not is_allowed_source(playlist_url):
        return False
    try:
        response = requests.get(playlist_url, timeout=FETCH_TIMEOUT)
        response.raise_for_status()
    except Exception as e:
        logger.warning(f"Could not read the playlist {playlist_url}: {str(e)}")
        return False
    return '#EXT-X-MAP' in response.text


def quality_height(name):
    """The height out of a quality name: 1080p60 -> 1080."""
    digits = ''
    for char in name:
        if not char.isdigit():
            break
        digits += char
    return int(digits) if digits else 0


def match_quality(streams, resolution):
    """The stream key that matches a requested quality.

    Twitch names its renditions by their real frame rate - 480p30, 360p30 -
    while the app asks for 480p and 360p, so the closest match by height
    is used.
    """
    if resolution in streams:
        return resolution
    wanted = quality_height(resolution)
    candidates = [
        name for name in streams
        if name not in ('best', 'worst', 'audio_only')
        and 'portrait' not in name
        and quality_height(name) == wanted
    ]
    if candidates:
        for name in candidates:
            if name.startswith(resolution):
                return name
        return sorted(candidates)[0]
    return 'best' if 'best' in streams else None


def normalize_quality(stream_data, resolution):
    """Make sure the requested quality is in the list the app looks in.

    The app asks for a quality by its own name - 480p, 360p - and Twitch
    calls the same rendition 480p30, 360p30. The app's name is added as an
    alias so the lookup always finds something.
    """
    streams = stream_data.get('streams', {})
    if not streams:
        return None
    name = match_quality(streams, resolution)
    if name is None:
        return None
    if name != resolution:
        streams[resolution] = streams[name]
    return name


class SegmentRemuxer:
    """Remuxes the segments of one fragmented-MP4 rendition into MPEG-TS."""

    def __init__(self, source_playlist_url):
        self.source_url = source_playlist_url
        self.base_url = source_playlist_url.rsplit('/', 1)[0] + '/'
        self.segments = []
        self.cache = OrderedDict()
        self.playlist = self._read_playlist()

    def _read_playlist(self):
        response = requests.get(self.source_url, timeout=FETCH_TIMEOUT)
        response.raise_for_status()
        text = response.text

        segments = []
        duration = None
        for line in text.splitlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith('#EXTINF:'):
                duration = line.split(':', 1)[1].split(',')[0]
            elif not line.startswith('#'):
                segments.append((duration, line))
        self.segments = segments
        return text

    def ts_playlist(self):
        """The source playlist as MPEG-TS.

        The fragmented-MP4 init segment is dropped - MPEG-TS carries what
        the player needs in the segment itself - and the segment names
        become .ts.
        """
        out = [
            '#EXTM3U',
            '#EXT-X-VERSION:3',
        ]
        for line in self.playlist.splitlines():
            line = line.strip()
            if not line:
                continue
            if line.startswith('#EXT-X-MAP'):
                continue
            if line.startswith('#EXT-X-VERSION'):
                continue
            if line == '#EXTM3U':
                continue
            if line.startswith('#'):
                out.append(line)
                continue
            out.append(line.replace('.mp4', '.ts'))
        return '\n'.join(out) + '\n'

    def segment(self, name):
        """One segment, remuxed to MPEG-TS."""
        if name in self.cache:
            self.cache.move_to_end(name)
            return self.cache[name]

        media_name = name[:-3] + '.mp4' if name.endswith('.ts') else name
        init = requests.get(self.base_url + 'init-0.mp4', timeout=FETCH_TIMEOUT).content
        media = requests.get(self.base_url + media_name, timeout=FETCH_TIMEOUT).content

        result = subprocess.run(
            [
                'ffmpeg', '-hide_banner', '-loglevel', 'error',
                '-i', 'pipe:0', '-c', 'copy', '-f', 'mpegts', 'pipe:1',
            ],
            input=init + media,
            capture_output=True,
        )
        if result.returncode != 0:
            raise RuntimeError(
                'Remux failed: ' + result.stderr.decode('utf-8', 'replace')
            )

        data = result.stdout
        self.cache[name] = data
        while len(self.cache) > CACHE_SEGMENTS:
            self.cache.popitem(last=False)
        return data


def build_master(variant_line, media_playlist_url):
    """A one-variant master playlist pointing at the proxied playlist.

    The variant line is copied from the source master so the bandwidth,
    codecs and resolution stay exact.
    """
    return '\n'.join([
        '#EXTM3U',
        variant_line,
        media_playlist_url,
        '',
    ])


def find_variant_line(source_master_url, media_playlist_url):
    """The #EXT-X-STREAM-INF line in the source master for this rendition."""
    fallback = '#EXT-X-STREAM-INF:BANDWIDTH=8000000,CODECS="avc1.4D402A,mp4a.40.2",RESOLUTION=1920x1080'
    if not source_master_url or not is_allowed_source(source_master_url):
        return fallback
    try:
        response = requests.get(source_master_url, timeout=FETCH_TIMEOUT)
        response.raise_for_status()
    except Exception as e:
        logger.warning(f"Could not read the master {source_master_url}: {str(e)}")
        return fallback

    lines = response.text.splitlines()
    for index, line in enumerate(lines):
        if not line.startswith('#EXT-X-STREAM-INF'):
            continue
        if index + 1 < len(lines) and lines[index + 1].strip() == media_playlist_url.strip():
            return line.strip()
    return fallback


def remuxer_for(token, source_url):
    """The remuxer for a session, cached per worker."""
    remuxer = _REMUXERS.get(token)
    if remuxer is None or remuxer.source_url != source_url:
        remuxer = SegmentRemuxer(source_url)
        _REMUXERS[token] = remuxer
    return remuxer


def get_session(token):
    """The session for a token, or None if it is unknown or too old."""
    try:
        session = VODProxySession.objects.get(token=token)
    except VODProxySession.DoesNotExist:
        return None
    if session.created_at < timezone.now() - timezone.timedelta(minutes=SESSION_TTL_MINUTES):
        return None
    return session


def prune_sessions():
    """Drop the sessions nobody is using any more."""
    VODProxySession.objects.filter(
        created_at__lt=timezone.now() - timezone.timedelta(minutes=SESSION_TTL_MINUTES)
    ).delete()


def proxy_if_fragmented(stream_data, quality, base_url):
    """Point a fragmented-MP4 rendition at the remuxing proxy.

    The device is handed the proxied media playlist rather than a master
    playlist: it takes one URL and plays it, where a master playlist would
    have to be resolved first.

    Returns the session token when the rendition was replaced.
    """
    streams = stream_data.get('streams', {})
    entry = streams.get(quality)
    if not entry:
        return None
    media_url = entry.get('url')
    if not media_url or not is_fragmented_mp4(media_url):
        return None

    token = uuid.uuid4().hex
    session = VODProxySession.objects.create(token=token, source_url=media_url)
    playlist_url = '%s/vodproxy/%s/index.m3u8' % (base_url.rstrip('/'), session.token)
    entry['master'] = playlist_url
    logger.info(f"Remuxing fragmented-MP4 rendition {quality} for {session.token}")
    return session.token
