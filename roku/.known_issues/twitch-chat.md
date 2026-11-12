# Twitch chat — root cause, the backend change, and what is still parked

## Status

- **Fixed:** 2026-10-29 — the chat panel is fed by plain Twitch IRC again
- **Needs a backend change:** the token Twitch's IRC server accepts is not the
  token the backend currently mints. See the diff below.
- **Still parked:** the EventSub WebSocket path. See
  [backend-chat-relay.md](backend-chat-relay.md) for the durable replacement.

---

## Why the chat box was empty

There were **five** independent faults stacked on top of each other. Any one of
them alone would have produced an empty chat box.

### 1. The transport could not connect (EventSub WebSocket)

`ChatLog` used the vendored `WebSocketClient` to reach
`wss://eventsub.wss.twitch.tv/ws`. On device:

```
TlsUtil: Sending: 16030300660100006203036AE29CDC8D8C40E1C35EBAB92E1F0DADBF0969308EE0158C46F28BF13F18C05F000008009C009D003C003D010000...
TlsUtil: Received fragment of type 21: 0100
[DEBUG] TlsUtil: Handshake timed out
WebSocket error message: "TLS error"
```

Decoding that ClientHello: version **TLS 1.2**, and the cipher suites are
`0037 009C 009D 003C 003D 0100` — `TLS_RSA_WITH_AES_128_CBC_SHA`,
`..._AES_128_GCM_SHA256`, `..._AES_256_GCM_SHA384`, `..._AES_256_CBC_SHA`,
`..._AES_128_CBC_SHA256` and `TLS_NULL_WITH_NULL_NULL`. **RSA key exchange
only — no ECDHE, and no TLS 1.3 suites.** Twitch's EventSub endpoint requires
TLS 1.3.

It could not have been fixed on the device either:

- `components/web_socket_client/ByteUtil.brs` has **no symmetric cipher** — only
  RSA and modular arithmetic — so records could never be decrypted.
- The cipher itself is **not** the blocker. `roEVPCipher` has had
  `aes-gcm-128` since Roku OS 15.2 (the device here runs 15.3.4) and TLS 1.3
  also allows `TLS_AES_128_GCM_SHA256` (0x1301). What is missing is key
  agreement (X25519 ECDHE), server authentication (signature verification and
  X.509 chain validation) and GCM record framing. A TLS 1.3 skeleton with
  exactly those gaps stubbed is parked in the stash — see
  [stashed-websocket-client.md](stashed-websocket-client.md).

### 2. The chat task was stopped before it ever ran

Even with a working transport, the Task was cancelled. `Chat` watched the
panel's `visible` property:

```brightscript
sub onInvisible()
    if m.top.visible = false
        m.chat.control = "stop"
    else
        m.chat.control = "run"
    end if
end sub
```

The chat panel is **hidden at startup**, so this fired immediately after the
task was started and stopped it again. A `stop` that arrives before the
thread has run cancels it for good — the task's function never executed, and
the task's `state` still read `run`.

`onEnterChannel` had the same shape (`control = "stop"` then `control =
"run"`), which is a race with the task's own startup in the best case.

**Fix:** the transport now runs for the lifetime of the app. It watches its own
`channel` field and reconnects itself when the channel changes, so nothing
starts or stops it. The panel's visibility no longer has any say in it.

### 3. The subscription was never created

`ChatLog.subscribeToChat` built the subscription body and then issued a **GET**
to `helix/eventsub/subscriptions`. Twitch requires a **POST** with that body.
The body was never sent.

### 4. The user id was never plumbed through

The subscription's `condition.user_id` came from `Chat.loggedInUserId`, which
**nothing ever writes** — `MainScene` sets `m.chat.loggedInUserName` only. The
underlying registry key `LoggedInUserId` is likewise never written.

### 5. Messages never reached the renderer

`ChatLog.on_message` printed the message but **never set `nextComment`** — the
only field `Chat.brs` observes. Even a working socket would have rendered
nothing. `Chat.brs` also parsed the IRCv3 tag format, while EventSub delivers
JSON.

---

## The fix

The chat now uses **plain Twitch IRC** (`irc.chat.twitch.tv:6667`). It is
plain TCP, so no TLS is involved and the Roku platform is not a constraint.
The renderer in `Chat.brs` was already written for the IRCv3 tag format, so it
was repaired rather than replaced.

### The token scope problem

Twitch's IRC server authenticates **only** against the *legacy* `chat:read` /
`chat:edit` scopes. A token carrying the modern `user:read:chat` /
`user:write:chat` names — which is what the backend mints — is rejected:

```
:tmi.twitch.tv NOTICE * :Login unsuccessful
```

Verified on the same account, same server, same nick, changing only the
scopes:

| Token scopes | Result |
|---|---|
| `user:read:chat user:write:chat` | `Login unsuccessful` |
| `chat:read chat:edit` | `:tmi.twitch.tv 001 <login> :Welcome, GLHF!` |

