# TLS 1.3 on Roku — what a hand-rolled stack would require

## Status

- **Not pursued.** The chat works over plain Twitch IRC, which needs no TLS at
  all, and the durable answer is to move the Twitch-side connection to the
  companion backend — see [backend-chat-relay.md](backend-chat-relay.md).
- **What this file is:** the analysis that decided the question, kept so the
  platform limits are not re-derived from scratch.

## Why the platform is the constraint

Roku exposes no native TLS socket. `roUrlTransfer` does TLS for HTTP only,
and `roStreamSocket` — the API a WebSocket client needs — has no TLS at all.
So a WebSocket to a `wss://` endpoint means writing TLS in BrightScript.

| Need | Roku offers |
|---|---|
| A TLS socket | None. `roStreamSocket` is plain TCP; `roUrlTransfer` is HTTP-only. |
| A symmetric cipher | `roEVPCipher` has AES-128/192/256 in CBC/CFB/ECB/OFB, and `aes-gcm-128` since **Roku OS 15.2**. |
| Key agreement | No X25519 and no ECDH of any kind. |
| Server authentication | No certificate chain validation, no signature verification over the transcript hash. |
| Randomness | `roDeviceInfo` provides a random seed, but there is no CSPRNG primitive. |

### The cipher is *not* the blocker

An earlier conclusion in this folder was that the Roku "cannot speak TLS 1.3"
because `roEVPCipher` lacks AES-256-GCM and ChaCha20-Poly1305. **That is too
strong.** TLS 1.3 also defines `TLS_AES_128_GCM_SHA256` (0x1301), which
servers must support, and `roEVPCipher` has had `aes-gcm-128` since **Roku OS
15.2**. A device on OS 15.2 or later has AES-128-GCM available.

What is genuinely missing is key agreement, server authentication and
certificate handling — plus GCM record framing.

## What a TLS 1.3 implementation would have to add

Five pieces, four of them explicitly stubbed in the abandoned attempt:

1. **X25519 ECDHE** — scalar multiplication on Curve25519. There is no
   Curve25519 arithmetic on the platform; `roEVPCipher` has no ECDH.
2. **The ECDHE shared secret** — derived from the above.
3. **Signature verification** over the transcript hash (RFC 8446 §4.4.3) —
   RSA/ECDSA against the server's certificate.
4. **ASN.1 / X.509 parsing and chain validation** — the server certificate
   would otherwise never be checked.
5. **GCM framing.** `roEVPCipher`'s GCM mode is set up as
   `cipher.Setup(encrypt, "aes-128-gcm", key, iv)` followed by
   `cipher.Process(...)` with **no additional authenticated data and no
   authentication tag**. TLS 1.3 requires the five-byte record header as AAD
   and a 16-byte tag appended to the ciphertext, so the AEAD has to be driven
   differently — the primitive alone is not enough.

Items 1-4 are the hard part: they are a cryptographic implementation, not a
protocol detail, and they would need to be correct to be safe.

## What *is* in this repository

`components/common/WebSocket.brs` is a working RFC 6455 WebSocket client over
**`ws://` only**. It is hand-rolled, so treat it as delicate code, but it is
self-contained and it is not the blocker for anything that speaks plain
WebSocket.

It cannot be extended to `wss://` without all five items above. The reason it
is `ws://`-only is exactly that `roStreamSocket` has no TLS and a hand-rolled
TLS stack could not complete a handshake against a real server.

## Why it was not pursued

Chat does not need TLS 1.3 on the device. Plain IRC over TCP 6667 is
unencrypted but works, and the durable design is to have the **backend** hold
the Twitch-side connection — it already speaks TLS 1.3 for free — and leave
the Roku doing plain HTTPS, which it already does well.
