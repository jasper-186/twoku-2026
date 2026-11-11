# Stashed WebSocket client — parked, do not resurrect blindly

## Status

- **Parked:** 2026-10-29, at the user's request
- **Where it lives:** in the pre-merge clone, `twitch-reloaded-roku`, which is
  retained unchanged:
  - branch `tls13-webclient` — tip `3f0a2c19743567f4ff89b3cc6cd509c3b412c979`,
    message *"Original attempt to upgrade the Chat to the websocket client"*,
    authored 2026-06-23 08:40 -0500, from the state at `1310648`,
    7 files, +1646 / −921.
  - the same commit is also `stash@{0}` in that clone, so it is recoverable
    from either.
  - The merge into this repository squashed the history, so the commit is not
    in this repository's object database. Both the branch and the stash entry
    live in the old clone only — **they are not on any remote**, so if that
    clone is deleted the work is gone.

## What it is

| File | Change |
|---|---|
| `components/web_socket_client/TlsUtil.brs` | Rewritten as a **TLS 1.3 (RFC 8446) skeleton** by Joseph Echtenkamp, 2026-05-29. The key schedule (HKDF-Extract / HKDF-Expand-Label / Derive-Secret) and transcript hashing are implemented over `roEVPDigest`. |
| `components/web_socket_client/WebSocket.brs` | **New, 546 lines** — a clean RFC 6455 WebSocket client, event-driven through a message port. |
| `components/web_socket_client/ByteUtil.brs` | +48 lines |
| `components/web_socket_client/WebSocketClient.brs`, `WebSocketClientTask.brs` | Wiring for the new client |
| `components/Chat.xml`, `components/ChatLog.brs` | Chat wiring |

Its own header is the best summary of where it got to:

> "The large remaining primitives — X25519 ECDHE, AES-128-GCM AEAD, RSA/ECDSA
> signature verification, and ASN.1 / X.509 parsing — are explicitly stubbed
> and tagged UNIMPLEMENTED. […] The structure is laid out so each stub can be
> filled in independently."

And the new WebSocket client's header says:

> "Supports ws:// only. wss:// will fail with an on_error event explaining why
> (Roku's roStreamSocket has no TLS and the in-repo hand-rolled TLS in
> TlsUtil.brs cannot complete a handshake — see known_bugs.md #9)."

`known_bugs.md` was **never committed** — it does not exist in this repo or
in any commit on any branch. The reference is dangling.

## What is actually left to do

Four stubs are tagged `UNIMPLEMENTED` in the stashed `TlsUtil.brs`, plus one
that is not tagged:

1. **X25519 ECDHE** — scalar multiplication on Curve25519. The stub returns
   32 zero bytes (`TlsUtil.brs` around the `_x25519` helpers).
2. **The ECDHE shared secret** — uses zeros as a placeholder.
3. **RSA/ECDSA signature verification** over the transcript hash (RFC 8446
   §4.4.3).
4. **ASN.1 / X.509 parsing and chain validation** — the server certificate is
   never validated.
5. **GCM framing.** The `_aead_*` helpers call
   `cipher.Setup(encrypt, "aes-128-gcm", key, iv)` and then `cipher.Process(...)`
   with **no additional authenticated data and no tag**. TLS 1.3 requires the
   five-byte record header as AAD and a 16-byte tag appended to the ciphertext,
   so the AEAD is set up as if GCM were a bare counter-mode cipher.

### The cipher is *not* the blocker

An earlier note in this folder said the Roku "cannot speak TLS 1.3" because
`roEVPCipher` lacks AES-256-GCM and ChaCha20-Poly1305. **That is too strong
and has been corrected.** TLS 1.3 also defines `TLS_AES_128_GCM_SHA256`
(0x1301), which servers must support, and `roEVPCipher` has had
`aes-gcm-128` since **Roku OS 15.2**. The device here runs **15.3.4.2402**, so
AES-128-GCM *is* available.

The real blockers are the four stubs above: **key agreement**, **server
authentication** and **certificate handling**, plus GCM framing. That is a
substantial but not impossible piece of work — `ByteUtil.brs` already has
`ModExp` and RSA helpers to build on.

## Why it was parked

The user's summary was "lack of AES256 support", which is close but not exact
— see above. The practical reason it sat still is that the chat now works
over **plain Twitch IRC** (see [twitch-chat.md](twitch-chat.md)), which needs no
TLS at all, and the durable answer is to move the Twitch-side connection to
the companion backend rather than to make the Roku speak TLS 1.3 (see
[backend-chat-relay.md](backend-chat-relay.md)).

## If it is ever picked up

- Work on a branch. The parked code is on the `tls13-webclient` branch of the
  pre-merge clone `twitch-reloaded-roku` — check it out there and build on it.
- `WebSocket.brs` is the more valuable half of the stash: a clean RFC 6455
  client that works over `ws://` and could talk to any **plain** WebSocket
  endpoint. It is independent of TLS and could be adopted on its own. A
  salvaged copy of it already ships as `components/common/WebSocket.brs`.
- `TlsUtil.brs` in the stash replaces the vendored TLS 1.2 code in the working
  tree. Do not merge it without the stubs filled in — the working tree's
  version is TLS 1.2 and at least completes a handshake to a TLS 1.2 server.
