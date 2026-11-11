# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Twoku — an unofficial Twitch client for Roku, written in BrightScript on the SceneGraph framework. The original developers were learning Roku as they went, so the code is intentionally messy in places and not consistently organized.

This file covers the Roku application. It lives at `roku/` in a monorepo that also contains the companion Django service at `backend/`. Paths below are relative to `roku/`.

## Build / Run / Deploy

There is no build system, test framework, or linter. The source tree *is* the deployable artifact.

- **Sideload to a Roku in dev mode** — the BrightScript VSCode extension needs to know your device and where the app lives. `.vscode/` is gitignored, so create a local `.vscode/settings.json` at the repo root:
  ```json
  {
      "brightscript.devices": [
          { "host": "<device-ip>", "serialNumber": "<serial>", "password": "<dev-password>" }
      ],
      "brightscript.projects": ["roku"]
  }
  ```
  `brightscript.projects` is needed because the app is in `roku/`, not at the workspace root. Use the extension's "Launch" action to push the tree to the device.
- **Manual install** — ZIP the *contents* of `roku/` (no top-level directory) and upload via the Roku dev web UI at `http://<roku-ip>`. `package.sh` does this and lists exactly what goes in; `*.zip` is gitignored. It also copies `env.example` to `env` if `env` is missing, so a fresh clone can package immediately.
- **manifest** — `title=TwokuDev`, `major_version=0`, `minor_version=9`, `rsg_version=1.3` identify the dev build. Bump `minor_version` / `build_version` on releases.
- **`env`** — holds `BASE-URL`, the address of the backend this build talks to. It ships inside the package and is read at runtime from `pkg:/env` by `common/Env.brs`. The file is not committed — `env.example` is the template and `env` is gitignored, because each deployment has its own. `package.sh` copies `env.example` to `env` if it is missing, so a fresh clone packages and runs against the upstream deployment; edit `env` to point somewhere else. The URL is baked into the package, so changing it needs a rebuild.

To verify a change, sideload and walk the affected screen on a real device — there is no headless way to exercise the SceneGraph.

- **Compile check** — Roku's own BrightScript compiler runs without a device and catches the errors that stop the app installing:

  ```bash
  npx --yes -p brighterscript@latest bsc --root-dir roku \
      --create-package false --copy-to-staging false --diagnostic-level error
  ```

  It exits non-zero and names the file and line. **Run it before sideloading** — the device reports a compile failure only as a component name (`Install Failure: Compilation Failed.\nGetUser`), with no line number, so a mistake is otherwise only found after a failed install.

## Architecture

### Entry and scene graph

`source/main.brs` does the bare minimum: create an `roSGScreen`, instantiate the `MainScene` component, and pump the event loop. Everything else lives in `components/`.

Each SceneGraph component is a pair: `Foo.xml` declares the node (extends `Group`, `Scene`, `Video`, or `Task`) plus its `<interface>` fields and child nodes; `Foo.brs` holds the behavior. The `<interface>` field list is the contract between components — the parent reads/writes them, often via `alias=` so a child field shows through on the parent.

`MainScene` is the router. It owns the top-level scenes (`HomeScene`, `CategoryScene`, `LoginPage`, `Chat`, `CustomVideo`, `KeyboardGroup`, `Options`) and switches between them by toggling `visible`. Scene transitions are driven by `observeField` on cross-scene fields like `streamUrl`, `streamerSelectedName`, `categorySelected`, `buttonPressed`.

**Init ordering matters.** XML children are constructed — and their `init()` runs — *before* `MainScene.init()`. So `HomeScene.init()` fires first and starts `GetStreams` before `MainScene.init()` has defined `m.global.userToken`. That is why the token waits below exist and why they are unbounded busy-waits.

### `Get*` Task nodes = async HTTP layer

Every component named `Get<Something>` is a `Task` node. The pattern is always:

1. Caller creates the node with `createObject("roSGNode", "GetX")`, sets input fields, observes an output field, then sets `control = "RUN"`.
2. The task runs `m.top.functionName` on a background thread, fetches/parses, writes the result to an output field.
3. The observer fires on the render thread.

