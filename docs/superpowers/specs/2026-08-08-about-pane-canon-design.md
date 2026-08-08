# About pane canon — design

**Date:** 2026-08-08
**Status:** approved, pending implementation plan
**Ships as:** DragonKit `v3.0.0` (breaking)

## Problem

Five apps depend on DragonKit and every one of them renders a different About pane. Side-by-side
screenshots of Ice 2, ClipMenu 2, Yahoo! KeyKey 2 and Spectacle 2 disagree on row titles, SF
Symbols, row counts, copyright format, link destinations, and whether a version carries a `v`.

The cause is structural, not sloppiness. `AboutContent` accepts:

```swift
public let links: [AboutLink]                        // app picks title, symbol, detail, url
public let credits: [(label: String, value: String)] // app picks every label
```

DragonKit owns the *frame* — three sections, header typography, `DragonAbout.versionString()` —
and nothing inside it. Each app then hand-writes its own `AboutConfig.swift`. Five hand-written
files with no shared schema produce five different panes, exactly as observed.

> **An app supplies content and app-domain logic. It never re-implements what DragonKit owns.**

The About pane's *shape* is something the kit owns and never enforced.

## Evidence — the measured drift

### About pane

| | Ice 2 | ClipMenu 2 | KeyKey 2 | Spectacle 2 | Sample |
|---|---|---|---|---|---|
| Version source | `DragonAbout` | `DragonAbout` | `DragonAbout` + `" Debug"` | own hand-rolled¹ | `DragonAbout` |
| Copyright | `Copyright © 2025 …` | `© 2008–2014 …` | **not a copyright** — `倉頡／簡易 輸入法` | `© 2026 …` | `© 2026 …` |
| Link 2 title | Support on GitHub | Support on GitHub | Report an issue on GitHub | Source | Source |
| Link 2 symbol | `lifepreserver` | `lifepreserver` | `ladybug` | `chevron.left.…` | `chevron.left.…` |
| Link 2 URL | `/issues` | `/issues` | `/issues` | repo root | repo root |
| Website detail | `dragonapp.com/ice-2` ✅ | `dragonapp.com/clipmenu` — stub² | `www.dragonapp.com/keykey` — stub² | **`dragonapp.com`** — hub² | `dragonapp.com` |
| Link 3 | — | — | Homage · `heart` | Original · `eyeglasses` | — |
| Credit rows | 3 | 3 | 4 | 3 | 2 |
| "License" row | ✅ | ✅ | **missing** | ✅ | ✅ |
| "Built with" | missing | missing | missing | ✅ | ✅ |
| Acknowledgements | ✅ | — | — | — | — |
| Localization | **raw English**, no `L()` | `L("Website")` | `L("keykey.about.*")` | `L("app.about.*")` | `L("app.about.*")` |

¹ Local spectacle-2 checkout is v2.3.0 and hand-rolls `"\(short) (\(build))"`; the shipped 2.4.1
screenshot shows the kit format, so this one may already be fixed upstream.

² Every app has a canonical page on the site — `/ice-2/`, `/clipmenu-2/`, `/yahoo-keykey-2/`,
`/spectacle-2/`. `/clipmenu/` and `/keykey/` are `<meta refresh>` stubs whose `<link rel=canonical>`
points at the `-2` forms. So ClipMenu and KeyKey link redirect stubs and Spectacle links the bare
hub, all while a correct page exists for each.

KeyKey additionally renders **"Homage to the original" twice** — once as a link, once as a credit.

### Version display

| Surface | Source | Shows | `v`? |
|---|---|---|---|
| About header | `DragonAbout.versionString()` | `v2.13.0 (1350) · …` | ✅ kit-owned |
| **What's New header** | app-supplied raw string | varies | ❌ **3 of 5** |
| Updates "up to date" alert | `"v\(short) is currently…"` | `v2.13.0` | ✅ but hand-built and un-localized |
| Backup payload `appVersion` | written to the backup file | not displayed | n/a — data, not UI |

`WhatsNewPane.swift:19` renders `content.version` verbatim:

