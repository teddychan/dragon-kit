# DragonKit — working notes for Claude

DragonKit is a **published SwiftPM package**: the one place the shared parts of every Dragon
menu-bar app live. Four downstream apps depend on it (`clipmenu-2`, `ice-2`, `spectacle-2`,
`yahoo-keykey-2`), plus the in-repo Dragon Sample App. A change here ships to all of them.

The prime directive, from [CONFORMANCE.md](CONFORMANCE.md):

> **An app supplies content and app-domain logic. It never re-implements what DragonKit owns.**

Your job in this repo is the other half of that bargain: keep what the kit owns worth
depending on, and keep it from breaking five apps at once.

## Layout

| Path | What it is |
|---|---|
| `Sources/DragonKit/` | The core library. **No external dependencies.** |
| `Sources/DragonKitUpdates/` | The only target that may touch Sparkle. |
| `Sources/DragonKit/Resources/*.lproj/DragonKit.strings` | Kit-owned strings, 7 languages. |
| `Tests/DragonKitTests/` | swift-testing suites for the core library. |
| `Tests/DragonKitUpdatesTests/` | swift-testing suites for the Sparkle-backed target. Separate on purpose: keeping Sparkle out of the core test target is what keeps the two-product split honest. |
| `CONFORMANCE.md` + `Scripts/dragon-conformance.py` + `Scripts/test_conformance.py` | The rules apps are held to, their implementation, and the tests for that implementation. |
| `.github/workflows/conformance.yml` | Reusable workflow the four apps call from their own CI. |
| `sample-app/` | Dragon Sample App — a real, releasable reference app that wires up every module. |
| `docs/dragon-sample-app/appcast.xml` | Self-hosted Sparkle appcast (written by release CI — don't hand-edit). |

`Example/` is not tracked; it is leftover build output from before the sample app moved to
`sample-app/`. Ignore it.

## Non-negotiables

**The two-product split is load-bearing.** `DragonKit` links no external dependency;
`DragonKitUpdates` adds Sparkle. Mac App Store builds (clipmenu-2) link the core only, because
Sparkle is forbidden in a sandboxed build. Never `import Sparkle`, reference `SPUUpdater` /
`SPUStandardUpdaterController`, or add a package dependency outside `Sources/DragonKitUpdates/`.

**Public API is a contract with five apps.** Removing or renaming a `public` symbol, changing a
signature, adding a non-defaulted parameter to a public initializer, or adding a protocol
requirement without a default is a breaking change — it needs a major `vX.0.0` tag and every app
has to be bumped by hand. Prefer additive change with defaults.

**User-visible text goes through `L(_:)`,** and a new key goes into **all seven** `.lproj`
files (`en, es, fr, ja, ko, zh-Hans, zh-Hant`) — `LocalizationTests.allLanguagesDefineTheSameKeys()`
fails the build otherwise. `L()` resolves the module bundle first, so an app cannot override or
patch a kit string; getting app-specific copy for one means exposing it as config, the way
`UninstallConfig` does for the uninstall checklist.

**The menu and the pane order are canon, not preferences.** `DragonAppMenu` owns the dropdown's
order, titles, casing, ellipses and SF Symbols. Uninstall is deliberately absent from it and
there is no flag to put it back. The settings sidebar order is:

```
General → (the app's own panes) → Permissions → Backup & Restore → What's New → Updates → About → Uninstall
```

Changing any of this changes the UI of every Dragon app simultaneously, so it moves together
with `README.md`, `CONFORMANCE.md` and the tests — or not at all.

**The About pane's rows are canon too, and they are fixed slots.** `AboutContent` once took
free-form `links`/`credits` arrays; five apps used them to ship five visibly different panes, so
the arrays are gone. An app supplies URLs and proper nouns — the kit assembles every title, SF
Symbol, order and detail string:

```
header:  icon → name → v<ver> (<count>) · <commit date> UTC → © …
links:   Website globe · Support on GitHub lifepreserver · Original project heart* · Open-source licenses doc.text*
Credits: Created by · Based on* · Built with → DragonKit vX.Y.Z · License · attributions*
```

`*` optional slots. Link detail text is *derived* from the URL, never typed beside it, and the
website must address the canonical `dragonapp.com/{app-name}-{major}` page — the same string as
the support row's repo, which is how `websiteMatchesSupportRepo` checks one against the other.

**Attributions are `name → licence`** — `Sparkle → MIT`, `OpenCC → Apache-2.0`. Never a role
label: clipmenu-2 wrote `Sparkle → MIT` while the sample app wrote `Update framework → Sparkle
(MIT)` within a day of 3.0.0, in the one slot still app-supplied. The field names carry the rule,
which is why `Attribution(component:source:)` is deprecated in favour of `init(name:license:)`.

`AboutCanonTests` pins all of it.

**Never hardcode a version, and always show it with a `v`.** The app's version is read from
`Info.plist` (`CFBundleShortVersionString`); `DragonAbout.versionString()` is the shared helper.
Every version that reaches the UI goes through `DragonVersion.display(_:)`, which is why
`WhatsNewContent.version` is *not* public — only the normalized `displayVersion` is, so no
un-prefixed version string is reachable from outside the module.

`DragonKitVersion.current` is the one sanctioned hardcoded version: a SwiftPM library has no
`Info.plist` and SwiftPM injects no package version, so the constant is hand-bumped with the tag
and `kit-version-check.yml` fails the tag when the two disagree.

## Conformance rules move as a triad

`CONFORMANCE.md` (the rule), `Scripts/dragon-conformance.py` (the enforcement) and
`Scripts/test_conformance.py` (the test for the enforcement) change **together**. A rule that is
only written down is exactly the failure this spec exists to prevent — documentation did not
stop any of the drift that motivated it, and the design spec even mandated one of the drifted
items.

A broken checker is worse than no checker: it passes everything silently. Two specific traps
recorded in the spec — an unanchored version regex matches whichever dependency appears first
in the file (it matched Sparkle's version in ice-2's `.pbxproj`), and deleting
`.dragon-conformance.json` must itself be a violation.

## Conventions

- Swift 6.1, macOS 26 platform floor. Strict concurrency: `@MainActor` on anything touching
  AppKit or SwiftUI.
- Tests use **swift-testing** (`import Testing`, `@Suite`, `@Test`) — not XCTest.
- **Comments explain why, and cite the incident.** This repo's doc comments are unusually
  explicit on purpose: nearly every non-obvious decision names the app and the bug that forced
  it. Match that. A new piece of canon with no stated rationale will drift back out.
- Conventional-commit subjects, with the PR number appended: `feat(updates): … (#26)`.

## Deliberate deferrals — leave these alone

These look like gaps and are not. Don't "fix" them; do flag a PR that quietly undoes one.

- **Folder-based versioned backup stays app-side.** `DragonBackup` snapshots a UserDefaults
  suite only. Generalizing the folder shape waits until a second app needs it.
- **Uninstall stays out of the menu** and in `UninstallSettingsPane`, last in the sidebar.
- **The reusable conformance workflow is pinned `@main` on purpose.** It reads the kit's default
  branch anyway, so a tag pin would freeze the interface while the rules moved.
- **The `exceptions` in CONFORMANCE §R11 are sanctioned**, each with a reason and an owner.
- `sample-app/Info.plist` carries `CFBundleVersion = 1` as an inert placeholder; every build
  stamps `git rev-list --count HEAD` over it.

## Verify before claiming done

This is what CI runs, in this order:

```bash
swift test && (cd sample-app && swift build) && python3 Scripts/test_conformance.py && python3 Scripts/dragon-conformance.py --app sample-app --kit .
```

The sample app is the reference every other app mirrors, so it must pass its own spec. Two
packaging bugs only ever appear in the CI-packaged `.app`, never under `sample-app/scripts/run.sh` —
if you touch `sample-app/Package.swift`, preserve both:

1. the `@loader_path/../Frameworks` rpath in `linkerSettings`, or dyld can't find the bundled
   `Sparkle.framework` and the app crashes on launch;
2. the `AppResources` bundle shim, because SwiftPM's synthesized `Bundle.module` looks in the
   `.app` root rather than `Contents/Resources` where CI puts the resource bundle.

## Git and releases

**PR-first, always.** Branch → `gh pr create` → `gh pr merge` → push the tag. Never push to
`main` directly, even for a release.

Two independent tag series live in this repo:

- **`vX.Y.Z`** — the library. **Triggers a version-consistency check only — still no build and no
  release**; it is purely a version marker the four apps pin against. `kit-version-check.yml`
  asserts `DragonKitVersion.current` equals the tag, because every app's About reports that
  constant as "Built with · DragonKit vX.Y.Z" and nothing else can catch a missed bump. Shipping
  one isn't finished until the apps bump.
- **`sample-vX.Y.Z`** — the Dragon Sample App. Triggers `sample-app-release.yml`, which builds,
  signs, notarizes, self-hosts the appcast and bumps the Homebrew cask. Its GitHub Release is
  demoted to pre-release so the kit's own tags keep the "Latest" badge.

`git describe --tags` is unreliable here: both series can land on the same commit (`v2.0.0` and
`sample-v1.2.0` are both `808d5a7`) and `describe` reports the sample tag. Use
`git tag --points-at HEAD` instead.

Never delete and re-push a release tag to retry — GitHub turns the published Release into a
draft whose asset 404s. Bump the plist version and push a fresh tag.
