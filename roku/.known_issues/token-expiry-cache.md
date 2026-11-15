# Token expiry cache — deferred, and what the Global node will and will not do

## Status

- **Deferred:** 2026-11-14
- **State:** the optimisation was **written, shipped and rolled back**. The
  app is back on the last build that was verified working on device. The
  work is not lost — the design is below, and so is the reason it kept
  breaking.
- **Trigger:** every browse of the stream list spends **two round trips to
  `id.twitch.tv` before the Helix request goes out** — one to validate the
  user token and one to validate the app token. The list therefore appears
  two round trips late. This is visible in the console log as a
  `Validating token:` line every time the stream list is loaded.

The device the measurements below were taken on:

| | |
|---|---|
| Model | Streaming Stick 4K (3820R2) |
| OS | 16.0.4 |
| Address | **recheck**; DHCP may have moved it |
| Dev password | **HTTP Digest** auth — plain `-u` does not work |

---

## What the optimisation is

Twitch already says how long a token is good for. `GET
https://id.twitch.tv/oauth2/validate` answers with an `expires_in`, and
`POST /refresh` does too. So there is no need to ask "is this token still
good?" before every request — ask once, remember the answer, and only ask
again when the answer is about to expire.

Measured on device, from the validate responses in the console log:

| Token | `expires_in` | Where it comes from |
|---|---|---|
| app token | ~5,000,000 s (about two months) | `GET /apptoken`, fetched fresh at **every** app start by `GetToken` |
| user token | ~15,000 s (about four hours) | the device-code login, then `POST /refresh` |

The app token is the expensive one to keep checking: it is good for two
months and is refetched at every start, so validating it before every
browse is pure waste.

What the cache would save:

| | before | after |
|---|---|---|
| first browse of a session | 2 requests | 1 (the user token) |
| every later browse | 2 requests | 0 |
| first browse after a restart | 2 requests | 0 |
| browse latency | +2 round trips | +0 round trips |

The user token's expiry would live in the registry as
`LoggedInUserData.UserTokenExpiresAt`, next to the token itself, so it
survives a restart and the first browse of a session costs nothing either.

The app token's expiry does **not** need to persist — the app token is
refetched at every start, so its expiry is only useful within a session.

---

## Why it was rolled back

Three attempts were shipped. All three stopped the app with the same
error, on the same statement:

```
Member function not found in BrightScript Component or interface. (runtime error &hf4)
   at pkg:/components/common/TwitchAuth.brs(121)
```

and the app sat in the BrightScript debugger instead of running.

The three attempts differed only in **which method they used to create the
global field**:

| Attempt | Method used | Verdict |
|---|---|---|
| 1 | `m.global.hasField()` then `m.global.addField()` | `addField` does not exist on the Global node |
| 2 | `m.global.getField()` | did not get past the missing-field case either |
| 3 | `m.global.hasField()` then `m.global.addFields()` then `m.global.setField()` | never reached the device — rolled back before it was tested |

The mistake was the same each time: **a global field was written before it
existed**. `setField` on a field the node does not have stops the script.
Every attempt assumed that some method would create the field on the way.

### What the Global node actually supports

`m.global` is the **Global node** (`ifGlobal`), not an `roSGNode`. That
difference is the whole bug.

| Method | On the Global node? | Note |
|---|---|---|
| `hasField(name)` | **yes** | returns `false` for a field that is not there — confirmed on device: `? m.global.hasField("probeField")` answered `false` |
| `addFields({key: value})` | **yes** | the existing code already uses it (`m.global.addFields({userToken: userToken})`) |
| `getField(name)` | yes | the existing code reads `m.global.userToken` before `MainScene.init` has created it, and gets `invalid` without complaint |
| `setField(name, value)` | **yes** | the existing code already uses it (`m.global.setField("userToken", access_token)`) |
| `addField(name, type, notify)` | **NO** | this is an `roSGNode` method. Calling it on the Global node is what produced the error above. |

Two more rules came out of it:

- **`addFields` takes the field's type from the value.** A value of
  `invalid` has no type, so `addFields({someField: invalid})` **does not
  create the field**. It has to be added with a real value — a string, a
  boolean, a number.
- **A field must exist before `setField` is called on it.** The existing
  code gets away with it because `MainScene.init` creates `userToken` and
  `appBearerToken` first.