| App | Passes | Renders |
|---|---|---|
| Ice 2 | `Constants.versionString` → raw plist | `2.13.0` ❌ |
| ClipMenu 2 | `"v\(AppInfo.version)"` | `v2.19.1` ✅ |
| Spectacle 2 | raw `CFBundleShortVersionString` | `2.4.1` ❌ |
| KeyKey 2 | **hardcoded `"2.10.0"`** | `2.10.0` ❌ |
| Sample app | **hardcoded `"v1.3.1"`** | `v1.3.1` ✅ |

KeyKey and the sample app hardcode the version, breaking the repo's own non-negotiable *"Never
hardcode a version"*. KeyKey's About reads `v2.10.0` from the bundle while its What's New says
`2.10.0` from a literal — they diverge the day KeyKey ships 2.11.0.

### Build timestamp semantics

`DragonAbout` derives the timestamp in `v2.4.1 (756) · 2026-Aug-07 16:54:20 UTC` from the
**executable's modification date** — when CI linked and signed the binary. It is neither the
commit date nor the tag/release date. Meanwhile `CFBundleVersion` is `git rev-list --count HEAD`.
The two halves of that line therefore describe different things and can disagree: rebuild the
same commit tomorrow and the count holds while the date moves.

### Localization

A sweep of both targets for user-visible string literals outside `L()` returns exactly three
lines, all in `Sources/DragonKitUpdates/Updates.swift`:

```swift
alert.messageText     = "\(appName) is up to date"
alert.informativeText = "v\(short) is currently the newest version available."
alert.addButton(withTitle: "OK")
```

Everything else in the kit already routes through `L()`.

## Design

### Principle

The kit owns every label, symbol, order and format. The app supplies only URLs and proper nouns.
Anything an app can type, an app will eventually type differently — so the drift-prone values are
either fixed slots or *derived*, never free-form.

### The canonical pane

```
┌─────────────────────────────────────────────────┐
│                 [ icon 128×128 ]                │
│                    App Name                     │  .largeTitle semibold
│      v2.4.1 (756) · 2026-Aug-07 16:54:20 UTC    │  .callout  secondary
│               © 2026 Teddy Chan                 │  .caption  secondary
├─────────────────────────────────────────────────┤
│  🌐  Website .......... dragonapp.com/yahoo-keykey-2│  globe
│  🛟  Support on GitHub .... teddychan/yahoo-keykey-2│  lifepreserver
│  ❤️  Original project ..... ninjapanda/YahooKeyKey│  heart        (optional)
│  📄  Open-source licenses .. dragonapp.com/…/licenses│ doc.text  (optional)
├─ Credits ───────────────────────────────────────┤
│  Created by ..................... Teddy Chan    │
│  Based on ....................... Yahoo! KeyKey by ninjapanda · zonble │  (optional)
│  Built with ..................... DragonKit v3.0.0│  kit-supplied, always
│  License ........................ MIT           │
│  Language model ................. openvanilla/McBopomofo │ ┐ attributions,
│  Cangjie table .................. ibus-table-chinese     │ │ 0..n,
│  Han conversion ................. OpenCC (Apache-2.0)    │ ┘ always last
└─────────────────────────────────────────────────┘
```

Section 3 gains a visible `Credits` header (`DragonSection` already supports one). Sections 1 and
2 stay unheadered.

The two licence-shaped rows are deliberately different things and must not be merged: **License**
(Credits) is the app's own licence, `MIT` or `GPL-3.0`; **Open-source licenses** (Links) is the
website page carrying third-party notices for bundled dependencies.

### API

`links: [AboutLink]` and `credits: [(String, String)]` are **deleted**. `AboutLink` is deleted.

```swift
public struct AboutContent {
    // Header
    let appName: String
    let versionString: String        // DragonAbout.versionString() — no other source
    let copyright: String            // DragonAbout.copyright(…) — no other source
    let appIcon: NSImage?

    // Links — fixed slots
    let websiteURL: URL              // required, canonical dragonapp.com/<repo> page
    let supportURL: URL              // required, GitHub issues
    let originalProjectURL: URL?     // optional
    let licensesURL: URL?            // optional, third-party licence page on the website

    // Credits — fixed slots
    let createdBy: String            // default "Teddy Chan"
    let originalWork: (name: String, author: String)?   // → "Spectacle by Eric Czarny"
    let license: String              // "MIT", "GPL-3.0"
    // "Built with · DragonKit vX.Y.Z" is emitted by the kit. No field, no way to omit it.

    // Credits — third-party attributions, rendered last, in order
    let attributions: [Attribution]  // default []
}

public struct Attribution { let component: String; let source: String }
```