Tasks cannot touch the UI directly — they communicate only through their interface fields.

| Task | Entry fn | Output field(s) | Instantiated by |
|---|---|---|---|
| `GetToken` | `onStreamerChange` | `appClientId`, `appBearerToken` | `MainScene.brs:43` |
| `GetUser` | `onSearchTextChange` | `searchResults`, `currentlyLiveStreamerIds` | `MainScene.brs:48` |
| `GetAuth` | `onStreamerChange` | `code`, `finished` | `LoginPage.brs:4` |
| `GetSearch` | `onSearchTextChange` | `searchResults` | `KeyboardGroup.brs:20` |
| `GetCategorySearch` | `onSearchTextChange` | `searchResults` | `KeyboardGroup.brs:23` |
| `GetCategories` | `onSearchTextChange` | `searchResults` | `HomeScene.brs:55` |
| `GetStreams` | `onSearchTextChange` | `searchResults` | `HomeScene.brs:49`, `CategoryScene.brs:15` |
| `GetClips` | `onSearchTextChange` | `searchResults` | `CategoryScene.brs:18` |
| `GetOfflineFollowedChannels` | `onSearchTextChange` | `offlineFollowedUsers` | `HomeScene.brs:58` |
| `GetLiveStream` | `onStreamerChange` | `streamUrl` | `HomeScene.brs:52`, `CategoryScene.brs:21`, `KeyboardGroup.brs:26`, `ChannelPage.brs:27` |
| `GetPreviousLiveStreamVideo` | `onStreamerChange` | `streamUrl`, `thumbnailInfo` | `ChannelPage.brs:30` |
| `GetUserChannel` | `onSearchTextChange` | `searchResults`, `streamDurationSeconds` | `ChannelPage.brs:21` |
| `GetVideos` | `onSearchTextChange` | `searchResults` | `ChannelPage.brs:24` |

**Dead UI inside a live component** — `HomeScene.browseOfflineFollowingList` (`HomeScene.xml:176-187`) is a RowList whose content is rebuilt on every refresh but which is never made visible: every `visible = true` for it is commented out (`HomeScene.brs:308`). The visible offline list is the `OfflineChannelList` component, not this RowList.

`ChannelPage` is instantiated by `HomeScene.xml:196`, **not** by `MainScene.xml` (whose instance is commented out at `MainScene.xml:36-38`).

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

- `GetUser` also returns `currentlyLiveStreamerIds` (an assocarray of `user_id → true`). `GetOfflineFollowedChannels` uses it to subtract the live streamers from the followed list.
- `HomeScene.onGetFollowedStreams` is driven by a change to `HomeScene.currentlyLiveStreamerIds` (`HomeScene.brs:66`) — that is the only thing that kicks off the offline lookup.
- **`loggedInUserName` vs `loggedInUserLogin`**: `HomeScene.loggedInUserName` is the *display name* shown in the header, `HomeScene.loggedInUserLogin` is the *login*. The offline task looks the user up with `helix/users?login=`, so it must be given the login.
- `followed_users` items carry `game_name` (not `game_id`) — the Helix streams response includes the category name, so there is no id→name lookup.
- `m.numRowsInFollowingList` is the **number of rows** in the live-follows grid. The offline list is revealed when the last row is focused, or immediately when there are no live follows.

### Shared helpers (`components/common/`)

The old monolithic `components/UrlFunctions.brs` no longer exists — it was split into per-concern files under `components/common/`. Helpers are **not global**: each component's XML `<script>`-includes only the files it needs, so a helper is only in scope inside the component that included it.