### The trap underneath it: the tasks start first

`MainScene.xml` has `HomeScene`, `CategoryScene` and the rest as
**children**, so their `init()` runs **before** `MainScene.init`. `HomeScene.init`
starts `GetStreams`, whose task calls `refreshToken()` — so the token code
runs before `MainScene.init` has created anything on the global node.

That is why "create the fields in `MainScene.init`" is not good enough: by
the time `MainScene.init` runs, a task may already have tried to write to
them. The fields have to be created **on demand**, at the point of use.

### What the working shape looks like

```brightscript
sub setUserTokenExpiresAt(value as String)
    if NOT m.global.hasField("userTokenExpiresAt")
        m.global.addFields({ "userTokenExpiresAt": value })
    end if
    m.global.setField("userTokenExpiresAt", value)
end sub
```

Every operation in that is one the existing code already proves works on
the Global node. The field names are spelled out rather than passed in,
because the associative array that `addFields` takes needs a literal key.

**This exact code has not been on a device.** Attempt 3 above was the
nearest to it and was rolled back before it was tested. It should be
treated as unproven until it has been through the recipe below.

---

## Two things to be careful about

**The value has to be a real one.** `addFields` takes the type from the
value, so an expiry cannot be added as `invalid`. Storing the expiry as a
**string** sidesteps the question entirely: a string is a string, and the
number it holds is read back with `Val()` when it is needed.

**A `setField` that is not there is fatal, but a `setField` on a field
that holds `invalid` is not necessarily.** Keep the fields holding real
values — `""` for "no expiry known", not `invalid`.

---

## Recipe: proving it works when it is picked up again

1. Write the cache. Start from the state this repository is in now:
   - `validateToken` returns the parsed response instead of `true`, so the
     caller can read `expires_in`.
   - The expiry is remembered in `m.global` (as a string) and, for the user
     token, in the registry as `LoggedInUserData.UserTokenExpiresAt`.
   - `refreshToken()` trusts the remembered expiry. `refreshToken(true)`
     does not — a caller that has just been given a **401** must not trust
     it, because the token could have been revoked while the expiry still
     said it was good.
   - The app token's expiry comes from the `/apptoken` response, so it is
     never validated at all.

2. Compile-check it. The compiler will not catch the field problem — it
   cannot check what a dynamic object supports — so this only rules out the
   ordinary mistakes:

   ```bash
   npx --yes -p brighterscript@latest bsc --root-dir roku \
       --create-package false --copy-to-staging false --diagnostic-level error
   ```

3. Sideload it, then **read the console log before touching the remote**.
   The failure mode is a debugger break, and the log says which statement
   broke:

   ```bash
   telnet <device-ip> 8085
   ```

   What a working build prints on the second and later browses:

   ```
   Refreshing user token...
   User token is still fresh, skipping refresh
   Refreshing app token...
   App token is still fresh, skipping refresh
   ```

   What a broken one prints:

   ```
   Member function not found in BrightScript Component or interface. (runtime error &hf4)
   ```

   If the app stops in the debugger, **press a key on the remote** to
   dismiss the prompt — the app does not carry on by itself.

4. Check that the requests actually went away. In the console log, count
   the `Validating token:` lines against the number of stream-list loads:

   ```
   grep -c "Validating token:"     # should not grow with the number of browses
   grep -c "Stream Quality Url"    # the number of stream-list loads
   ```

   Before the cache these two counts move together.

5. Regression. The browse list, the Following list, a live stream, a VOD
   and the chat all have to keep working, and a cold start with an expired
   token still has to refresh exactly once.

---

## Cheat sheet

| | |
|---|---|
| Console | `telnet <device-ip> 8085` — one connection at a time, and the password prompt does not always appear |
| Reading the log from a script | Connect, then read; the console replays its buffer on connect |
| The app | `dev` channel, id `dev`, `pkg: dev 0.9.0 <digest>` in the source digest line |
| Breaking in the debugger | The console prints the statement, the local variables and the backtrace — the **line number and the statement** are what matter |
| Testing a global-node method | At the debugger prompt: `? m.global.hasField("someField")` answers `true` or `false` |

The Roku debugging documentation is at
<https://developer.roku.com/dev/docs/debugging>.
