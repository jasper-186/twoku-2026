# Known issues

Notes for defects that are fixed but **not yet verified on a device**, and for
open questions that need a particular account, device state or moment in time.

`CLAUDE.md` lists the defects themselves under "Known gaps / hazards". This
folder is the other half: **how to prove a fix actually works** when the defect
cannot be reproduced on demand.

## Conventions

- One file per topic, named after the area of the app rather than the bug.
- Every file starts with a **Status** block: what is deferred, when it was
  deferred, and the **trigger condition** — the observable state that has to
  happen before the verification can run.
- Verification steps are written to be executable cold. Assume the reader has
  not read the rest of this folder, has not seen the device, and does not
  remember the reasoning. Include the exact commands and the exact expected
  output — with the user's own details replaced by placeholders, and the
  concrete values kept in a `*.local.md` companion where a recipe needs them.
- Record **negative** findings too. A defect that turned out not to be a live
  bug is worth keeping so nobody spends time on it again.

### Anonymize the user, and keep every file self-contained

These files are published. Two rules follow from that:

- **Never write a real login, user id, display name, or followed channel into
  one.** Write `<login>`, `<your-user-id>`, `<client-id>`, and describe the
  *properties* the fixture needs instead — "an account whose display name
  differs from its login only in capitalisation" says everything the recipe
  needs, and identifies nobody.
- **No published file may refer to a `*.local.md` companion.** Those files are
  gitignored, so a reader who clones the repository will not have one and the
  reference would be dead. If you keep concrete values for your own runs, put
  them in a `*.local.md` file alongside, and let the published recipe stand on
  its own.

Remember that Twitch logins and user ids are public: `helix/users?login=`
resolves any of them, so a name in a public file is a name anyone can look up
— and a **third party's** name is worth avoiding entirely.

## Index

| Topic | Deferred | Status |
|---|---|---|
| [following-tab.md](following-tab.md) | 2026-10-28 | Two verification recipes deferred (D1, D2) plus one correction (D11). The test account is described by its properties, not by name. |
| [twitch-chat.md](twitch-chat.md) | 2026-10-29 | Chat was empty: five stacked faults. Fixed by moving to plain Twitch IRC — **needs a backend change** (documented as a diff) |
| [backend-chat-relay.md](backend-chat-relay.md) | 2026-10-29 | Future feature: move the Twitch-side connection to the backend so the Roku only ever needs plain HTTPS |
| [stashed-websocket-client.md](stashed-websocket-client.md) | 2026-10-29 | The parked TLS 1.3 / WebSocket rewrite — what it is, what is left, and how to recover it from the pre-merge clone. |

## Related

- Device setup, the console, and the commands used by these recipes are in the
  cheat sheet at the bottom of each file.
- The Roku debugging documentation is at <https://developer.roku.com/dev/docs/debugging>.
