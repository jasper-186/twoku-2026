# Future feature — chat over a backend relay

## Status

- **Deferred:** 2026-10-29
- **Why:** Twitch is sunsetting IRC. The IRC transport in `ChatIrc` works today,
  but it is a dead end.
- **Blocked on:** a change to the companion backend, which lives in this same
  repository under `backend/`.

## The problem

The Roku has no way to open a TLS 1.3 WebSocket to Twitch. That is not a
shortage of effort in this app — the platform does not expose the primitives:

| Need | Roku offers |
|---|---|
| TLS 1.3 to a WebSocket endpoint | No native TLS socket. `roUrlTransfer` does TLS for HTTP only. |
| A symmetric cipher for TLS 1.3 | `roEVPCipher` has AES-128/192/256 in CBC/CFB/ECB/OFB and `aes-gcm-128` (OS 15.2+). TLS 1.3 also allows `TLS_AES_128_GCM_SHA256`, so the cipher is **not** the blocker. |
| Key agreement | No X25519, and no ECDH of any kind. |
| Server authentication | Certificate chain validation and signature verification over the transcript hash are not available. |
| A hand-rolled TLS 1.3 stack | Not present in this repository, and not attempted further. The analysis of what it would require is in [tls-1.3-on-roku.md](tls-1.3-on-roku.md). |

So the platform *could* be taught TLS 1.3, but it would mean implementing
Curve25519, signature verification and X.509 parsing in BrightScript — a large
job with a poor return, when the backend already speaks TLS 1.3 for free.

## The shape of the fix

**Move the Twitch-side connection to the backend, which already has full TLS.**

The app already talks to `twoku-web.clstr.dev` for everything it cannot do
itself — `/apptoken`, `/register`, `/unregister`, `/refresh`, `/getlivestream`,
`/getvod`. The backend shells out to `streamlink` for the stream links. Chat
fits that pattern.

```
Roku app                          Backend                      Twitch
   |                                  |                            |
   |  POST /chat {channel, token}     |                            |
   |--------------------------------->|  open EventSub WebSocket   |
   |                                  |--------------------------->|
   |                                  |  subscribe to              |
   |                                  |  channel.chat.message      |
   |                                  |                            |
   |  GET /chat?channel=X&since=N    |                            |
   |--------------------------------->|  buffer of messages        |
   |<---------------------------------|  since N                    |
```

### Backend work

1. **An EventSub WebSocket client.** Python with `websockets` or `aiohttp` gets
   TLS 1.3 for free.
   - Connect to `wss://eventsub.wss.twitch.tv/ws`.
   - On the `session_welcome` message, take `payload.session.id`.
   - `POST https://api.twitch.tv/helix/eventsub/subscriptions` with the app's
     **user access token** (the WebSocket transport requires a user token, not
     an app token), `type: channel.chat.message`, `version: 1`,
     `condition: { broadcaster_user_id, user_id }` and
     `transport: { method: "websocket", session_id }`.
   - `user_id` is the *signed-in* user's id. The device has it at runtime:
     `MainScene` passes `m.getUser.searchResults.id` to the chat component.
     The backend will need its own copy of the id, which it can take from the
     token's `/validate` response.
   - Subscribe within 10 seconds of the welcome message or Twitch closes the
     socket.
2. **A per-channel buffer** of recent messages with a monotonically increasing
   id, and an endpoint that returns everything after a given id. Keep the
   buffer bounded — chat is fast.
3. **A long-poll endpoint.** `GET /chat?channel=X&since=N` that holds the
   request until a message arrives or a timeout (say 25 seconds) expires. The
   Roku's `roUrlTransfer` handles a slow HTTPS response fine, and this needs no
   new transport on the device.

### Device work

1. Replace the `roStreamSocket` transport in `ChatIrc` with a poll loop against
   the backend.
2. **The renderer has to change.** EventSub delivers JSON
   (`payload.event.chatter.display_name`, `payload.event.message.text`,
   `payload.event.chatter.color`, `payload.event.chatter.badges`,
   `payload.event.message.emotes`), not IRCv3 tags. `Chat.brs`'s parser would
   be rewritten against the JSON shape. The badge lookup would move to
   `helix/chat/badges?broadcaster_id=…` (the legacy `badges.twitch.tv` host no
   longer resolves — see [twitch-chat.md](twitch-chat.md)).

### Why this is worth doing even though IRC works

- Twitch's IRC endpoint is deprecated and will go away.
- EventSub is the supported path, and it also gives user notices, subs,
  raids and cheers — none of which IRC exposes cleanly.
- It removes the Roku TLS ceiling entirely: the platform only ever needs
  plain HTTPS, which it already does well.

### A cheaper intermediate

If the backend cannot take on a WebSocket client yet, the backend could
**proxy plain IRC** instead — it opens `irc.chat.twitch.tv:6667`, buffers what
it reads, and the app polls it over HTTPS. That keeps the device-side renderer
on the IRC tag format (no JSON rewrite) while moving the connection off the
platform. It needs the same `chat:read` / `chat:edit` scopes, and it inherits
IRC's deprecation, but it is a much smaller change than the EventSub version.
