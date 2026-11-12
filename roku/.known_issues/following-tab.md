# Following tab — deferred verification

## Status

- **Deferred:** 2026-10-28
- **State:** the fixes are committed; the *verification* could not be run
- **Trigger:** `helix/streams/followed?user_id=<your-user-id>` returns `data: []`
  — that is, nobody the test account follows is live. The account follows a
  handful of streamers; they go offline eventually, and that is the natural
  window. If the window is missed, see "Fallback" in Recipe B.

Two recipes are deferred (D1 and D2) and one earlier finding was corrected
(D11). Read the context section first — the *properties* the account needs
matter.

### What has since been confirmed on device

Checked on a Streaming Stick 4K (Roku OS 15.3.4.2402) with the app sideloaded
and a test account signed in:

| Finding | Status |
|---|---|
| The offline lookup resolves by **login** | The offline list populates and the console never prints `failed to get current user info`. The *display name vs login* distinction itself still needs a non-capitalisation display name to exercise. |
| The Offline Channels reveal is based on the **live follow count** | Not yet exercised — the account always had live follows. |
| `currentlyLiveStreamerIds` observer fires on refresh | **Not a defect.** The five minute timer fires and `onGetFollowedStreams` runs, so a freshly assigned assocarray does notify the observer. `alwaysNotify` is not needed. |
| Pagination cursor handling | **Not a live bug** — see the correction below. |
| Category names on the Following tiles | Populated (`Minecraft`, `CRACK`, `Just Chatting`, `League of Legends`, `Riot Games`) with the `game_name` taken straight from the streams response. |

The account's display name differs from its login only in capitalisation.
`helix/users?login=` is case-insensitive, so that pair resolves to the same
account either way — which is exactly why the original defect was invisible
here.

---

## Context

### Device

| | |
|---|---|
| Model | Streaming Stick 4K (3820R2) |
| OS | 15.3.4.2402 |
| Serial | your own device — see your local `.vscode/settings.json` |
| Address | **recheck**; DHCP may have moved it |
| Dev password | **HTTP Digest** auth — plain `-u` does not work |

### What the test account must look like

The recipes do not depend on one particular account. Any account with these
properties works, and the results are the same:

| Property | Why it is needed |
|---|---|
| The display name differs from the login **only in capitalisation** | Recipe A compares the two. The old code looked the user up by display name, and `helix/users?login=` is case-insensitive, so both lookups resolve to the *same* account. The defect is therefore invisible in the result — the only observable difference is the input, which is exactly what the diagnostic line prints. |
| At least one followed streamer | Recipe B's trigger is that none of them are live. |
| A followed streamer that is live now and goes offline later | That is the natural window for Recipe B. The **Fallback** in Recipe B forces the same state without waiting for it. |

Sign in through the device-code flow (`GetAuth` → `twoku-web.clstr.dev`). The
login is stored in the `dev` registry section and survives a reinstall.

### Repository state

The fixes are in the trunk. The **pre-fix build is not obtainable from this
repository**: `*.zip` is gitignored, and the history was squashed when the
Roku app and its backend were merged into one repository, so there is no
pre-fix commit to check out.

The A/B comparisons below are therefore done by **reintroducing the defect
with a local patch** — the same technique the Fallback in Recipe B uses. Each
recipe gives the patch, and every patch says **do not commit it**. Apply one,
build and sideload, observe, then revert it and build again.

---

## Recipe A — the offline lookup must use the login, not the display name

### The defect

`GetOfflineFollowedChannels` resolves the signed-in user with
`helix/users?login=<login>` to get the user id it needs for
`helix/channels/followed`. It was being handed **the display name** (the one
shown in the header) rather than the login.

### Why it cannot be reproduced with this account

`helix/users?login=` is **case-insensitive**. Verified against the live API:

```
login='<login>'            -> RESOLVED -> login='<login>' display_name='<display name>'
login='<display name>'     -> RESOLVED -> login='<login>' display_name='<display name>'
login='<LOGIN UPPERCASED>' -> RESOLVED -> login='<login>'
login='<a prefix of it>'   -> RESOLVED -> login='<other>'  <- a DIFFERENT real account
login='<login with space>' -> HTTP 400 Bad Request
```

The values above stand for any account whose display name differs from its
login only in capitalisation. The fourth row is the interesting one: a
*prefix* of the login resolves to a **different** account.

Because the display name differs from the login only in capitalisation, and
only capitalisation changes are permitted on such an account, the old code
looks up the right account by accident. The bug is invisible for this
account.

### What the fix does