| File | Provides |
|---|---|
| `common/Http.brs` | `newUrlTransfer()`, `waitForAppToken()`, `waitForUserToken()` |
| `common/TwitchAuth.brs` | `createUrl()`, `createUserUrl()`, `GETJSON()`, `validateToken()`, `refreshToken()`, `refreshUserToken()`, `refreshAppToken()`, `getUserRefreshToken()`, `saveLogin()`, `clearLogin()` |
| `common/TwitchApi.brs` | `lookupUserByLogin()`, `lookupUserByLoginAuthed()`, `ensureGlobalBTTVEmotes()`, `ensureChannelBTTVEmotes()`, `ensureChannelFFZEmotes()` |
| `common/TwitchImages.brs` | `resizeTwitchImageUrl()` |
| `common/Format.brs` | `formatCountAbbrev()`, `secondsSinceISO8601()`, `formatElapsedHMS()` |
| `common/Registry.brs` | `checkRegistrySection()`, `setRegistrySection()` — included by `MainScene.xml` only, so these are in scope in `MainScene` alone |
| `common/Env.brs` | `getBackendBaseUrl()` — reads `BASE-URL` from `pkg:/env`. See the Companion backend section. |
| `common/WebSocket.brs` | RFC-6455 WebSocket client, `ws://` only. See the Chat section. |

Always go through these helpers rather than building `roUrlTransfer` by hand — they centralize cert setup, header injection (Client-ID + bearer), and the user-token-vs-app-token fallback:

- `createUrl()` — authed transfer; prefers user token, falls back to app token.
- `createUserUrl()` — authed transfer; returns `invalid` if no user token (use for endpoints that require user auth).
- `GETJSON(link)` — one-shot GET + parse.
- `validateToken`, `refreshToken`, `refreshUserToken`, `refreshAppToken` — token lifecycle; the refresh path round-trips through the companion backend.

POSTs are not wrapped in a helper. `GetLiveStream.brs`, `GetPreviousLiveStreamVideo.brs` and `GetAuth.brs` each build their own `roUrlTransfer` and call `AsyncPostFromString` directly.

`waitForAppToken()` / `waitForUserToken()` (`common/Http.brs:10-23`) busy-wait on `m.global.appClientId` / `m.global.appBearerToken` / `m.global.userToken` being non-`invalid`. They are unbounded spins with no timeout — if the upstream token never arrives, the task thread hangs forever.

### Global state

Cross-component state is dumped onto `m.global` via `addFields` / `setField`. Notable keys:

| Key | Meaning | Set at |
|---|---|---|
| `appClientId` | Twitch client id from `/apptoken` | `MainScene.brs:181` |
| `appBearerToken` | App-level OAuth bearer token | `MainScene.brs:182` |
| `userToken` | User OAuth token; `""` = anonymous, `invalid` = logged out / unset | `MainScene.brs:108`/`:110`, `common/TwitchAuth.brs:168`, `common/TwitchAuth.brs:192` |
| `videoQuality` | Index into the quality ladder (0 = 1080p60 … 6 = 160p) | `MainScene.brs:84`/`:86`, `Options.brs:46` |
| `videoFramerate` | 30 or 60 — persisted but never consumed by playback | `MainScene.brs:92`/`:94`, `Options.brs:48`/`:50` |
| `chatOption` | Chat on/off — persisted but not wired to chat visibility (see gaps) | `MainScene.brs:100`/`:102`, `Options.brs:69` |
| `globalBadges` | Chat badge cache (Helix shape) | `ChatIrc.brs` |
| `globalTTVEmotes` | BetterTTV global emotes, keyed by code | `common/TwitchApi.brs:35` |
| `channelBadges` | Per-channel badges (Helix shape) | `ChatIrc.brs` |
| `channelTTVEmotes` | BetterTTV channel-shared emotes | `common/TwitchApi.brs:47`/`:49` |
| `channelTTVFrankerEmotes` | FrankerFaceZ channel emotes | `common/TwitchApi.brs:61`/`:63` |
| `recentChannels` | Recently watched — write path is unreachable (see gaps) | `GetOfflineFollowedChannels.brs:13` |

### Persistent state

Stored in `roRegistrySection`. Two sections matter:

