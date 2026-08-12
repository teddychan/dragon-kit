# DragonKit — working notes for Claude

DragonKit is a **published SwiftPM package**: the one place the shared parts of every Dragon
menu-bar app live. Five downstream apps depend on it, one repository each — `clipmenu-2`, `ice-2`,
`spectacle-2`, `yahoo-keykey-2` and `dragon-sample-app`. A change here ships to all of them.

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
| `.github/workflows/conformance.yml` | Reusable workflow all five apps call from their own CI. |

`Example/` is not tracked; it is leftover build output from an earlier sample-app layout. Ignore it.

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
header:  icon → name → v<ver> <channel>* (<count>) · <commit date> UTC → © <years> <holder>
links:   Website globe · Support on GitHub lifepreserver · Original project heart* · Open-source licenses doc.text
Credits: Created by · Based on* · Built with → DragonKit vX.Y.Z · License · attributions*
```

`*` optional slots — and there are only two left, both of them the *pair* an app either has or
doesn't. 4.0.0 closed the gaps *between* the slots, after a screenshot comparison found the same
drift living there: `licensesURL` is **required** (spectacle-2 and the sample app listed
`Sparkle → MIT` in Credits with no notices page), and the upstream repository lives **inside**
`OriginalWork`, so the `Original project` link and the `Based on` credit are one value that cannot
half-ship (clipmenu-2 and ice-2 both credited an upstream the pane never linked). The copyright
names **one holder — the app's own**; the dual-holder `© 2008–2014 Naotaka Morimoto · © 2026 Teddy
Chan` form is gone. It is a plain `String`, so the compiler can't close it — **CONFORMANCE §R14**
does.

That last one is **a rule about a presentation slot, not about who holds a copyright**, and the
distinction was learned the hard way: the first draft justified it by claiming a Dragon app
reimplements its upstream rather than reusing its source and so has no upstream copyright to
assert. True of yahoo-keykey-2, false of both apps it touched — ice-2 is a GPL-3.0 *fork* whose §4
requires the upstream notice to travel, and clipmenu-2's `LICENSE` names two holders. Don't
reinstate that reasoning, and don't let this rule near a legal notice: `LICENSE` and the licences
page are out of scope, and they are where the upstream holder is named — ice-2's `LICENSE` carries
Jordan Baird in the GPL's own notice template. Lineage inside the pane is `OriginalWork`'s job,
twice. `NSHumanReadableCopyright` is **not** where §4 is satisfied: it's an optional Apple key no
licence names, three apps shipped without it, and all five now set it to `© 2026 Teddy Chan` to
match About — ice-2 last, in 2.14.7. The kit neither reads nor requires it.

`<channel>` is `DragonBuildChannel` from the bundle — `Debug` for a local
build, absent for a release one, so a release renders exactly as it did before the key existed.
It is the only sanctioned way to show `Debug`: per
[`docs/MAC-APP-RELEASE-LIFECYCLE.md`](docs/MAC-APP-RELEASE-LIFECYCLE.md) the word must never enter
`CFBundleShortVersionString`, which stays the numeric candidate `X.Y.Z` that the release tag is
asserted against. Link detail text is *derived* from the URL, never typed beside it, and the
website must address the canonical `dragonapp.com/{app-name}-{major}` page — the same string as
the support row's repo, which is how `websiteMatchesSupportRepo` checks one against the other.
That property is only reachable from a constructed `AboutContent`, so only two apps asserted it;
**CONFORMANCE §R15** now reads both literals per app, and dragon-sample-app — which has no public
page — holds the one live §R11 exception.

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