`HomeScene` gained a `loggedInUserLogin` field alongside `loggedInUserName`:

- `MainScene.onUserLogin` sets `loggedInUserName` from `searchResults.display_name`
  (for the header) and `loggedInUserLogin` from `searchResults.login`
  (`components/MainScene.brs:301-302`).
- `HomeScene.onGetFollowedStreams` passes `m.top.loggedInUserLogin` to the
  offline task (`components/HomeScene.brs:326`).

That chain is verifiable by reading the source. To see it at runtime, add one
diagnostic line — **do not commit it**:

```brightscript
' in components/GetOfflineFollowedChannels.brs, immediately after the
' current_user lookup succeeds:
? "GetOfflineFollowedChannels > resolved user id " + current_user.id + " for login " + m.top.loggedInUserName
```

### Reintroducing the defect — do not commit this

Change the one line that hands the task the login, so it hands over the
display name instead:

```brightscript
' in components/HomeScene.brs, in onGetFollowedStreams:
'   current (fixed):   m.getOfflineFollowed.loggedInUserName = m.top.loggedInUserLogin
'   patched (defect): m.getOfflineFollowed.loggedInUserName = m.top.loggedInUserName
```

That is the whole defect: the task resolves the user with
`helix/users?login=`, and the display name is what it used to be given.

### Pass criteria

| Build | Expected console line |
|---|---|
| Patched (defect reintroduced) | `... for login <display name>` |
| Unpatched (current trunk) | `... for login <login>` |

Both resolve to the same user id, so the *result* is the same on this
account — the input is what differs, and the input is the defect.

### Why it is worth keeping the fix

The failure mode is worse than an empty list. A display name that happens to
be **another account's login** resolves to that other account — the fourth
row of the table above is a real, different Twitch account — so the old code
would have shown **someone else's followed channels** as your own. A display
name containing a space returns HTTP 400 and the lookup fails outright.

---

## Recipe B — the Offline Channels section must be reachable with no live follows

### The defect

The Following tab has a live grid (followed streamers who are live) and, below
it, an Offline Channels section. The Offline section is revealed when the last
row of the live grid is focused. The code that decided this compared the
focused row against a counter that could not express "there are no live
follows":

- When the followed-streams list is **invalid** (GetUser bailed out early),
  the counter was 0 and then decremented to **-1**, which no focused row can
  ever match.
- When the list is an **empty array** — the realistic "nobody I follow is
  live" case — the trailing-row append still ran and counted an **empty
  phantom row**, so the counter was **1**, never 0. The same wrong test in
  `onFollowingSelect` then *hid* the section again on the way back to the tab.

### The fix

`HomeScene.hasLiveFollows()` tests the number of live followed streamers
rather than the row count, and is used in `onFollowingSelect`,
`onGetFollowedStreams` and `onBrowseFollowing`
(`components/HomeScene.brs:385-390`).

**Note:** an earlier version of this fix tested `m.numRowsInFollowingList`
against 0, which could never be true — when the list is empty the trailing row
append still runs and counts an *empty* row, so the count was 1. The row count
cannot express "there are no live follows"; only the stream count can.

### Reintroducing the defect — do not commit this

Change the one line that answers "are there live follows?" so it answers
"are there rows?" instead:

```brightscript
' in components/HomeScene.brs, in hasLiveFollows():
'   current:  return m.top.followedStreams.count() > 0
'   patched:  return m.numRowsInFollowingList > 0
```

With no live follows, the trailing-row append still counts an empty phantom
row, so `m.numRowsInFollowingList` is **1** — the helper now reports live
follows that do not exist, and the Offline Channels section never appears.

This patch reproduces the realistic case (the followed-streams list comes back
as an empty array). It does **not** reproduce the other sub-case, where
`GetUser` bails out early and the list is `invalid` — both the current and the
patched helper answer "no live follows" there, so that path looks the same in
both builds.

### A/B

1. Apply the patch, build, sideload, and open the Following tab.
   **Expected:** the Offline Channels section never appears, however the
   cursor is moved.
2. Revert the patch, rebuild, sideload, and open the Following tab.
   **Expected:** the Offline Channels section appears straight away, with the
   "Offline Channels" label above it.

Watch the console for `GetOfflineFollowedChannels > getOfflineFollowedChannels
SearchResults > called` — the task must run either way; the difference is
whether its result is displayed.

### Fallback — if the natural window is missed

Force the zero-live case in either build by patching `GetUser` so the
followed-streams list comes back empty. **Do not commit this:**