- **`LoggedInUserData`** — `UserToken`, `RefreshToken`, `LoggedInUserName` (the Twitch *login*), `LoggedInUser` (the *display name* — written but only `Exists`-gated, never read), plus a `Reset` flag used to clear the section on first run after a known-bad state, and `RecentStreamers` (JSON blob of recently watched channels, capped at `m.maxRecents` = 20). `saveLogin` / `clearLogin` in `common/TwitchAuth.brs` are the entry points.
- **`VideoSettings`** — `VideoQuality`, `VideoFramerate`, `ChatOption`, `VideoBookmarks` (playback resume positions).

`MainScene.init` reads both at boot and seeds `m.global` from them.

**Every registry write must be flushed.** Writes are not committed until `Flush()` is called, and each `roRegistrySection` is a snapshot — a write staged on one instance is invisible to the next one, so a `Write` without a `Flush` is silently lost. Use `setRegistrySection()` / `checkRegistrySection()` from `common/Registry.brs`, which handle it. The whole registry is **32K zlib-compressed**, so keep stored values small.

### Companion backend

The app does not talk to Twitch's private APIs directly for stream playback — it relays through the Django service in `../backend/`, deployed at `https://twoku-web.clstr.dev/`. The address comes from `BASE-URL` in the `env` file at the root of the package, read by `common/Env.brs`:

- `GET /apptoken` — fetch app client id + bearer token (avoids shipping the client secret).
- `GET /register`, `POST /unregister` — device-code login flow.
- `POST /refresh` — exchange refresh token for new access token.
- `POST /getlivestream` — body `{twitch_channel, access_token, resolution}`; returns `stream_data.streams[<quality>].master`.
- `POST /getvod` — body `{video_id, access_token, resolution}`; same response shape.

The actual client secret lives in the backend, not on the device.

`common/Env.brs` is `<script>`-included by every component that builds a
backend URL. It has to be included wherever `common/TwitchAuth.brs` is, since
that file builds two of them.

Everything else — Helix browsing, search, followed channels, chat badges — is fetched directly from Twitch by the app.

### Chat

Chat is fed by **plain Twitch IRC** (`irc.chat.twitch.tv:6667`, plain TCP) in `ChatIrc.brs`. `Chat.brs` (the `Group` wrapper that owns the keyboard and message panel) renders the IRCv3 tags.

- `ChatIrc.brs` — the transport. A `Task` that runs for the lifetime of the app, watches its own `channel` field and reconnects when it changes. It uses the documented `roStreamSocket` pattern: `SetMessagePort` + `notifyReadable` + `wait()`. **Nothing starts or stops it** — the chat panel's visibility deliberately has no say, because stopping the task races with its own startup and cancels it.
- `ChatLog.brs` — the EventSub rewrite, **parked**. It cannot work as it stands: the vendored `WebSocketClient` offers TLS 1.2 with RSA key exchange only (no ECDHE, no TLS 1.3 suites), and `ByteUtil.brs` has no symmetric cipher at all. The cipher is *not* the real blocker — `roEVPCipher` has had `aes-gcm-128` since Roku OS 15.2 and TLS 1.3 also allows `TLS_AES_128_GCM_SHA256`. What is missing is key agreement, server authentication and certificate handling; the stashed TLS 1.3 skeleton has those stubbed. See [`.known_issues/stashed-websocket-client.md`](.known_issues/stashed-websocket-client.md). The durable replacement is a backend relay — see [`.known_issues/backend-chat-relay.md`](.known_issues/backend-chat-relay.md).
- **The token must carry the legacy `chat:read` / `chat:edit` scopes.** Twitch's IRC server rejects a token with only the modern `user:read:chat` / `user:write:chat` names with "Login unsuccessful". The companion backend mints the modern names — the diff to add both is in [`.known_issues/twitch-chat.md`](.known_issues/twitch-chat.md).
- Chat badges come from `helix/chat/badges?broadcaster_id=<id>` (Helix shape: `data[].set_id`, `data[].versions[].image_url_1x`). The legacy `badges.twitch.tv` host no longer resolves. One fetch returns the global badges and the channel's own.

`components/common/WebSocket.brs` is an RFC-6455 BrightScript WebSocket client, salvaged from the parked stash. It is `ws://`-only: the hand-rolled TLS that was in `components/web_socket_client/` could not complete a handshake, and `roStreamSocket` has no native TLS. Don't modify it casually — the protocol code is hand-rolled.

