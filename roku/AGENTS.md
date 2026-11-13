# AGENTS.md

Guidance for AI coding agents working in the Roku application.

This app lives at `roku/` in a monorepo that also contains the companion
Django service at `backend/`. The repo-root `AGENTS.md` covers the whole
product; this file is the canonical reference for the Roku half.

It documents the project overview, the build/deploy workflow, the SceneGraph
architecture, the `Get*` Task-node contract, the shared helpers under
`components/common/`, global and registry state, the companion backend, the
BrightScript conventions used here, and a list of known gaps/hazards that are
documented but *not* fixed.

## Quick orientation

- **Twoku** — an unofficial Twitch client for Roku, written in BrightScript on
  the SceneGraph framework. The original developers were learning Roku as they
  went, so the code is intentionally messy in places and not consistently
  organized.
- **No build system, no test framework, no linter.** The source tree *is* the
  deployable artifact. Verify changes by sideloading to a Roku in dev mode and
  walking the affected screen.
- **Entry point** — `source/main.brs` creates an `roSGScreen` and instantiates
  `MainScene`; everything else lives in `components/` as a `Foo.xml` (node +
  `<interface>` fields) / `Foo.brs` (behavior) pair.
- **Async work** — anything named `Get*` is a SceneGraph `Task` node: the
  caller sets input fields, sets `control = "RUN"`, and observes an output
  field. Tasks may only communicate through their interface fields.
- **Shared helpers are per-component, not global.**
  `components/common/*.brs` files must be `<script>`-included by each
  component that needs them.
- **Working branches** are dated `YYYY_MM_DD_<Topic>`; `main` is the trunk. Do
  not commit unless explicitly asked.

Paths below are relative to `roku/`.

## Build / Run / Deploy

There is no build system, test framework, or linter. The source tree *is* the
deployable artifact.

- **Sideload to a Roku in dev mode** — the BrightScript VSCode extension needs
  to know your device and where the app lives. `.vscode/` is gitignored, so
  create a local `.vscode/settings.json` at the repo root:

  ```json
  {
      "brightscript.devices": [
          { "host": "<device-ip>", "serialNumber": "<serial>", "password": "<dev-password>" }
      ],
      "brightscript.projects": ["roku"]
  }
  ```

  `brightscript.projects` is needed because the app is in `roku/`, not at the
  workspace root. Use the extension's "Launch" action to push the tree to the
  device.
- **Manual install** — ZIP the *contents* of `roku/` (no top-level directory)
  and upload via the Roku dev web UI at `http://<roku-ip>`. `package.sh` does
  this and lists exactly what goes in; `*.zip` is gitignored. It also copies
  `env.example` to `env` if `env` is missing, so a fresh clone can package
  immediately.
- **manifest** — `title=Twoku-2026`, `major_version=0`, `minor_version=9`,
  `rsg_version=1.3` identify the build. The committed `build_version` is
  `00000`; the release workflow stamps its own value into the packaged copy,
  so the file in git is the baseline and not the released version. Bump
  `major_version` / `minor_version` when a release calls for a new version
  line.
- **`env`** — holds `BASE-URL`, the address of the backend this build talks
  to. It ships inside the package and is read at runtime from `pkg:/env` by
  `common/Env.brs`. The file is not committed — `env.example` is the template
  and `env` is gitignored, because each deployment has its own. `package.sh`
  copies `env.example` to `env` if it is missing, so a fresh clone packages and
  runs against the upstream deployment; edit `env` to point somewhere else.
  The URL is baked into the package, so changing it needs a rebuild.

To verify a change, sideload and walk the affected screen on a real device —
there is no headless way to exercise the SceneGraph.

- **Compile check** — Roku's own BrightScript compiler runs without a device
  and catches the errors that stop the app installing:

  ```bash
  npx --yes -p brighterscript@latest bsc --root-dir roku \
      --create-package false --copy-to-staging false --diagnostic-level error
  ```

  It exits non-zero and names the file and line. **Run it before sideloading**
  — the device reports a compile failure only as a component name
  (`Install Failure: Compilation Failed.\nGetUser`), with no line number, so a
  mistake is otherwise only found after a failed install.