Both sets can be requested at once — the device-code endpoint accepts
`chat:read chat:edit user:read:chat user:write:chat` — so the same token can
serve both IRC and EventSub.

### Backend change required

In `backend/authhandler/views.py`:

```diff
--- a/authhandler/views.py
+++ b/authhandler/views.py
@@ -55,12 +55,19 @@ def register(request):
     logger.info(f"request.META.REMOTE_ADDR: {(request.META.get('REMOTE_ADDR'))}")
     try:
         # Request device code from Twitch
+        # Twitch's IRC endpoint (irc.chat.twitch.tv:6667) still authenticates
+        # only against the legacy chat:read / chat:edit scopes - a token
+        # carrying just the modern user:read:chat / user:write:chat names is
+        # rejected with "Login unsuccessful". Request both sets so the same
+        # token works for IRC and for EventSub.
         scopes = [
             'user:read:email',
             'user:read:follows',
             'user:read:chat',
-            'user:write:chat',            
+            'user:write:chat',
+            'chat:read',
+            'chat:edit',
         ]
         
         device_response = requests.post(
@@ -117,10 +124,11 @@ def unregister(request):
         # Post to Twitch token endpoint
         token_response = requests.post(
             'https://id.twitch.tv/oauth2/token',
             data={
                 'client_id': settings.TWITCH_CLIENT_ID,
-                'scope': 'channel:manage:broadcast',
+                # No scope here: for the device_code grant the scopes come from
+                # the original /register request. This parameter was ignored.
                 'device_code': device.device_code,
                 'grant_type': 'urn:ietf:params:oauth:grant-type:device_code'
             }
         )
```

After deploying the backend, **re-run the device-code login** — the token
already in the device's registry carries the old scopes, and only a fresh
`/register` mints the new set.

---

## What changed on the device side

| File | Change |
|---|---|
| `components/ChatTest.brs` → `components/ChatIrc.brs` | Renamed, and rewritten. It used a hot `while true` loop reading the socket a character at a time; it now uses the documented `roStreamSocket` pattern — `SetMessagePort` + `notifyReadable` + `wait()` — with an accumulator so a line split across two TCP reads is not published half-formed. It runs for the lifetime of the app and reconnects when its `channel` field changes. Messages are queued and handed to the renderer one at a time. |
| `components/ChatTest.xml` → `components/ChatIrc.xml` | Renamed. |
| `components/Chat.brs` | Now creates `ChatIrc` instead of `ChatLog`, starts it once, and no longer stops it when the panel is hidden. The IRC line parser was rewritten (see below), and badge lookup now uses the Helix shape. |
| `components/ChatLog.brs` | The EventSub transport, removed from this repository's tree — it was never committed here. It survives only in the pre-merge clone `twitch-reloaded-roku` and in the parked stash; see [stashed-websocket-client.md](stashed-websocket-client.md). |

### Verified on device

With the transport pointed at a live channel:

```
ChatIrc > chat transport started
ChatIrc > connected to irc.chat.twitch.tv:6667
ChatIrc >> JOIN > legendsofavantris
ChatIrc > :tmi.twitch.tv NOTICE * :Login unsuccessful
ChatIrc > socket closed
```

The Roku **can** open a TCP connection to Twitch's IRC server — that was the
biggest unknown. `Login unsuccessful` is the expected result with the token
the backend currently mints; it is the scope problem above, not the transport.

### The renderer had real parsing bugs

Simulating the old parser against a real captured line:

| Field | Old result | Now |
|---|---|---|
| `display_name` | `'=Martineli426'` (kept the `=`) | `Martineli426` |
| `color` | `'=#FF69B4'` (kept the `=`) | `FF69B4` |
| `badges` | `['=subscriber/3', …]` | `['subscriber/3', …]` |
| `message` | `'l'` — **chopped by four characters** | the full text |

The old code split the whole line on `;`, so **a message containing a
semicolon was truncated** as well. The line is now split at the first `" :"`
(tags versus message) and only then are the tags split on `;`. The emote
offsets in the `emotes` tag are relative to the message without its leading
`:`, which the corrected extraction also fixes.

### The badge endpoints had moved

`badges.twitch.tv` **no longer resolves** — the legacy badge API the old code
used is gone. The replacement is `helix/chat/badges?broadcaster_id=<id>`, which
requires a user token with chat scopes and returns
`data[].set_id` / `data[].versions[].id` / `data[].versions[].image_url_1x`. One
fetch returns the global badges *and* the channel's own.

---

## Still to verify on a device

- **The message rendering**, once the backend has been changed and the account
  has re-logged in. The transport, the parser and the badge lookup have all been
  checked; what has not been seen is a real message drawn in the chat panel.
- **The send path** (`chat:edit`). **No chat message was ever sent while
  developing this** — every test was `CAP REQ` / `PASS` / `NICK` / `JOIN` plus
  reads.
- The IRC connection now stays up while the chat panel is hidden. That is
  deliberate — reconnecting is slow — but it means a channel that is no longer
  being watched keeps its connection until another one is opened.
