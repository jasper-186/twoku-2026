# AGENTS.md

Guidance for AI coding agents working in this repository.

## Layout

| Path | What it is |
|---|---|
| `roku/` | The Roku application — BrightScript on SceneGraph. The deliverable. |
| `backend/` | The companion Django service. Holds the Twitch client secret. |
| `.github/workflows/` | CI. Builds the backend Docker image and the Roku package. |

**Read `roku/CLAUDE.md` before touching the Roku code — it is the canonical
reference.** It documents the scene graph layout, the `Get*` Task-node
contract, the shared helpers under `roku/components/common/`, global and
registry state, the backend contract, and a list of known gaps/hazards that are
documented but *not* fixed.

## Orientation

- **Twoku** — an unofficial Twitch client for Roku.
- **Two halves, one product.** The Roku app talks to the backend in
  `backend/` for OAuth, token refresh and playback-URL resolution. Everything
  else it fetches directly from Twitch. The endpoint contract is tabulated in
  the root `README.md`.
- **No build system, no test framework, no linter** on the Roku side. The
  source tree *is* the deployable artifact. Verify changes by sideloading to a
  Roku in dev mode and walking the affected screen.
- **Entry point** — `roku/source/main.brs` creates an `roSGScreen` and
  instantiates `MainScene`; everything else lives in `roku/components/` as a
  `Foo.xml` (node + `<interface>` fields) / `Foo.brs` (behavior) pair.
- **Async work** — anything named `Get*` is a SceneGraph `Task` node: the
  caller sets input fields, sets `control = "RUN"`, and observes an output
  field. Tasks may only communicate through their interface fields.
- **Shared helpers are per-component, not global.**
  `roku/components/common/*.brs` files must be `<script>`-included by each
  component that needs them.
- **The backend is a hard dependency** for anything but browsing: the app
  token, all playback URLs, login and token refresh all come from it. Its
  address comes from `BASE-URL` in the Roku app's `roku/env` file, which ships
  inside the package; the backend's own address comes from `DJANGO_BASE_URL`.
  The two must agree.
- **Working branches** are dated `YYYY_MM_DD_<Topic>`; `main` is the trunk.
  Do not commit unless explicitly asked.

## Before you sideload

Compile-check the Roku tree first — the device reports compile failures
without a line number:

```bash
npx --yes -p brighterscript@latest bsc \
    --root-dir roku --create-package false --copy-to-staging false \
    --diagnostic-level error
```

## When you touch code

Read `roku/CLAUDE.md` end to end first. Its "Known gaps / hazards" section
lists bugs that are *documented but deliberately unfixed*, so don't "fix" one
silently as part of unrelated work.

## Secrets

The repository is intended to be public. Credentials are not committed:
they are supplied as environment variables (backend) or GitHub Actions
secrets (CI). See the root `README.md` and `.github/workflows/` for how each
one is injected. If you find a credential committed in plaintext, do not
reproduce it — replace it with a variable and say so.

The same applies to personal data in the documentation. When you write a
known issue, anonymize the user: describe the test account by the
*properties* it must have rather than by its login, user id, display name or
followed channels. See [`roku/.known_issues/README.md`](roku/.known_issues/README.md).