## Known gaps / hazards

Documented, not fixed. Verify on-device before assuming any of these still holds.

Fixes that are committed but **not yet verified on a device**, and the recipes for verifying them, live in [`.known_issues/`](.known_issues/README.md).

Those files are published, so they never carry a real login, user id, display name or channel name — the test account is described by the *properties* it must have. Concrete values for your own runs belong in a `*.local.md` companion, which is gitignored; no published file refers to one. See [the conventions](.known_issues/README.md).

- **`GetLiveStream.brs:51-58`** — the request assoc array has a malformed literal (a stray `"` before `"resolution": "720p60"`), so the JSON body posted to `/getlivestream` is invalid.
- **`common/TwitchAuth.brs:90`** — `refreshAppToken()` calls `waitForAppToken()`, which busy-waits on `m.global.appBearerToken`. `HomeScene.init` starts `GetStreams` before `MainScene.init` defines it, so the first browse request can abort on a type error.
- **`common/TwitchAuth.brs:192`** — `clearLogin()` sets `m.global.userToken = invalid`, which makes `waitForUserToken()` spin forever. Logging out wedges every subsequent API call (and `createUrl()` waits on the user token even though it has an app-token fallback).
- **`common/TwitchAuth.brs:165`** — writes the registry key `LoggedInUserId`, and `GetUser.brs` reads it. Verify the write actually happens on the path that reads it.
- **`MainScene.brs:91`** — copy/paste bug: tests `videoQuality <> invalid` where it means `videoFramerate`, so the saved framerate is ignored and `videoFramerate` always resets to 60.
- **`CustomVideo.brs:215-253`** — `VideoBookmarks` is assembled as a hand-built string. When a bookmark is new, `tempBookmarks` is updated at `CustomVideo.brs:218` *before* the loop at `:225-231` runs, so the new entry is emitted twice — once by the loop and again by the append at `:253` — producing a duplicate JSON key. The closing `}` is appended correctly in both branches; it is the duplicate, not a stray brace, that is suspect.
- **`MainScene.brs:373`** — the `chatOption` → chat-visibility wiring is commented out, so the Options toggle has no effect.
- **`GetOfflineFollowedChannels.brs:13-14`** — reads registry key `RecentChannels`, which is never written, so `m.global.recentChannels` is never initialized.
- **`GetPreviousLiveStreamVideo.brs:13`** — `extractThumbnailUrl` derives the storyboard URL from the stream URL's path, but the master URL now comes from the backend as `https://usher.ttvnw.net/vod/v2/<id>.m3u8`, so the derived storyboard path is wrong and `ParseJSON` fails with "Data is empty". VOD scrubbing thumbnails are lost. Found on device.

## BrightScript conventions used here

- `m.` is the component-instance scope (like `this.`). `m.top` is the SG node itself; `m.global` is the cross-scene singleton.
- `?` is `print` — used liberally for debug logging; keep matching style when adding logs.
- Field observation is the primary control flow: prefer `observeField` over polling. Setting a field with `alwaysNotify="true"` re-fires observers even when the value is unchanged.
- String formatting uses `roString.Format("%s/%s", a, b)` — the BrightScript `Format` method, not Python-style.
- The `loggedInUserName` field name is the canonical spelling for the authenticated user's login across components (recent refactor standardized this — don't reintroduce variants like `LoggedInUserName` as a field name, though it remains the registry key).
- The video quality ladder `["1080p60", "1080p", "720p60", "720p", "480p", "360p", "160p"]` is duplicated in `Options.brs:10`, `GetLiveStream.brs:48`, and `GetPreviousLiveStreamVideo.brs:78`. The latter two carry a `TODO` to read it from Options instead of re-hardcoding it.

## Branch / commit style

Working branches are dated: `YYYY_MM_DD_<Topic>` (e.g. `2026_05_01_Fix_Following`). Commit messages are short imperative summaries; squash-style "what + why" in a single line is typical. The trunk is `main`.