```brightscript
' in components/GetUser.brs, immediately after result.followed_users.SortBy(...):
result.followed_users = []
```

Build, sideload, and run the same A/B. Both builds take the same patch, so the
only difference is the fix itself.

### Pass criteria

Defect reintroduced: section absent. Current trunk: section present and
populated.

---

## Correction — the pagination fix is not a live bug

The followed-list pagination was reported as an infinite loop. That was
overstated.

Helix **omits** the cursor on the last page — the response carries
`pagination: {}` rather than `pagination: {"cursor": ""}`. The original check
(`if pagination.cursor = invalid then exit while`) was therefore already
correct for the shape the API actually returns. Verified:

```
helix/streams/followed   -> data: [...], pagination: {}
helix/channels/followed  -> data: [...], pagination: {}
```

The committed change accepts an empty cursor as well, which is harmless
hardening for the other shape. **Do not spend time treating this as a live
defect.**

---

## Cheat sheet — driving the device from a shell

Set `ROKU_HOST` and `ROKU_PASS` to your device's address and dev password
first. The dev password is **HTTP Digest** auth — plain `-u` does not work
without `--digest`.

```bash
export ROKU_HOST=192.168.1.100
export ROKU_PASS='your-dev-password'
```

### Package and sideload

```bash
# Package the app (no top-level directory) - run from the roku/ directory
cd roku
./package.sh /tmp/opencode/twoku.zip

# Install - the dev web server uses HTTP DIGEST auth
curl --digest -u "$ROKU_PASS:$ROKU_PASS" \
     -F mysubmit=Install \
     -F archive=@/tmp/opencode/twoku.zip \
     "http://$ROKU_HOST/plugin_install"

# Confirm what is installed (port 8080 debug server)
printf 'plugins\n' | timeout 3 nc "$ROKU_HOST" 8080
```

### Launch and drive

```bash
# Launch the sideloaded app (ECP, port 8060 - not 80)
curl -d '' "http://$ROKU_HOST:8060/launch/dev"

# Remote keys via the debug server on 8080
printf 'd\n' | timeout 3 nc "$ROKU_HOST" 8080     # Down
printf 's\n' | timeout 3 nc "$ROKU_HOST" 8080     # Select / OK
printf 'k\n' | timeout 3 nc "$ROKU_HOST" 8080     # Back   (NOT 'b' - that is Rev)
printf 'h\n' | timeout 3 nc "$ROKU_HOST" 8080     # Home
printf 'press\n' | timeout 3 nc "$ROKU_HOST" 8080 # list every key
```

### Watch the console

Port 8085 carries the BrightScript console: `print`/`?` output, compile
warnings, and crash backtraces. **Attach before launching** or the startup
output is missed.

```bash
timeout 60 nc "$ROKU_HOST" 8085
```

Compile output looks like:

```
------ Compiling dev 'Twoku-2026' ------
BRIGHTSCRIPT: WARNING: unused variable 'scene' in function 'runuserinterface' in pkg:/source/main.brs(1)
...
Displayed 34 of 34 warnings
```

The reference build produced **34 warnings, 0 errors**. A new build must
produce **0 errors**; compare the warning list against the reference to spot
anything new.

### Useful debug-server commands (port 8080)

| Command | Purpose |
|---|---|
| `plugins` | list installed apps |
| `brightscript_warnings <n>` | raise the number of warnings shown |
| `chanperf [-r <seconds>]` | CPU and memory, repeated to 8085 |
| `sgnodes` | every SceneGraph node the running app created |
| `fps_display 1` | on-screen frame rate |
| `free` | device memory |
| `press` | simulate a remote keypress |

### ECP queries (port 8060)

`query/device-info` and `launch` work. `query/registry`, `query/chanperf`,
`query/sgnodes` and `exit-app` need ECP to be out of limited mode — set
**Settings → System → Advanced system settings → Control by mobile apps →
Enabled**.

`query/registry` still fails with "Device not keyed": the device reports
`Dev ID: <unkeyed>` (`showkey` on port 8080). **Do not run `genkey`** — the
registry is per developer id, and re-keying could orphan the stored login.

### Getting the account's follow state without the app

The app's own access token appears in the console log (`Found UserToken:`
followed by the token). With it:

```bash
# The client id comes from the app's own /apptoken call; the backend has
# the client secret. Use the same id the app uses.
curl -s -H "Client-ID: <client-id>" \
        -H "Authorization: Bearer <token>" \
        "https://api.twitch.tv/helix/streams/followed?user_id=<your-user-id>&first=100"
```

`data: []` is the trigger condition for Recipe B.
