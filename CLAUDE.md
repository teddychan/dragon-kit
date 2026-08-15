# DragonKit — working notes for Claude

DragonKit is a **published SwiftPM package**: the one place the shared parts of every Dragon
macOS app live. Five downstream apps depend on it, one repository each — `clipmenu-2`, `ice-2`,
`spectacle-2`, `yahoo-keykey-2` and `dragon-sample-app`. Four are ordinary app/menu-bar hosts;
`yahoo-keykey-2` is a system-managed Input Method Kit host. A change here ships to all of them.

There is no app inside this repository. Dragon Sample App lived here as `sample-app/` until
release ownership moved to `teddychan/dragon-sample-app`, because
[`docs/MAC-APP-RELEASE-LIFECYCLE.md`](docs/MAC-APP-RELEASE-LIFECYCLE.md) allows a repository only
one public `vX.Y.Z` series and this one's belongs to the package. Its wiring is still the
reference every app mirrors — read it there.

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
| `Tests/*/HostWiringTests.swift` | The host-app integration fixture: assembles the shared panes and configs from a plain, non-`@testable` import, in both link shapes. Replaced `sample-app/`'s build — see [Verify before claiming done](#verify-before-claiming-done). |
| `CONFORMANCE.md` + `Scripts/dragon-conformance.py` + `Scripts/test_conformance.py` | The rules apps are held to, their implementation, and the tests for that implementation. |
| `docs/CONFORMANCE-INCIDENTS.md` | Why each rule is shaped the way it is — the incident behind it. Non-normative. |
| `.github/workflows/conformance.yml` | Reusable workflow all five apps call from their own CI. |