## Architecture

### Entry and scene graph

`source/main.brs` does the bare minimum: create an `roSGScreen`, instantiate
the `MainScene` component, and pump the event loop. Everything else lives in
`components/`.

Each SceneGraph component is a pair: `Foo.xml` declares the node (extends
`Group`, `Scene`, `Video`, or `Task`) plus its `<interface>` fields and child
nodes; `Foo.brs` holds the behavior. The `<interface>` field list is the
contract between components — the parent reads/writes them, often via `alias=`
so a child field shows through on the parent.

`MainScene` is the router. It owns the top-level scenes (`HomeScene`,
`CategoryScene`, `LoginPage`, `Chat`, `CustomVideo`, `KeyboardGroup`,
`Options`) and switches between them by toggling `visible`. Scene transitions
are driven by `observeField` on cross-scene fields like `streamUrl`,
`streamerSelectedName`, `categorySelected`, `buttonPressed`.

**Init ordering matters.** XML children are constructed — and their `init()`
runs — *before* `MainScene.init()`. So `HomeScene.init()` fires first and
starts `GetStreams` before `MainScene.init()` has defined
`m.global.userToken`. That is why the token waits below exist and why they are
unbounded busy-waits.

### `Get*` Task nodes = async HTTP layer

Every component named `Get<Something>` is a `Task` node. The pattern is always:

1. Caller creates the node with `createObject("roSGNode", "GetX")`, sets input
   fields, observes an output field, then sets `control = "RUN"`.
2. The task runs `m.top.functionName` on a background thread, fetches/parses,
   writes the result to an output field.
3. The observer fires on the render thread.

Tasks cannot touch the UI directly — they communicate only through their
interface fields.

| Task | Entry fn | Output field(s) | Instantiated by |
|---|---|---|---|
| `GetToken` | `onStreamerChange` | `appClientId`, `appBearerToken` | `MainScene.brs:43` |
| `GetUser` | `onSearchTextChange` | `searchResults`, `currentlyLiveStreamerIds` | `MainScene.brs:48` |
| `GetAuth` | `onStreamerChange` | `code`, `finished` | `LoginPage.brs:8` |
| `GetSearch` | `onSearchTextChange` | `searchResults` | `KeyboardGroup.brs:18` |
| `GetCategorySearch` | `onSearchTextChange` | `searchResults` | `KeyboardGroup.brs:21` |
| `GetCategories` | `onSearchTextChange` | `searchResults` | `HomeScene.brs:55` |
| `GetStreams` | `onSearchTextChange` | `searchResults` | `HomeScene.brs:49`, `CategoryScene.brs:15` |
| `GetClips` | `onSearchTextChange` | `searchResults` | `CategoryScene.brs:18` |
| `GetOfflineFollowedChannels` | `onSearchTextChange` | `offlineFollowedUsers` | `HomeScene.brs:58` |
| `GetLiveStream` | `onStreamerChange` | `streamUrl` | `HomeScene.brs:52`, `CategoryScene.brs:21`, `KeyboardGroup.brs:24`, `ChannelPage.brs:27` |
| `GetPreviousLiveStreamVideo` | `onStreamerChange` | `streamUrl`, `thumbnailInfo` (the video id only) | `ChannelPage.brs:30` |
| `GetUserChannel` | `onSearchTextChange` | `searchResults`, `streamDurationSeconds` | `ChannelPage.brs:21` |
| `GetVideos` | `onSearchTextChange` | `searchResults` | `ChannelPage.brs:24` |

`ChannelPage` is instantiated by `HomeScene.xml:183-186`, and there is **no**
`ChannelPage` instance in `MainScene.xml` — the `MainScene.brs` references to
`m.channelPage.*` resolve to the `HomeScene` child.

### The Following tab (main page)

The Following tab has two halves and two separate tasks feed them:

