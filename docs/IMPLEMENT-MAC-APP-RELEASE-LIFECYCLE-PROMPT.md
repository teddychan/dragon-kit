# Implement the Dragon macOS app release lifecycle

Paste the block below into a fresh implementation session. The lifecycle spec, not prior chat
memory or historical release documents, is authoritative.

---

```text
Implement the accepted Dragon macOS app release lifecycle across the shared kit, release
workflow, apps, and marketing site.

Before editing:

1. Fetch each repository's origin/main. Do not trust stale local branches.
2. Read ~/git/dragon-kit/docs/MAC-APP-RELEASE-LIFECYCLE.md completely from the latest main.
3. Read each repository's CLAUDE.md/AGENTS.md and preserve unrelated or dirty work.
4. Inspect and report what conforms, what conflicts, the implementation order, and verification
   criteria. Then continue into implementation; do not stop after the plan.

Non-negotiable version and identity rules:

- Every public app, including Dragon Sample App, uses exactly vX.Y.Z.
- Do not add sample-v, mas-v, app-v, release-v, or any other public tag prefix.
- One repository owns at most one independently versioned public vX.Y.Z release series.
- Multiple distribution channels for one app consume the same exact tag; a Mac App Store build
  does not create a second tag family.
- DragonKit's repository keeps vX.Y.Z for the Swift package. Move Dragon Sample App's release
  ownership to a separate normal app repository; the in-tree app may remain the integration
  fixture. Historical sample-v tags and appcast entries are migration data only.
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

1. Add DragonKit build-channel presentation so About can render vX.Y.Z Debug (<build>) while
   CFBundleShortVersionString stays X.Y.Z.

2. Update clipmenu-2, ice-2, spectacle-2, yahoo-keykey-2, and Dragon Sample App:
   - stop writing (Debug) into CFBundleShortVersionString;
   - set Debug name, filename, executable, and .debug bundle identity;
   - disable production updating in Debug;
   - audit explicit UserDefaults suites, data paths, App Groups, iCloud, Keychain, helpers, XPC,
     Mach services, locks, sockets, notifications, updater, uninstall, and lifecycle scripts.

3. Add simultaneous-run verification proving Debug cannot modify, terminate, update, or
   uninstall the public app.

4. Implement the public tag gate before signing:
   - accept only ^v[0-9]+\.[0-9]+\.[0-9]+$;
   - verify tag equals the built numeric bundle version;
   - find the preceding exact public tag;
   - require current What's New content and meaningful or maintenance-only notes;
   - reject an explicit current-version argument;
   - make workflow_dispatch require an existing exact tag or run verification-only.

5. Treat Dragon Sample App as a normal app. Prepare separate app-owned release infrastructure
   using exact vX.Y.Z tags. Do not create another sample-v tag. Preserve existing installed users
   during appcast and artifact migration.

   Migrate channel-specific public tags such as mas-v as well: direct download, Homebrew, and
   Mac App Store workflows for the same app must consume the same exact vX.Y.Z release.

6. Keep marketing-site refresh asynchronous and non-blocking, filter drafts/prereleases, and
   migrate production Sparkle appcasts to app-owned repositories with old/new feed mirroring.

Use surgical changes and repository-native tests. Prepare codex/ branches and PR-ready commits,
but do not push, tag, publish, merge, or alter production infrastructure without explicit
authorization.
```