`sample-app/` is **not tracked** — it is leftover build output (`.build/`, `Package.resolved`) from
when Dragon Sample App lived here, and `.gitignore` still names it. Nothing builds it and it is not
the in-tree app that [`docs/MAC-APP-RELEASE-LIFECYCLE.md`](docs/MAC-APP-RELEASE-LIFECYCLE.md)
prohibits. Ignore it; do not commit it, and do not mistake it for a reference — the reference app is
[dragon-sample-app](https://github.com/teddychan/dragon-sample-app).

### The KeyKey host and build boundary

Do not infer KeyKey's topology from the other four apps. In the current `yahoo-keykey-2`
repository there is no top-level `Package.swift` and no Xcode project. `tools/build-app.sh` is the
product-build entry point: it compiles KeyKey with direct `swiftc`, builds the pinned DragonKit
checkout under `vendor/dragon-kit` with SwiftPM, archives the kit's objects into static libraries,
links `DragonKit` and `DragonKitUpdates`, and copies `DragonKit_DragonKit.bundle` into the produced
IMK app. The two manifests under `Packages/` are test harnesses, not product-build entry points.

At runtime, macOS hosts the input-source menu and KeyKey supplies it from
`InputController.menu()`. KeyKey gets the applicable lifecycle items from `DragonAppMenu.items`,
then retargets them to `@objc` selectors on `InputController` because IMK dispatches top-level
selections back to the controller. Settings uses the shared DragonKit window and panes. Quit and
Uninstall are absent from the IMK menu; Uninstall is the last Settings pane. The implemented
uninstaller clears configured defaults/files, moves the running bundle to Trash, conditionally
clears its Homebrew receipt, and terminates — but has **no TIS deregistration hook**. Removing the
input source in System Settings and logging out when needed remain separate user steps; do not
document automatic TIS cleanup unless an implementation adds and verifies it.

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
General → (the app's own panes) → Permissions (when applicable) → Backup & Restore → What's New → Updates (when applicable) → About → Uninstall
```

That string is canon and **`CONFORMANCE.md` §R9 owns it** — quote it, don't paraphrase it. The two
`(when applicable)` markers are part of the canon, and §R5 owns both conditions: Permissions is
omitted for an app with the `no-permissions` trait (yahoo-keykey-2), Updates for an app without
`sparkle` (clipmenu-2's Mac App Store target, which can't ship Sparkle at all). Every other slot is
required, and the relative order never changes.

Changing any of this changes the UI of every Dragon app simultaneously, so it moves together
with `README.md`, `CONFORMANCE.md` and the tests — or not at all.

**The About pane's rows are canon too, and they are fixed slots.** `AboutContent` once took
free-form `links`/`credits` arrays; five apps used them to ship five visibly different panes, so
the arrays are gone. An app supplies URLs and proper nouns — the kit assembles every title, SF
Symbol, order and detail string:

```
header:  icon → name → v<ver> <channel>* (<count>) · <commit date> UTC → © <years> <holder>
links:   Website globe · Support on GitHub lifepreserver · Original project heart* · Open-source licenses doc.text
Credits: Created by · Based on* · Built with → DragonKit vX.Y.Z · License · attributions*
```

`*` optional slots — and there are only two left, both of them the *pair* an app either has or
doesn't. 4.0.0 closed the gaps *between* the slots after a screenshot comparison found the same
drift living there, and **it closed them in the signature rather than with a rule**: `licensesURL`
became required, and the upstream repository moved **inside** `OriginalWork` so the `Original
project` link and the `Based on` credit are one value that cannot half-ship. Prefer that move every
time — a required parameter or two fields folded into one type is caught by the app's own build,
where a rule is caught a day later in five CIs.

The one slot a signature *cannot* close is `copyright:`, because it is a plain `String`. That is
why it gets **CONFORMANCE §R14** instead. Before you touch §R14 or write anything nearby, read
[Incidents §R14](docs/CONFORMANCE-INCIDENTS.md#r14--the-about-copyright-is-kit-assembled-and-names-one-holder):
it records a legal justification that was written into the rule once, was wrong on the facts for
two of the five apps, and must not be reinstated. Short version — it is a rule about a presentation
slot, not about who holds a copyright; `LICENSE`, the licences page and `NSHumanReadableCopyright`
are all out of scope.

`<channel>` is `DragonBuildChannel` from the bundle — `Debug` for a local build, absent for a
release one, so a release renders exactly as it did before the key existed. It is the only
sanctioned way to show `Debug`; the word must never enter `CFBundleShortVersionString`. See
[`docs/MAC-APP-RELEASE-LIFECYCLE.md`](docs/MAC-APP-RELEASE-LIFECYCLE.md), which owns that rule.

Link detail text is *derived* from the URL, never typed beside it, and `websiteMatchesSupportRepo`
checks the Website row against the Support row's repo name (**CONFORMANCE §R15**).

**Attributions are `name → licence`** — `Sparkle → MIT`, `OpenCC → Apache-2.0`. Never a role
label: clipmenu-2 wrote `Sparkle → MIT` while the sample app wrote `Update framework → Sparkle
(MIT)` within a day of 3.0.0, in the one slot still app-supplied. The field names carry the rule,
which is why `Attribution(component:source:)` is deprecated in favour of `init(name:license:)`.
DragonKit itself is never an attribution — the kit writes its own `Built with` row.

`AboutCanonTests` pins all of it. Note what it *cannot* pin: the kit's tests assert what the kit
assembles, so they cannot see that two apps left an optional slot nil. **Five screenshots side by
side is what has found every round of About drift**, including 4.0.0's.

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

A broken checker is worse than no checker: it passes everything silently. Before writing or
relaxing a rule, read [`docs/CONFORMANCE-INCIDENTS.md`](docs/CONFORMANCE-INCIDENTS.md) — most of
the mistakes recorded there are mistakes about *rule design*, not about apps, and its closing
section collects them as a checklist. The two shortest ones: an unanchored version regex matches
whichever dependency appears first in the file, and anything a rule cannot read must be a
violation rather than a skip.

Rule numbers are not first-come. **Check open PRs for the next `R` number before claiming one** —
`gh pr list --state open` and grep the diffs for `## R`. Two branches will happily take the same
number, each `test_conformance.py` passes in isolation, and the collision only appears after the
second merge. Renumbering needs no kit tag: a rule number is documentation plus a violation label,
not public Swift API.

## Conventions

- Swift 6.1, macOS 26 platform floor. Strict concurrency: `@MainActor` on anything touching
  AppKit or SwiftUI.
- Tests use **swift-testing** (`import Testing`, `@Suite`, `@Test`) — not XCTest.
- **Comments explain why, and cite the incident.** This repo's doc comments are unusually
  explicit on purpose: nearly every non-obvious decision names the app and the bug that forced
  it. Match that. A new piece of canon with no stated rationale will drift back out.
- Conventional-commit subjects, with the PR number appended: `feat(updates): … (#26)`.

## Deliberate deferrals and migration debt — keep these scoped

These are intentional constraints or sequenced work. Don't quietly generalize one while fixing
something else; do flag a PR that contradicts the recorded decision or skips its migration plan.

- **Backup unification is approved migration debt.** Every app's target is DragonKit's
  `BackupSettingsPane` + `DragonBackup`. ClipMenu 2's `SyncBackupPane` and Ice 2's
  `IceBackupSettingsPane` remain temporarily while their data and workflows are mapped safely;
  keep the current conformance compatibility until both migrations land, then enforce the shared
  pane through the conformance triad. See [TechDebt.md](TechDebt.md).
- **Uninstall stays out of the menu** and in `UninstallSettingsPane`, last in the sidebar.
- **The reusable conformance workflow is pinned `@main` on purpose.** It reads the kit's default
  branch anyway, so a tag pin would freeze the interface while the rules moved.
- **The `exceptions` in CONFORMANCE §R11 are sanctioned**, each with a reason and an owner — and
  the registry is **what the apps declare**, never what prose here or in §R11 describes. An empty
  list means only that no divergence is sanctioned: it is not evidence the app was checked, or that
  it conforms. Say *not currently verified* when you have not run the checker against current
  source, and read the apps' config files when you need to know what is actually declared. Do not
  record a headcount here — a copy of the registry in prose is how §R11 acquired five phantom
  sanctions that sat live for months.
- **`Tests/*/HostWiringTests.swift` import the kit plainly, not `@testable`.** They stand in for a
  host app, and an app sees only the public surface — `@testable` would let a public-API break
  pass there while breaking five apps.

## Verify before claiming done

This is what CI runs, in this order:

```bash
swift test && python3 Scripts/test_conformance.py
```

`swift test` also carries the integration coverage `cd sample-app && swift build` used to provide.
`Tests/DragonKitTests/HostWiringTests.swift` assembles the Mac App Store shape — every shared pane
and config a sandboxed host wires, with `DragonKitUpdates` out of scope — and
`Tests/DragonKitUpdatesTests/HostWiringTests.swift` adds the Sparkle shape and the full canonical
sidebar. Between them they are the only place here that constructs a real `AboutSettingsPane`,
`BackupConfig` or `UninstallConfig`: every other suite uses a `FakePane`, so before they existed
the kit could add a non-defaulted parameter to any public initializer, go green, ship a tag, and
break five apps on bump.

`dragon-sample-app` cannot supply that signal from its own CI — it builds against the *published*
pin, so a break on a branch here stays invisible until this repo tags a release and the app bumps.
Cloning it into this workflow instead would be worse: an intentional breaking change would red-X
CI with no way to fix it in the same PR.

To check a real app against the spec, point the checker at its clone:

```bash
python3 Scripts/dragon-conformance.py --app ~/git/dragon-sample-app --kit .
```

That is a local convenience only. Each app's own CI runs the same checker through the reusable
workflow, which is where a violation actually blocks a PR.

## Git and releases

**PR-first, always.** Branch → `gh pr create` → `gh pr merge` → push the tag. Never push to
`main` directly, even for a release.

[`docs/MAC-APP-RELEASE-LIFECYCLE.md`](docs/MAC-APP-RELEASE-LIFECYCLE.md) is the canonical
lifecycle for every Dragon macOS app. Debug is a local build-and-test configuration, never a
tag, prerelease, appcast or public artifact. Only a public app tag enters the release gate; a
successful public release notifies the independently deployed marketing site without waiting
for it.

One public tag series lives in this repo:

- **`vX.Y.Z`** — the library, and nothing else. **Triggers a version-consistency check only —
  still no build and no release**; it is purely a version marker the five apps pin against.
  `kit-version-check.yml` asserts `DragonKitVersion.current` equals the tag, because every app's
  About reports that constant as "Built with · DragonKit vX.Y.Z" and nothing else can catch a
  missed bump. Shipping one isn't finished until the apps bump.

This repository builds and publishes no app. Dragon Sample App is a normal app, so it uses exact
`vX.Y.Z` tags too — and two release products cannot share one `vX.Y.Z` namespace, so it releases
from `teddychan/dragon-sample-app`, which owns its source, appcast, artifacts and Homebrew cask.
The `sample-v*` tags left here are historical migration data: they stay for provenance, and no new
one is ever created.

Never delete and re-push a release tag to retry — GitHub turns the published Release into a
draft whose asset 404s. Bump the plist version and push a fresh tag.