```
GetUser  ── helix/streams/followed ──▶  followed_users  ──▶  HomeScene.followedStreams
                                          (live only)         │
                                                                ├── alias ──▶ FollowedStreamsBar  (the left "LIVE" rail)
                                                                └──▶ browseFollowingList  (the grid)

GetOfflineFollowedChannels ── helix/channels/followed ──▶  offlineFollowedUsers
                                     (live + offline)         └──▶ OfflineChannelList  (the grid below)
```

- `GetUser` also returns `currentlyLiveStreamerIds` (an assocarray of
  `user_id → true`). `GetOfflineFollowedChannels` uses it to subtract the live
  streamers from the followed list.
- `HomeScene.onGetFollowedStreams` is driven by the observeField on
  `HomeScene.currentlyLiveStreamerIds` (`HomeScene.brs:62`) — that is the only
  thing that kicks off the offline lookup.
- **`loggedInUserName` vs `loggedInUserLogin`**: `HomeScene.loggedInUserName`
  is the *display name* shown in the header, `HomeScene.loggedInUserLogin` is
  the *login*. The offline task looks the user up with `helix/users?login=`, so
  it must be given the login.
- `followed_users` items carry `game_name` (not `game_id`) — the Helix streams
  response includes the category name, so there is no id→name lookup.
- `m.numRowsInFollowingList` is the **number of rows** in the live-follows
  grid. The offline list is revealed when the last row is focused, or
  immediately when there are no live follows.

The visible offline list is the `OfflineChannelList` component
(`HomeScene.xml:188-191`), shown and hidden by `showOfflineChannelList()` /
`hideOfflineChannelList()` (`HomeScene.brs:392-400`).

### Shared helpers (`components/common/`)

The old monolithic `components/UrlFunctions.brs` no longer exists — it was
split into per-concern files under `components/common/`. Helpers are **not
global**: each component's XML `<script>`-includes only the files it needs, so
a helper is only in scope inside the component that included it.

| File | Provides |
|---|---|
| `common/Http.brs` | `newUrlTransfer()`, `waitForAppToken()`, `waitForUserToken()`, `redactToken()`, `redactUrl()` |
| `common/TwitchAuth.brs` | `createUrl()`, `createUserUrl()`, `GETJSON()`, `GETJSONPublic()`, `validateToken()`, `refreshToken()`, `refreshUserToken()`, `refreshAppToken()`, `getUserRefreshToken()`, `saveLogin()`, `clearLogin()` |
| `common/TwitchApi.brs` | `lookupUserByLogin()`, `lookupUserByLoginAuthed()`, `ensureGlobalBTTVEmotes()`, `ensureChannelFFZEmotes()` |
| `common/TwitchImages.brs` | `resizeTwitchImageUrl()` |
| `common/Format.brs` | `formatCountAbbrev()`, `secondsSinceISO8601()`, `formatElapsedHMS()` |
| `common/Registry.brs` | `checkRegistrySection()`, `setRegistrySection()` — included by `MainScene.xml` only, so these are in scope in `MainScene` alone |
| `common/Env.brs` | `getBackendBaseUrl()` — reads `BASE-URL` from `pkg:/env`. See the Companion backend section. |
| `common/WebSocket.brs` | RFC-6455 WebSocket client, `ws://` only. See the Chat section. |

Always go through these helpers rather than building `roUrlTransfer` by hand —
they centralize cert setup, header injection (Client-ID + bearer), and the
user-token-vs-app-token fallback:

- `createUrl()` — authed transfer; prefers user token, falls back to app
  token.
- `createUserUrl()` — authed transfer; returns `invalid` if no user token (use
  for endpoints that require user auth).
- `GETJSON(link)` — one-shot GET + parse. Attaches the Twitch credentials,
  so it is only for Twitch's own endpoints.
- `GETJSONPublic(link)` — one-shot GET + parse with **no** credentials
  attached. Use it for third-party APIs (BetterTTV, FrankerFaceZ) — they have
  no business seeing the user's Twitch token.