There is no way to add a row, retitle one, choose an icon, or reorder. Those become compile
errors instead of screenshots.

**`Based on` carries no `%@` interpolation.** An `Original %@` label would render differently per
app, which is drift by definition. The label is fixed; the app supplies the value, and even the
"by" is kit-formatted from `(name, author)`.

### Derived values, not typed ones

Three drift sources close by derivation:

1. **Link detail text is computed from the URL.** `https://www.dragonapp.com/keykey` →
   `dragonapp.com/keykey` (strip scheme, `www.`, trailing slash); a `github.com` URL → `owner/repo`.
   KeyKey's stray `www.` and Spectacle's hub-instead-of-app-page become unrepresentable.
2. **Copyright is assembled by the kit.**
   `DragonAbout.copyright(original: ("2008–2014", "Naotaka Morimoto"), years: "2026", holder: "Teddy Chan")`
   → `© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan`. Kills Ice's `Copyright ©` prefix.
3. **Version has one source** — `DragonAbout.versionString()`.
4. **The website is the canonical app page**, whose path is the GitHub repo name:
   `https://www.dragonapp.com/<repo>/`. The site's canonical URLs are all repo-named — `/clipmenu/`
   and `/keykey/` are `<meta refresh>` stubs pointing at `/clipmenu-2/` and `/yahoo-keykey-2/` —
   yet ClipMenu and KeyKey both link the stub and Spectacle links the bare hub. Because the
   Support row already yields `owner/repo`, the two rows are checkable against each other: the
   website path must equal the support repo. Three of five apps are wrong today and the rule
   catches all three.

   Sanctioned exception: the Dragon Sample App has no marketing page and points at the hub. It is
   the kit's reference app, not a product with its own page. Recorded like the other
   CONFORMANCE §R11 exceptions, with a reason and an owner.

### `Built with · DragonKit vX.Y.Z`

The kit emits label and whole value, so the row can never misreport which kit a binary compiled
against.

```swift
/// DragonKit's own version, shown in every app's About → Built with row.
/// Sanctioned exception to "never hardcode a version": a SwiftPM library has no
/// Info.plist to read, and SwiftPM injects no package version at compile time.
/// Bumped with the `vX.Y.Z` tag; the tag-push workflow fails if the two disagree.
public enum DragonKitVersion { public static let current = "3.0.0" }
```

The constant is only as honest as its guard, so the guard ships with it:

- **Tag-push check** — a verify-only workflow on `v*` that fails when `DragonKitVersion.current`
  ≠ the tag. This changes a documented fact: CLAUDE.md currently states `vX.Y.Z` triggers no CI.
  That line moves in the same PR, reworded to *"triggers a version-consistency check only; still
  no release."*
- **Unit test** that the constant is well-formed semver.

Accepted limitation: an app pinned to a branch or loose commit rather than a tag reports the last
tagged version. All four apps pin exact tags; commit-hash plumbing is not worth building for a
case that does not occur.

### The `v` prefix rule

```swift
public enum DragonVersion {
    /// Every version rendered in UI goes through here. Idempotent — strips any
    /// existing v/V and surrounding whitespace, then prepends exactly one "v".
    public static func display(_ raw: String) -> String   // "2.4.1" → "v2.4.1"
}
```

A normalizer alone is a convention someone forgets, so the guarantee is structural:
**`WhatsNewContent.version` stops being public.** Only `displayVersion` is exposed and it is
always normalized, so no un-prefixed version string is reachable from outside the module and a
future pane physically cannot render one.

`WhatsNewContent.version` also defaults to the bundle's `CFBundleShortVersionString`, so KeyKey
and the sample app stop hardcoding — they delete the argument.

Routed through the normalizer: About header, Built with, What's New header, Updates alert.

Backup's `appVersion` is deliberately **excluded** — it is written into the backup payload as
data, never displayed, and a `v` there would corrupt a stored value.

### Localization

Two new keys plus the existing `DragonKit.ok` fix the three raw strings:

```
"DragonKit.updates.upToDate.title"   = "%@ is up to date";
"DragonKit.updates.upToDate.message" = "%@ is currently the newest version available.";
```

