# Implement the Dragon macOS app release lifecycle

This is a cross-repository coordination prompt for an authorized rollout. Use it only from a
workspace where DragonKit, every consuming app, shared automation, and the marketing site are
separate repository checkouts. It is not an app-scaffolding prompt and must never be used to add
an app or app-release infrastructure to the DragonKit repository.

Paste the block below into a fresh implementation session. The accepted lifecycle spec, not prior
chat memory or historical release documents, is authoritative.

> **Maintainers:** this prompt restates rules because it is pasted where this repository is absent.
> The duplication is derived, never authoritative.
>
> <!-- MIRRORS: MAC-APP-RELEASE-LIFECYCLE (repository boundary, tag namespace, Debug identity, tag gate) -->
>
> A change to any mirrored rule must update this file and
> [`ADOPT-DRAGONKIT-PROMPT.md`](ADOPT-DRAGONKIT-PROMPT.md) in the same PR.

---

```text
Implement the accepted Dragon macOS app release lifecycle across DragonKit, shared reusable
automation, each app's separate repository, and the marketing site.

Before editing:

1. Fetch each repository's origin/main. Do not trust stale local branches.
2. Read ~/git/dragon-kit/docs/MAC-APP-RELEASE-LIFECYCLE.md completely from the latest main.
3. Confirm each consuming app is checked out as its own repository. DragonKit must not contain an
   app directory, app build or packaging scripts, app release workflows, app signing/notarization
   configuration, downloadable app artifacts, or a production appcast.
4. Read each repository's CLAUDE.md/AGENTS.md and preserve unrelated or dirty work.
5. Inspect and report what conforms, what conflicts, the implementation order, and verification
   criteria. Then continue into implementation; do not stop after the plan.

Non-negotiable version and identity rules:

- Every public app, including Dragon Sample App, uses exactly vX.Y.Z.
- Do not add sample-v, mas-v, app-v, release-v, or any other public tag prefix.
- One repository owns at most one independently versioned public vX.Y.Z release series.
- Multiple distribution channels for one app consume the same exact tag; a Mac App Store build
  does not create a second tag family.
- DragonKit's repository keeps vX.Y.Z for the Swift package. It owns shared package code,
  contracts, conformance guidance, and reusable release conventions—not a consuming app or app
  release.
- Every consuming app, including Dragon Sample App, lives and releases from its own repository.
  Do not create, restore, copy, or maintain an app under DragonKit as `Example/`, `sample-app/`,
  an integration fixture, or any other path. Use DragonKit's test targets for kit integration
  coverage.
- Each app repository is the sole owner of its source, build and packaging scripts, workflows
  (including reusable-workflow callers), signing/notarization configuration, releases,
  downloadable artifacts, production appcast, app-side website/download notification
  integration, and app-specific operational configuration and state.
  Shared reusable automation may execute release steps, but it does not own an app release.
- Historical sample-v tags, releases, and appcast entries in DragonKit are migration data only.
  Do not add to them or recreate their infrastructure.
- Debug has no tag, GitHub Release, appcast, Homebrew release, or marketing-site event.
- Debug is never part of CFBundleShortVersionString. Keep the candidate numeric X.Y.Z and render
  the word Debug only from build-channel metadata and the Debug app's name.
- Release and Debug share one codebase but have runtime-independent bundles. Debug uses
  <release-bundle-id>.debug and must run simultaneously with the installed public release.

Implement in this order:

0. Correct the upstream instructions that currently recreate the old rule:
   - ~/.claude/CLAUDE.md
   - ~/.claude/skills/macos-debug-build/SKILL.md
   - ~/.claude/skills/dragon-mac-ops/SKILL.md

1. In DragonKit, add only shared build-channel presentation so About can render
   vX.Y.Z Debug (<build>) while CFBundleShortVersionString stays X.Y.Z. Do not add a host app or
   app-specific build/release infrastructure for this work.

2. In their separate repositories, update clipmenu-2, ice-2, spectacle-2, yahoo-keykey-2, and
   Dragon Sample App:
   - stop writing (Debug) into CFBundleShortVersionString;
   - set Debug name, filename, executable, and .debug bundle identity;
   - disable production updating in Debug;
   - audit explicit UserDefaults suites, data paths, App Groups, iCloud, Keychain, helpers, XPC,
     Mach services, locks, sockets, notifications, updater, uninstall, and lifecycle scripts.

3. In each app repository, add simultaneous-run verification proving Debug cannot modify,
   terminate, update, or uninstall the public app.

4. Implement each app's public tag gate in that app repository before signing. A caller may use
   shared reusable automation, but the app repository owns its workflow, configuration, and
   release result:
   - accept only ^v[0-9]+\.[0-9]+\.[0-9]+$;
   - verify tag equals the built numeric bundle version;
   - find the preceding exact public tag;
   - require current What's New content and meaningful or maintenance-only notes;
   - reject an explicit current-version argument;
   - make workflow_dispatch require an existing exact tag or run verification-only.

5. Treat Dragon Sample App as a normal app. In the separate dragon-sample-app repository, prepare
   app-owned release infrastructure using exact vX.Y.Z tags. Do not create or retain an in-tree
   DragonKit copy, and do not create another sample-v tag. Preserve existing installed users
   during appcast and artifact migration.

   Migrate channel-specific public tags such as mas-v as well: direct download, Homebrew, and
   Mac App Store workflows for the same app must consume the same exact vX.Y.Z release.

6. In the marketing-site repository, keep refresh asynchronous and non-blocking and filter
   drafts/prereleases. In each app repository, own the production Sparkle appcast and any
   website/download notification integration; use old/new feed mirroring only as a migration.

Use surgical changes and repository-native tests. Prepare codex/ branches and PR-ready commits,
but do not push, tag, publish, merge, or alter production infrastructure without explicit
authorization.
```