- `redactToken(token)` — a short hint for a credential, for log lines. It
  lives in `common/Http.brs` so that every component can use it, including
  the ones that do not include `common/TwitchAuth.brs`.
- `redactUrl(url)` — a URL without its query string. The signed parameters in
  a playback URL are credentials of their own.
- `validateToken`, `refreshToken`, `refreshUserToken`, `refreshAppToken` —
  token lifecycle; the refresh path round-trips through the companion backend.
  A refresh **rotates** the refresh token, so only one may run at a time:
  `refreshUserToken` takes a global flag and the other tasks wait for it.
  When the stored token turns out to be valid, it is copied into
  `m.global.userToken` — the token in use can be an older one that a refresh
  elsewhere has already replaced.

POSTs are not wrapped in a helper. `GetLiveStream.brs`,
`GetPreviousLiveStreamVideo.brs` and `GetAuth.brs` each build their own
`roUrlTransfer` and call `AsyncPostFromString` directly.

`waitForAppToken()` (`common/Http.brs:10-25`) and `waitForUserToken()`
(`common/Http.brs:27-34`) busy-wait on `m.global.appClientId` /
`m.global.appBearerToken` / `m.global.userToken` being non-`invalid`. They are
unbounded spins with no timeout — if the upstream token never arrives, the
task thread hangs forever.

### Global state

Cross-component state is dumped onto `m.global` via `addFields` / `setField`.
Notable keys:

| Key | Meaning | Set at |
|---|---|---|
| `appClientId` | Twitch client id from `/apptoken` | `MainScene.brs:181` |
| `appBearerToken` | App-level OAuth bearer token | `MainScene.brs:182` |
| `userToken` | User OAuth token; `""` = anonymous, `invalid` = logged out / unset | `MainScene.brs`, `common/TwitchAuth.brs` |
| `videoQuality` | Index into the quality ladder (0 = 1080p60 … 6 = 160p). The index already encodes the framerate, so there is no separate one. | `MainScene.brs`, `Options.brs` |
| `chatOption` | Chat on/off — applied when the stream layout is set. The OK button during playback is a per-stream override on top of it. | `MainScene.brs`, `Options.brs` |
| `globalBadges` | Chat badge cache (Helix shape) | `ChatIrc.brs` |
| `globalTTVEmotes` | BetterTTV global emotes, keyed by code | `common/TwitchApi.brs` |
| `channelBadges` | Per-channel badges (Helix shape) | `ChatIrc.brs` |
| `channelTTVFrankerEmotes` | FrankerFaceZ channel emotes | `common/TwitchApi.brs` |

The recently-watched list is **not** on `m.global` — it lives in the
`LoggedInUserData` registry section under `RecentStreamers`
(`MainScene.brs:130`, written at `MainScene.brs:235`).

### Persistent state

Stored in `roRegistrySection`. Two sections matter:

- **`LoggedInUserData`** — `UserToken`, `RefreshToken`, `LoggedInUserName`
  (the Twitch *login*), `LoggedInUser` (the *display name* — written but only
  `Exists`-gated, never read), plus a `Reset` flag used to clear the section
  on first run after a known-bad state, and `RecentStreamers` (JSON blob of
  recently watched channels, capped at `m.maxRecents` = 20). `saveLogin` /
  `clearLogin` in `common/TwitchAuth.brs` are the entry points.
- **`VideoSettings`** — `VideoQuality`, `ChatOption`,
  `VideoBookmarks` (playback resume positions).

`MainScene.init` reads both at boot and seeds `m.global` from them.

**Every registry write must be flushed.** Writes are not committed until
`Flush()` is called, and each `roRegistrySection` is a snapshot — a write
staged on one instance is invisible to the next one, so a `Write` without a
`Flush` is silently lost. Use `setRegistrySection()` / `checkRegistrySection()`
from `common/Registry.brs`, which handle it. The whole registry is **32K
zlib-compressed**, so keep stored values small.

### Companion backend

