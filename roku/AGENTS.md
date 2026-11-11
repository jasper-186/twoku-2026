# AGENTS.md

Guidance for AI coding agents working on the Roku application.

This app lives at `roku/` in a monorepo that also contains the companion
Django service at `backend/`. The repo-root `AGENTS.md` covers the whole
product; this file covers the Roku half.

**Read `CLAUDE.md` first — it is the canonical reference.** It documents the project overview, build/deploy workflow, the SceneGraph architecture, the `Get*` Task-node contract, the shared helpers under `components/common/`, global and registry state, the companion backend, the BrightScript conventions used here, and a list of known gaps/hazards that are documented but *not* fixed.

Quick orientation:

- **Twoku** — an unofficial Twitch client for Roku, written in BrightScript on the SceneGraph framework.
- **No build system, no test framework, no linter.** The source tree *is* the deployable artifact. Verify changes by sideloading to a Roku in dev mode and walking the affected screen.
- **Entry point** — `source/main.brs` creates an `roSGScreen` and instantiates `MainScene`; everything else lives in `components/` as a `Foo.xml` (node + `<interface>` fields) / `Foo.brs` (behavior) pair.
- **Async work** — anything named `Get*` is a SceneGraph `Task` node: the caller sets input fields, sets `control = "RUN"`, and observes an output field. Tasks may only communicate through their interface fields.
- **Shared helpers are per-component, not global.** `components/common/*.brs` files must be `<script>`-included by each component that needs them.
- **Working branches** are dated `YYYY_MM_DD_<Topic>`; `main` is the trunk. Do not commit unless explicitly asked.

Before you sideload, compile-check the tree — the device reports compile
failures with no line number:

```bash
npx --yes -p brighterscript@latest bsc \
    --root-dir roku --create-package false --copy-to-staging false \
    --diagnostic-level error
```

When you touch code, read `CLAUDE.md` end to end first — the "Known gaps / hazards" section lists bugs that are *documented but deliberately unfixed*, so don't "fix" one silently as part of unrelated work.