New About keys, all seven `.lproj`:

```
"DragonKit.about.website"   = "Website";
"DragonKit.about.support"   = "Support on GitHub";
"DragonKit.about.original"  = "Original project";
"DragonKit.about.credits"   = "Credits";
"DragonKit.about.createdBy" = "Created by";
"DragonKit.about.basedOn"   = "Based on";
"DragonKit.about.builtWith" = "Built with";
"DragonKit.about.license"   = "License";
"DragonKit.about.licenses"  = "Open-source licenses";
```

`DragonKit.acknowledgements` is retired along with the bundled-document slot; `licensesURL`
replaces it as a plain link to a website page.

### Third-party licences move to the website

Ice bundles six MIT libraries — AXSwift, CompactSlider, Ifrit, LaunchAtLogin, Semaphore, Sparkle —
whose full licence text ships today as `Ice/Resources/Acknowledgements.rtf`/`.pdf`, reachable from
an in-app Acknowledgements button. KeyKey has comparable exposure via OpenCC (Apache-2.0).

The bundled document is removed. Each app that ships third-party code gets a licences page on
www.dragonapp.com — `dragonapp.com/<repo>/licenses` — carrying the verbatim notices, linked from
the About pane's `licensesURL` slot. The Credits section additionally names the libraries as
`attributions` rows, which are a summary and not a substitute for the notice text.

**Stated risk, owner-accepted.** MIT requires the copyright and permission notices be *included in
all copies or substantial portions of the Software*; a website is a weaker reading of that than a
file inside the bundle. This was raised and the owner chose the website. Recorded here so the
trade-off is not rediscovered as an accident.

Work this creates in the `www.dragonapp.com` repo (separate PRs, outside the kit release): a
licences page per app, plus `sitemap.xml` / `robots.txt` updates and an SEO pass per the site's
own rules.

### Commit datetime, not build time

Runtime has no git, so the build records it where it already records the build number:

```bash
BUILD="$(git rev-list --count HEAD)"          # existing
COMMIT_DATE="$(git log -1 --format=%cI)"      # new — 2026-08-07T16:54:20+08:00
"$PB" -c "Set :DragonCommitDate $COMMIT_DATE" "$APP/Contents/Info.plist"
```

`DragonAbout.versionString()` reads `DragonCommitDate` instead of stat-ing the executable, and
formats it UTC as before. Both halves of the line then describe the same commit:

```
v2.4.1 (756) · 2026-Aug-07 16:54:20 UTC
       └─ commit count ─┘  └─ that commit's date ─┘
```

Decisions:

- **Committer date (`%cI`), not author date** — it matches what `git log` shows and what sits on
  the branch; author date survives rebases and would point at the wrong moment.
- **Missing key omits the date entirely** — `v2.4.1 (756)` and nothing more. No silent fallback
  to executable mtime; a timestamp that quietly means something different in some builds is the
  drift being removed. `run.sh` stamps it too, so this only affects hand-assembled bundles.

## Testing

Row assembly is pure data — `AboutContent` computes the finished row lists and `AboutPane` only
renders them — so the canon is assertable without standing up SwiftUI.

| Test | Asserts |
|---|---|
| `linkRowsAreCanonical` | exact `[(title, systemImage)]`: Website/`globe`, Support/`lifepreserver`, Original/`heart`, Licenses/`doc.text` |
| `optionalLinkSlotsCollapseInOrder` | omitting `originalProjectURL` and/or `licensesURL` leaves the remaining rows in canonical order, never reordered |
| `creditRowsAreCanonical` | exact label order: Created by → Based on → Built with → License → attributions |
| `builtWithDragonKitAlwaysPresent` | kit row cannot be omitted or moved |
| `builtWithReportsKitVersion` | exactly `DragonKit v` + `DragonKitVersion.current` |
| `linkDetailDerivedFromURL` | `www.` stripped, scheme stripped, GitHub → `owner/repo` |
| `websiteMatchesSupportRepo` | website path equals the support URL's repo name; catches redirect stubs and the bare hub |
| `copyrightFormat` | single- and dual-holder forms, exactly |
| `attributionsRenderLastInOrder` | app rows never interleave with canon rows |
| `displayNormalizesAndIsIdempotent` | `2.4.1`→`v2.4.1`, `v2.4.1`→`v2.4.1`, `V2.4.1`→`v2.4.1`, `" 2.4.1 "`→`v2.4.1` |
| `everyVersionSurfaceIsPrefixed` | table over all four UI surfaces, fed un-prefixed input, each starts with `v` |
| `whatsNewVersionDefaultsToBundle` | omitting `version:` reads the plist, never a literal |
| `kitVersionIsSemver` | `DragonKitVersion.current` is well-formed |
| `noUnlocalizedUIStrings` | scans kit sources; fails on a user-visible literal outside `L()` |
| `LocalizationTests` (existing) | all new keys present in all seven `.lproj` |