The app does not talk to Twitch's private APIs directly for stream playback —
it relays through the Django service in `../backend/`, deployed at
`https://twoku-web.clstr.dev/`. The address comes from `BASE-URL` in the `env`
file at the root of the package, read by `common/Env.brs`:

- `GET /apptoken` — fetch app client id + bearer token (avoids shipping the
  client secret).
- `GET /register`, `POST /unregister` — device-code login flow.
- `POST /refresh` — exchange refresh token for new access token.
- `POST /getlivestream` — body `{twitch_channel, access_token, resolution}`;
  returns `stream_data.streams[<quality>].master`.
- `POST /getvod` — body `{video_id, access_token, resolution}`; same response
  shape.

The actual client secret lives in the backend, not on the device.

`common/Env.brs` is `<script>`-included by every component that builds a
backend URL. It has to be included wherever `common/TwitchAuth.brs` is, since
that file builds two of them.

Everything else — Helix browsing, search, followed channels, chat badges — is
fetched directly from Twitch by the app.

### Chat

Chat is fed by **plain Twitch IRC** (`irc.chat.twitch.tv:6667`, plain TCP) in
`ChatIrc.brs`. `Chat.brs` (the `Group` wrapper that owns the keyboard and
message panel) creates the `ChatIrc` task (`Chat.brs:5`) and renders the
IRCv3 tags.

- `ChatIrc.brs` — the transport. A `Task` that runs for the lifetime of the
  app, watches its own `channel` field and reconnects when it changes. It uses
  the documented `roStreamSocket` pattern: `SetMessagePort` + `notifyReadable`
  + `wait()`. **Nothing starts or stops it** — the chat panel's visibility
  deliberately has no say, because stopping the task races with its own
  startup and cancels it.
- An earlier EventSub WebSocket implementation of the chat transport has been
  **removed from the tree**. It could not have worked as it stood: its
  hand-rolled TLS offered TLS 1.2 with RSA key exchange only (no ECDHE, no
  TLS 1.3 suites) and no symmetric cipher. The cipher was *not* the real
  blocker — `roEVPCipher` has had `aes-gcm-128` since Roku OS 15.2 and TLS 1.3
  also allows `TLS_AES_128_GCM_SHA256`. What was missing is key agreement,
  server authentication and certificate handling. See
  [`.known_issues/tls-1.3-on-roku.md`](.known_issues/tls-1.3-on-roku.md) for
  the full analysis. The durable replacement is a backend relay — see
  [`.known_issues/backend-chat-relay.md`](.known_issues/backend-chat-relay.md).
- **The token must carry the legacy `chat:read` / `chat:edit` scopes.**
  Twitch's IRC server rejects a token with only the modern `user:read:chat` /
  `user:write:chat` names with "Login unsuccessful". The companion backend now
  requests both sets — but that change still has to be **deployed**, and the
  account has to **re-run the device-code login** afterwards, because the token
  already in the device's registry carries the old scopes. See
  [`.known_issues/twitch-chat.md`](.known_issues/twitch-chat.md).
- Chat badges come from `helix/chat/badges?broadcaster_id=<id>` (Helix shape:
  `data[].set_id`, `data[].versions[].image_url_1x`). The legacy
  `badges.twitch.tv` host no longer resolves. One fetch returns the global
  badges and the channel's own.
- Chat emotes come from two third-party APIs, fetched with `GETJSONPublic()`
  so the user's Twitch token is not sent to them. BetterTTV's
  `cached/users/twitch/<id>` endpoint — the source of the per-channel shared
  emotes — was retired upstream and now answers `404 {"message":"user not
  found"}` for every channel, so that feature has been dropped. The global
  BetterTTV list (`cached/emotes/global`) and the FrankerFaceZ list still
  work.

### VOD playback

