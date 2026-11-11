# Twoku

An unofficial Twitch client for Roku, and the backend it talks to.

Twoku is a native Roku application written in BrightScript on the SceneGraph
framework. It browses live channels and categories, searches, shows followed
streamers, plays live streams and VODs, and renders Twitch chat.

| Directory | What it is | Stack |
|---|---|---|
| [`roku/`](roku/) | The Roku application. The deliverable — this is what ships to the device. | BrightScript / SceneGraph |
| [`backend/`](backend/) | The companion service. Holds the Twitch client secret, brokers OAuth, and resolves playback URLs. | Django / gunicorn |

The two halves are one product, so they live in one repository.

## How the halves talk

The Roku app never receives the Twitch client secret. Everything that needs
it goes through the backend, which is deployed at `https://twoku-web.clstr.dev/`.

| Endpoint | Method | Purpose |
|---|---|---|
| `/apptoken` | GET | App client id + bearer token. Avoids shipping the client secret on the device. |
| `/register` | GET | Begins the device-code login. Returns a short user code as plain text. |
| `/unregister` | POST | Polls the device-code grant for tokens. *(The name is historical — it is the token-exchange step.)* |
| `/refresh` | POST | Exchanges a refresh token for a new access token. |
| `/getlivestream` | POST | `{twitch_channel, access_token, resolution}` → playback URL for a live stream. |
| `/getvod` | POST | `{video_id, access_token, resolution}` → playback URL for a VOD. |

The backend resolves playback URLs by shelling out to `streamlink`, so the
device receives a master playlist URL and nothing more.

Everything else — Helix browsing, search, followed channels, chat badges —
is fetched **directly from Twitch by the Roku app**, using the token it holds.

## Working on the Roku app

There is no build system, no test framework and no linter. The repository *is*
the deployable artifact. To change the app, sideload it and walk the affected
screen on a device.

```bash
cd roku
./package.sh            # writes roku/twoku.zip
```

Then sideload it:

```bash
curl --digest -u rokudev:<password> \
     -F mysubmit=Install -F archive=@roku/twoku.zip \
     http://<device-ip>/plugin_install
```

Or use the BrightScript VS Code extension's launch task, which pushes the
current tree straight to the device.

Check that the source still compiles before you sideload — the device only
reports `Install Failure: Compilation Failed.` with no line number:

```bash
npx --yes -p brighterscript@latest bsc \
    --root-dir roku --create-package false --copy-to-staging false \
    --diagnostic-level error
```

**Read [`roku/CLAUDE.md`](roku/CLAUDE.md) before touching the Roku code.** It is
the canonical architecture reference: scene graph layout, the `Get*` Task-node
contract, the shared helpers under `roku/components/common/`, global and
registry state, and a list of known gaps that are documented but deliberately
unfixed.

## Working on the backend

```bash
cd backend
python -m venv .venv
.venv/bin/pip install -r requirements.txt

export TWITCH_CLIENT_ID=...      # required for the token endpoints
export TWITCH_CLIENT_SECRET=...  # required for the token endpoints

.venv/bin/python manage.py migrate
.venv/bin/python manage.py runserver
```

The service listens on port 8080 in production (`gunicorn`), and
`backend/Dockerfile` builds that image.

## Continuous integration

[`.forgejo/workflows/`](.forgejo/workflows/) builds and pushes the backend
Docker image to `registry.clstr.dev`:

- `build-push-docker-image.yaml` — on a `release-v*` tag. Publishes
  `twoku-webapp:latest` and `twoku-webapp:<version>`.
- `build-push-docker-image-branch.yaml` — on any non-`main` branch. Publishes
  `twoku-webapp-<branch>:latest`.

## Self-hosting

Both halves are configured through the environment, so the same sources serve
any deployment.

**1. The backend.** It is a container image configured entirely through
environment variables.

```bash
cd backend
cp .env.example .env      # then fill it in
docker compose up -d
```

You need `DJANGO_BASE_URL` (the address your backend is reached at),
`TWITCH_CLIENT_ID` and `TWITCH_CLIENT_SECRET` (from a Twitch application you
register at <https://dev.twitch.tv/console/apps>), and `DJANGO_SECRET_KEY`.
See [`backend/README.md`](backend/README.md) for the full list.

**2. The Roku app.** The app reads the backend address from an `env` file at
the root of the package. Edit it, rebuild, and sideload:

```bash
cd roku
cp env.example env
$EDITOR env               # set BASE-URL to your backend's address
./package.sh              # writes roku/twoku.zip
```

Then sideload the zip as described above.

**The two must agree** — `DJANGO_BASE_URL` in the backend and `BASE-URL` in
the Roku app's `env` file have to be the same address.

Note that the URL is baked into the Roku package, so changing it means
rebuilding and re-sideloading the app.

## Known issues

[`roku/.known_issues/`](roku/.known_issues/) holds the defects that are fixed
but **not yet verified on a device**, plus open questions that need a
particular account, device state or moment in time. `roku/CLAUDE.md` lists the
defects themselves; that folder is the other half — how to prove a fix works
when the defect cannot be reproduced on demand.

## License

MIT. See [LICENSE](LICENSE).

## Credits

Twoku for Roku began as a community project. See
[`roku/README.md`](roku/README.md) for the original README, the Discord
invite, and the donation link.
