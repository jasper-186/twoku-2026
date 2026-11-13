# Twoku backend

The companion service for the [Twoku Roku app](../roku/). It holds the Twitch
client secret, brokers the OAuth device-code flow, and resolves playback URLs.

This is the service that lives in this repository as `backend/`. The Roku app
it serves is in `roku/`.

## What it does

| Endpoint | Method | Purpose |
|---|---|---|
| `/` | GET | Renders the device-authorization form. The user types the short code here and gets redirected to Twitch. |
| `/register` | GET | Asks Twitch for a device code, stores it, returns the short **user code** as plain text. |
| `/deviceredirect` | POST | Looks the code up and redirects the browser to Twitch's device page. |
| `/unregister` | POST | Exchanges the device code for tokens. *(The name is historical — this is the token-exchange step.)* |
| `/refresh` | POST | Exchanges a refresh token for a new access token. Returns the upstream status code, so a rejected refresh token comes back as `400`. |
| `/apptoken` | GET | Mints an app-level token and returns it with the client id. |
| `/getlivestream` | POST | Resolves a live stream's playback URL via `streamlink`. |
| `/getvod` | POST | Resolves a VOD's playback URL via `streamlink`. |
| `/vodproxy/<token>/index.m3u8` | GET | The MPEG-TS playlist for a broadcast that Twitch stores as fragmented MP4. |
| `/vodproxy/<token>/<segment>.ts` | GET | One segment of that playlist, remuxed to MPEG-TS. |

The device-code flow:

1. The Roku app calls `GET /register` and receives a short user code.
2. The user enters that code on the service's home page, which redirects them
   to Twitch to approve it.
3. The Roku app polls `POST /unregister` with the code until Twitch returns
   tokens.

Playback URLs are resolved by shelling out to `streamlink`, so the device
receives a master playlist URL and nothing more.

## Running it locally

```bash
python -m venv .venv
.venv/bin/pip install -r requirements.txt

export TWITCH_CLIENT_ID=...
export TWITCH_CLIENT_SECRET=...

.venv/bin/python manage.py migrate
.venv/bin/python manage.py runserver
```

The service listens on port 8080 in production.

## Configuration

All configuration is by environment variable. Nothing sensitive is committed.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `TWITCH_CLIENT_ID` | for the token endpoints | — | The Twitch application's client id. |
| `TWITCH_CLIENT_SECRET` | for the token endpoints | — | The Twitch application's client secret. |
| `DJANGO_SECRET_KEY` | in production | randomly generated per process | Django's signing key. Not setting it invalidates sessions and signed cookies on restart. |
| `DJANGO_DEBUG` | no | `false` | Set `true` for local development. |
| `DJANGO_BASE_URL` | no | `https://twoku-web.clstr.dev` | The public URL this deployment is reached at, no trailing slash. The host allowlist and the CSRF origins are derived from it. |
| `DJANGO_ALLOWED_HOSTS` | no | `localhost,127.0.0.1,<host from DJANGO_BASE_URL>` | Comma-separated host allowlist. Hostnames, without ports. |
| `DJANGO_CSRF_TRUSTED_ORIGINS` | no | `http://localhost:8080,http://localhost:8000,<origin from DJANGO_BASE_URL>` | Comma-separated origins for unsafe requests. |
| `DJANGO_DATABASE_PATH` | no | `db.sqlite3` next to `manage.py` | Where the SQLite file lives. |
| `LOG_SENSITIVE_DATA` | no | `false` | When `true`, log lines carry the full OAuth tokens, device codes and signed playback URLs. **Leave it off** — those are credentials, and the log is the one place they are most likely to be copied from. Turn it on only while debugging. |

## Self-hosting

The backend is configured entirely through the environment, so the same image
serves any deployment.

```bash
cp .env.example .env      # then fill it in
docker compose up -d
```

At minimum you need to set:

| Variable | Meaning |
|---|---|
| `DJANGO_BASE_URL` | The address your backend is reached at, e.g. `https://twoku.example.com`. |
| `TWITCH_CLIENT_ID` / `TWITCH_CLIENT_SECRET` | From a Twitch application you register at <https://dev.twitch.tv/console/apps>. |
| `DJANGO_SECRET_KEY` | A random string. `python -c "import secrets; print(secrets.token_urlsafe(64))"`. |

**The two halves have to agree.** `DJANGO_BASE_URL` here and `BASE-URL` in the
Roku app's `env` file must be the same address, or the app will not reach the
backend. See [`../roku/env.example`](../roku/env.example).

Run it behind a TLS-terminating reverse proxy, and set `DJANGO_BASE_URL` to
the `https://` address the proxy serves.

## Deploying

`Dockerfile` builds the image. It listens on port 8080 and runs gunicorn with
four workers.

```bash
docker build -t twoku-webapp -f backend/Dockerfile backend
```

Migrations are applied by `docker-entrypoint.sh` when the container starts,
not at build time, because the database may live on a mounted volume that is
not part of the image.

The CI workflow in [`.github/workflows/release.yml`](../.github/workflows/release.yml)
builds this image and pushes it to GitHub Container Registry as
`ghcr.io/<owner>/<repo>/backend`, tagged with the release version, the commit
SHA, and `latest`. It uses the automatic `GITHUB_TOKEN`, so no registry
credentials are configured in the repository. See the root
[`README.md`](../README.md#continuous-integration) for details.

## Notes

- The database is SQLite, created by `migrate`. It holds `Device`, for
  in-flight device codes, and `VODProxySession`, for the remuxing proxy.
- `streamlink` is installed from git rather than PyPI, so a build needs
  network access and a working git client.
- `ffmpeg` is needed for the remuxing proxy. The Dockerfile installs it;
  an install from source needs it too.

### The remuxing proxy

The Roku's HLS player will not start a fragmented-MP4 stream. Twitch stores
some broadcasts in that format and others as MPEG-TS — the choice is per
broadcast, and every rendition of a fragmented-MP4 broadcast is fragmented
MP4. There is no parameter that asks for the other container.

So `/getvod` checks the rendition it resolved: if it is fragmented MP4, the
segments are remuxed to MPEG-TS as they are requested, and the device is
handed a playlist served from `/vodproxy/`. A ten second segment takes
about a tenth of a second to remux, so playback starts almost immediately
and nothing is held on disk beyond a small cache.

Only fragmented-MP4 broadcasts go through the proxy. Live streams and
MPEG-TS broadcasts are served straight from Twitch's CDN.

The proxy endpoints are public, like `/getvod` and `/getlivestream` already
are. A session token is handed out by `/getvod` and expires after two
hours.