The VOD scrubber has **no preview thumbnails**. Twitch does not expose the
storyboard spec through the documented API — Helix has no field for it, and
the GQL schema no longer has `storyboards` on `Video` — and
`usher.ttvnw.net/vod/storyboards/<id>-info.json` answers `403` with an empty
body for every credential shape, including the `nauth`/`nauthsig` pair that
comes with the playback URL. The code that derived the storyboard URL from
the playback URL's path and parsed it was removed; `GetPreviousLiveStreamVideo`
now only reports the video id, which is what the bookmark feature needs.

The Roku's HLS player will also **not start a fragmented-MP4 stream**, and
Twitch stores some broadcasts in that format and others as MPEG-TS — the
choice is per broadcast, and every rendition of a fragmented-MP4 broadcast is
fragmented MP4. There is no parameter that asks for the other container, so
the backend remuxes those segments to MPEG-TS on demand and serves them
from `/vodproxy/`. See the backend's README.

`components/common/WebSocket.brs` is an RFC-6455 BrightScript WebSocket
client. It is `ws://`-only: `roStreamSocket` has no native TLS, so a
`wss://` handshake would need a hand-rolled TLS stack that could not complete
one. The chat does not use it — plain IRC needs no WebSocket — but it is a
self-contained client that could talk to any plain WebSocket endpoint. Don't
modify it casually — the protocol code is hand-rolled.

## Known gaps / hazards

Documented, not fixed. Verify on-device before assuming any of these still
holds.

Fixes that are committed but **not yet verified on a device**, and the recipes
for verifying them, live in [`.known_issues/`](.known_issues/README.md).

Those files are published, so they never carry a real login, user id, display
name or channel name — the test account is described by the *properties* it
must have. Concrete values for your own runs belong in a `*.local.md`
companion, which is gitignored; no published file refers to one. See [the
conventions](.known_issues/README.md).

- **`common/TwitchAuth.brs`** — `refreshAppToken()` calls
  `waitForAppToken()`, which busy-waits on `m.global.appBearerToken`.
  `HomeScene.init` starts `GetStreams` before `MainScene.init` defines it, so
  the first browse request can abort on a type error.
- **`CustomVideo.brs`** — `VideoBookmarks` is assembled as a hand-built
  string, and the loop that writes it out is preceded by the insert of the
  new entry. Keep the insert before the loop and let the loop be the only
  thing that writes entries out — appending the new one again afterwards puts
  the same key in the JSON twice.

## BrightScript conventions used here

- `m.` is the component-instance scope (like `this.`). `m.top` is the SG node
  itself; `m.global` is the cross-scene singleton.
- `?` is `print` — used liberally for debug logging; keep matching style when
  adding logs.
- Field observation is the primary control flow: prefer `observeField` over
  polling. Setting a field with `alwaysNotify="true"` re-fires observers even
  when the value is unchanged.
- String formatting uses `roString.Format("%s/%s", a, b)` — the BrightScript
  `Format` method, not Python-style.
- The `loggedInUserName` field name is the canonical spelling for the
  authenticated user's login across components (recent refactor standardized
  this — don't reintroduce variants like `LoggedInUserName` as a field name,
  though it remains the registry key).
- The video quality ladder
  `["1080p60", "1080p", "720p60", "720p", "480p", "360p", "160p"]` is
  duplicated in `Options.brs:10`, `GetLiveStream.brs:48`, and
  `GetPreviousLiveStreamVideo.brs:78`, and mirrored again as UI labels in
  `Options.xml:45-72`. The latter two carry a `TODO` to read it from Options
  instead of re-hardcoding it. The index into the ladder encodes the
  framerate — `1080p60` and `1080p` are the same resolution at different
  rates — so there is no separate framerate setting. Twitch names its
  renditions by their real rate (`480p30`, `360p30`), so the backend adds
  the app's name as an alias for the closest match — otherwise the lookup
  in `GetLiveStream.brs` and `GetPreviousLiveStreamVideo.brs` misses and
  the stream never starts.

## Branch / commit style

Working branches are dated: `YYYY_MM_DD_<Topic>` (e.g.
`2026_11_11_GitHub_Actions_Release`). Commit messages are short imperative
summaries; squash-style "what + why" in a single line is typical. The trunk is
`main`.