`noUnlocalizedUIStrings` is a source scanner, and CLAUDE.md warns a broken checker is worse than
none — it passes everything silently. So the scanner is a **pure function over a source string**,
unit-tested against a known-bad snippet (must flag) and a known-good snippet (must not), and only
then run across the real sources. It scans the kit's own two targets, not five external repos,
which is what keeps it reliable.

Honest limit: no test catches a *new* UI surface added next year and left out of the table. The
type-level changes carry that guarantee — unreachable raw strings, deleted free-form arrays — and
the tests only pin formatting.

## Conformance triad

`CONFORMANCE.md`, `Scripts/dragon-conformance.py` and `Scripts/test_conformance.py` move
together:

- App build script must stamp `DragonCommitDate`.
- App must use `AboutSettingsPane` (extends the existing pane rule).
- Deleting the rule's fixture must itself be a violation, per the recorded trap.

## Migration

| App | Work |
|---|---|
| Ice 2 | Rewrite `AboutConfig`; delete `Acknowledgements.rtf`/`.pdf` and publish `dragonapp.com/ice-2/licenses` with the 6 libraries' notices; name them as `attributions`; fix `Copyright ©` prefix; What's New loses the raw plist version; stamp `DragonCommitDate` |
| ClipMenu 2 | Rewrite `AboutConfig`; Website moves off the `/clipmenu/` redirect stub to `/clipmenu-2/`; app-domain `L("Website")` keys retire in favour of kit keys; stamp `DragonCommitDate` |
| KeyKey 2 | Rewrite `AboutConfig`; Website moves off the `/keykey/` redirect stub to `/yahoo-keykey-2/`; real copyright replaces `倉頡／簡易 輸入法` (**the IME description is dropped** rather than adding a tagline row only one app uses); de-duplicate "Homage to the original"; 3 data attributions move to `attributions`; publish a licences page for OpenCC; What's New stops hardcoding `"2.10.0"`; stamp `DragonCommitDate` |
| Spectacle 2 | Rewrite `AboutConfig`; Website moves off the bare hub to `/spectacle-2/` (the page exists); stamp `DragonCommitDate` |
| Sample app | Rewrite `AboutConfig`; Website stays the hub as a sanctioned exception; What's New stops hardcoding `"v1.3.1"`; `run.sh` stamps `DragonCommitDate` |

## Release

Breaking by design — removing `AboutLink`, the free-form arrays, and public `WhatsNewContent.version`.

1. `v3.0.0` on dragon-kit, PR-first.
2. Bump and release all five apps by hand.

Shipping the tag is not finished until the apps bump.

## Rejected alternatives

- **Keep the free-form API, enforce with a conformance checker.** A regex over five repos cannot
  reliably enforce ordering or symbols, and drift stays representable in the type system. Rejected
  in favour of making drift a compile error.
- **Fixed slots plus a free-form credits appendix.** The appendix is the current design in
  miniature and is exactly where drift returns. `attributions` is typed `(component, source)`
  pairs in a kit-owned section, not free-form rows.
- **Move KeyKey's data attributions into an Acknowledgements document.** Rejected by the owner:
  attributions stay visible in the pane, under `Credits`.
- **Keep a bundled Acknowledgements document as a fixed slot.** Would have kept the MIT notices
  inside the app bundle, which is the safest reading of the licence. Rejected by the owner in
  favour of website-hosted licence pages; the trade-off is recorded above rather than buried.
- **A `tagline` header slot for KeyKey's `倉頡／簡易 輸入法`.** One app would use it, so it is a
  new inconsistency wearing a typed costume.
