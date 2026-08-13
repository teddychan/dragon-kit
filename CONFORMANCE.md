# DragonKit conformance spec

Normative rules every Dragon app must satisfy. The point is narrow and absolute:

> **An app supplies content and app-domain logic. It never re-implements what DragonKit owns.**

Five apps are in scope, one repository each — `dragon-sample-app` (Dragon Sample App),
`clipmenu-2`, `ice-2`, `spectacle-2`, `yahoo-keykey-2`. The Sample App used to live inside
dragon-kit as `sample-app/`; it moved out because
[`docs/MAC-APP-RELEASE-LIFECYCLE.md`](docs/MAC-APP-RELEASE-LIFECYCLE.md) allows a repository only
one public `vX.Y.Z` series and this one's belongs to the Swift package. It is checked here like
any other app, not exempted as the kit's own fixture.

These rules are **machine-checked**, not review-enforced. `Scripts/dragon-conformance.py`
implements them; `.github/workflows/conformance.yml` is a reusable workflow each app calls
from its own CI, so a violation fails the PR. Rules live here and only here — apps get new
rules automatically by pinning the workflow at a major tag.

## Why this exists

Every rule below is a failure that actually happened, not a hypothetical. Before 2026-08-04
all four shipping apps had independently hand-rolled the same menu and drifted: three
different string sets, two casings, two update icons, a stray ellipsis, and one app with no
icons. ice-2 had `IceForm`/`IceSection` files that were line-for-line identical to
`DragonForm`/`DragonSection`, plus its own Sparkle wiring — so it silently missed a shared
alert reword. clipmenu-2 and keykey-2 each duplicated the kit's menu strings in their own
`.strings` files, which is how the casing drifted invisibly.

Documentation did not prevent any of it. The design spec even *mandated* the drifted item.

## How to comply

Add `.dragon-conformance.json` to the app repo root (schema in §R0) and call the workflow:

```yaml
# .github/workflows/conformance.yml
name: DragonKit conformance
on: pull_request
jobs:
  conformance:
    uses: teddychan/dragon-kit/.github/workflows/conformance.yml@main
```

`@main` is deliberate, and it's what all five apps use. The workflow reads the kit at
its default branch anyway, so pinning it to a tag would freeze the *interface* while the
*rules* still moved — the pin buys nothing and the version drifts out of date silently.
If you ever want the workflow itself pinned, cut a floating `v2` tag on dragon-kit first
(the way `dragon-release-ci` maintains `v5`); until then `@v2` does not resolve.


Run it locally the same way CI does:

```bash
python3 /path/to/dragon-kit/Scripts/dragon-conformance.py --app .
```

---

## R0 — Declare the app

**`.dragon-conformance.json` must exist at the app repo root.** Without it the checker cannot
know where an app keeps its sources, and a missing config is itself a violation (otherwise
deleting the file would be the easiest way to "pass").

```jsonc
{
  "app": "ClipMenu 2",
  "sources": ["app/Sources"],            // Swift source roots to scan
  // Does double duty: §R8 reads the keys inside these files, and §R13 reads the `.lproj`
  // directory names in the paths to learn which languages the app ships its own strings in.
  "strings": ["app/Sources/**/*.lproj/Localizable.strings"],
  "pin": {                               // where the DragonKit version is declared
    "file": "app/Package.swift",
    // MUST anchor on dragon-kit. The pattern is one search over the whole file, so an
    // unanchored version regex silently matches whichever dependency appears first. In an
    // Xcode .pbxproj this is a live trap: `minimumVersion = ([0-9.]+)` matched Sparkle's
    // 2.5.2 in ice-2 and compared *that* against DragonKit's tags. Anchor it:
    //   "dragon-kit\";[^}]*minimumVersion = ([0-9.]+)"
    "pattern": "dragon-kit\", from: \"([0-9.]+)\""
  },
  "paneOrder": { "file": "app/Sources/ClipMenu/SettingsWindowController.swift" },
  "traits": ["sparkle", "mac-app-store"],   // see §R5, §R6
  // §R11, and this is the real value in all five apps: empty. The schema is shown there,
  // not here, because an example exception reads as a live sanction — this one named a
  // rule R3 never fired and a path (`SyncBackupPane.swift`) clipmenu-2 does not have.
  "exceptions": []
}
```

## R1 — The lifecycle menu comes from `DragonAppMenu`

The app-lifecycle items (About, Check for Updates, Settings, Quit) **must** be produced by
`DragonAppMenu.menu(_:)` or `DragonAppMenu.items(_:)`. An app must not construct an
`NSMenuItem` for any of them.

Apps may build their own menu *content* freely — clipboard history, input-method toggles, an
Accessibility warning row — and append the shared items after their own separator.

The host still owns dispatch at a system boundary. KeyKey's IMK menu obtains the canonical
`NSMenuItem`s from `DragonAppMenu.items(_:)`, then retargets those same items to `@objc` selectors
on `InputController`, because IMK routes top-level selections back to the input controller rather
than honoring the closure-backed item's private target. This adapter does not hand-build a
lifecycle item and is not an R11 exception: DragonKit still supplies each item's title, icon,
order, and omission behavior.

**Violation:** any `NSMenuItem(title:)` whose title literal or `L()` key matches a lifecycle
item, or an app that never references `DragonAppMenu`.

**Rationale:** this is the drift that motivated the whole spec. Order, naming, casing,
ellipsis, icons and the omission rules (`onCheckForUpdates: nil` for Mac App Store,
`includeQuit: false` for an IME) are canon, not per-app choices.

## R2 — Uninstall is not in the menu

There is no `Uninstall` item in the dropdown, and no way to add one — `DragonAppMenu.Config`
has no such parameter since v2.0.0. Uninstall is `UninstallSettingsPane`, last in the
sidebar.

**Violation:** any menu item whose title contains "uninstall" (case-insensitive).

**Rationale:** a rarely-used destructive action does not belong one click away in the
everyday menu, next to Quit.

## R3 — No app type may shadow a public DragonKit type

An app must not declare a `struct`/`class`/`enum`/`protocol` whose name matches a public
DragonKit type. The checker derives the list from the kit's own sources, so it stays correct
as the kit grows.

**Violation:** e.g. an app-local `UpdatesSettingsPane`, `BackupSettingsPane`, `UninstallView`.

**Rationale:** ice-2 declared its own `UpdatesSettingsPane` and `BackupSettingsPane` in files
that also `import DragonKit`. It compiled — Swift resolves the local type — so the app
silently used its own copy while looking like it used the kit's. Name collision is the most
dangerous drift because it is invisible.

## R4 — No re-implemented design primitives

Settings UI uses `DragonForm`, `DragonSection` and `.dragonAnnotation`. An app must not
declare its own grouped-`Form` wrapper.

**Violation:** a type declaration containing both `Form {` and `.formStyle(.grouped)`, or a
type named `*Form`/`*Section`/`*GroupBox` that isn't from the kit.

**Rationale:** `IceForm`/`IceSection` were line-for-line identical to the kit types — the kit
was *ported from them* and ice-2 never adopted the port back.

## R5 — Shared panes come from the kit

About, What's New, Permissions, Updates and Uninstall must be the kit's panes. Required
references: `AboutSettingsPane` or `AboutPane`; `WhatsNewSettingsPane` or `WhatsNewPane`;
`UninstallSettingsPane`; `UpdatesSettingsPane` (unless the app lacks the `sparkle` trait);
`PermissionsSettingsPane` (unless the app has the `no-permissions` trait).

**Rationale:** every pane an app writes itself is a pane that stops receiving shared fixes.
ice-2's own updates pane meant it never got the reworded "up to date" alert.

## R6 — Updates go through `DragonKitUpdates`

An app must not import Sparkle directly or touch `SPUStandardUpdaterController`/`SPUUpdater`.
Use `DragonUpdater`. Apps with the `mac-app-store` trait link `DragonKit` only and pass
`onCheckForUpdates: nil`.

## R7 — Launch-at-login goes through `LoginItem`

No direct `SMAppService` use and no third-party launch-at-login package.

**Rationale:** two code paths writing the same `SMAppService.mainApp` registration is a
split-brain waiting to happen, and the uninstall flow has to unregister it too.

## R8 — The app owns no kit string keys

App `.strings` files must not define any key beginning `DragonKit.`, nor any key that is one
of the kit's canonical menu titles used verbatim as a key (`About %@`, `Check for Updates…`,
`Settings…`, `Quit %@`, `Uninstall %@…`).

**Rationale:** clipmenu-2 and keykey-2 both duplicated these across their own locale files,
which is exactly how the casing drifted without anyone noticing. Note `L()` resolves the
module bundle **first**, so an app cannot override a kit key even if it tries — a duplicated
key is dead weight that merely *looks* authoritative.

## R9 — Settings pane order matches the canon

```
General → (the app's own panes) → Permissions → Backup & Restore → What's New → Updates → About → Uninstall
```

The checker extracts kit pane identifiers in declaration order from the file named by
`paneOrder` and requires their **relative** order to match. App-specific panes anywhere
between General and Permissions are fine.

Each slot is matched on the **pane identifier**, never on its display title — so a slot is
satisfied by `BackupSettingsPane` (which the kit titles "Backup & Restore") or by a recognized
app-specific spelling in the same position. For example, clipmenu-2 ships `SyncBackupPane`
("Sync & Backup") in the Backup slot. This is an R9 slot spelling, not an R11 exception. The
canon line names what the kit itself ships rather than every recognized identifier.

**Rationale:** the canon line used to read "Sync & Backup" — clipmenu-2's name for it — while
the kit's own pane is titled "Backup & Restore" and the checker's slot spellings recognized
only `BackupSettingsPane`/`backup`. So the one app whose pane is named differently had this
slot **silently unchecked**: `\bbackup\b` doesn't match `SyncBackupPane`, R9 compares only the
slots it actually saw, and clipmenu-2 passed with its backup pane free to sit anywhere in the
order. Three names for one slot, and the gap was in the app the rule most needed to cover.

## R10 — The DragonKit pin is current

The version at `pin.file`/`pin.pattern` must be `>=` the newest `vX.Y.Z` tag in dragon-kit.
**Every app pins a published version — there is no path-dependency exemption.**

**Rationale:** a stale pin is how an app silently misses shared fixes. Every app sat on 1.3.0
while the kit was at 1.4.0, so none had the shared menu at all.

`"pin": {"kind": "path"}` used to satisfy this rule by construction, for the one app that
depended on the kit by `path: ".."` because it lived inside it. That app owns its own repository
now, so nothing qualifies — and the branch was an always-pass with no fixture behind it, which
made it the cheapest way for any app to opt out of the staleness check. Declaring it is now
itself an R10 violation, the same way §R0 makes deleting `.dragon-conformance.json` one.

## R11 — Exceptions are explicit, reasoned, and few

A sanctioned divergence goes in the app's own `.dragon-conformance.json` — which is the only
place the checker reads them from — with a `reason` and a `sanctionedBy`:

```jsonc
"exceptions": [
  { "rule": "R15", "path": "Sources/DragonAppTemplate/AboutConfig.swift",
    "reason": "no public app page exists; the site hosts only /dragon-sample-app/licenses/",
    "sanctionedBy": "CONFORMANCE.md §R11" }
]
```

The checker prints every exception on each run, so they stay visible instead of becoming
permanent. **The target is none at all, and as of 2026-08-12 exactly one is declared across all
five apps** — the one above, dragon-sample-app's, which §R15 landed and which is reasoned below.
Keep it there — an exception is the last resort, after a trait, a slot spelling, and changing the
app.

### What this table used to say

It listed five "currently sanctioned" exceptions, for months, while **not one of them was
declared in any app** — the checker printed nothing on every run of all five. None was ever
needed:

| Was listed | Why it needed no exception |
|---|---|
| clipmenu-2, ice-2 — R3/R4, own folder backup pane | `SyncBackupPane` and `IceBackupSettingsPane` shadow no kit type and hand-roll no grouped `Form`, so R3 and R4 never fired on them. The deferral is real — `DragonBackup` snapshots a UserDefaults suite only — but §R9 carries it, by listing the app's spelling in the Backup slot. |
| clipmenu-2 — R6, MAS links `DragonKit` only | R6 fires on `import Sparkle` in Swift sources. A *target* that omits a product gives it nothing to see. Declared as the `mac-app-store` trait. |
| yahoo-keykey-2 — R1, `includeQuit: false` | A parameter of `DragonAppMenu.Config`. Using the kit's own knob is compliance, not divergence. |
| yahoo-keykey-2 — R5, no Permissions pane | Carried by the `no-permissions` **trait**, which R5 reads directly. |

A row naming a rule the checker never fires is worse than no row: it reads as a live sanction,
nothing contradicts it, and the next app copies the shape. Traits and slot spellings are how a
*structural* difference gets declared; `exceptions` is only for a rule that genuinely fires and is
genuinely allowed to. If a row cannot be traced to a violation the checker would otherwise print,
it does not belong here.

### The live one

| App | Rule | Divergence | Declared | Lifts when |
|---|---|---|---|---|
| dragon-sample-app | R15 | About's Website row is `dragonapp.com`, not `dragonapp.com/dragon-sample-app/` | yes — `.dragon-conformance.json`, at `Sources/DragonAppTemplate/AboutConfig.swift` | the app gets a public page, if it ever does |

One row, one app, one rule. It is the only exception declared anywhere across the five.

**dragon-sample-app has no public-facing page, on purpose.** The site's only page for it is
`/dragon-sample-app/licenses/`: there is no
`docs/dragon-sample-app/index.html` and no card for it on the hub. The app exists to exercise
DragonKit's modules — it ships no feature of its own — so it is a released, updatable, licence-
carrying app without a product page. Pointing its Website row at the canonical path would ship a
404, so it addresses the studio hub, and `AboutContent.websiteMatchesSupportRepo` is `false` for
it and `true` for the other four. Every other rule applies to it unchanged.

§R15 is that property, and the exception landed in **dragon-sample-app's** repo before the rule
landed here: a rule merged here is live in five apps' CI the same day, so merging in the other
order would have red-X'd the app for a divergence already agreed. In between it was inert — the
checker matches exceptions by rule name, so it only added a printed line — which is what made
landing it first safe.

**ice-2's R13 row is gone, unused.** It sat here reserved from the day R13 landed: ice-2 shipped no
localization at all — no `.lproj`, no String Catalog, no `L()` call site — so nothing on disk
stated its coverage, and the sanction was written down in advance so it would already be agreed
when the app adopted a picker. It never was declared, and now never will be. ice-2 PR #102 ships
all seven locales and calls `LanguagePicker()` bare, which is what R13 asks of an app whose
coverage matches the kit's; **all five apps now satisfy R13 outright.**

Worth recording, because it is the second time this section has made the same point: the row was
never load-bearing. R13 is silent for an app that constructs no `LanguagePicker`, so for the whole
time it was listed there was no violation for it to sanction — and ice-2's `strings` glob matched
no files either, which meant R8 had nothing to read as well. Both rules passed that app by doing
no work. The fix was in the app (point the glob at real locale files; ship them), not here. A
reserved row is still a row that reads as a live sanction to the next person, which is exactly
what the table above records as the mistake.

## R12 — The build stamps `DragonCommitDate`

Some build step must write `git log -1 --format=%cI` into the packaged `Info.plist` as
`DragonCommitDate`, alongside the `CFBundleVersion = git rev-list --count HEAD` stamp. The
checker greps the app's build surface for the key — a shell script, a workflow, an `Info.plist`
placeholder or an Xcode project all satisfy it. Declare `buildFiles` to narrow where it looks.

**Rationale:** About renders `v2.4.1 (756) · 2026-Aug-07 16:54:20 UTC`. The count came from the
commit; the timestamp came from the *executable's* modification date — when CI linked and signed
the binary. The two halves described different things and drifted: rebuild the same commit
tomorrow and the count holds while the date moves. `DragonAbout` now reads `DragonCommitDate`, so
the line fingerprints one commit. It shows no date at all when the key is absent — a silent
fallback to the old meaning is exactly the drift this replaced — which is why *not* stamping it
has to be a violation rather than a quietly shorter version line.

## R13 — The language picker offers exactly the languages the app ships

Every `LanguagePicker(` construction must offer **exactly** the locales the app has translated
its own strings into. The app's set is read from the `.lproj` directory names in the paths its
`strings` globs match (§R0) — the same config §R8 already uses — and the offered set is either the
literal `languages:` argument or, when there is none, the kit's default of
`DragonLanguage.selectable`.

So a bare `LanguagePicker()` is correct for an app whose coverage matches the kit's, and a
violation for one whose coverage is narrower. clipmenu-2, spectacle-2 and dragon-sample-app all
call it bare and all ship seven `.lproj`; a rule that simply demanded an explicit argument would
fail three conforming apps.

**Violation:** the offered set differs from the shipped set in either direction; a `languages:`
argument that isn't a literal list, or that names something which is no `DragonLanguage` case; or
a picker in an app with no `.lproj` reachable through `strings` at all, where nothing can be
compared and the rule would otherwise pass by having no work to do.

Compared as equality because the picker is the app's own statement of its coverage. Offering more
than it ships is the shipping bug below; shipping more than it offers is translation work no user
can select. A `.lproj` `DragonLanguage` has no case for is not counted — `Base.lproj` is not a
language, and a `de.lproj` is one the picker physically cannot list, so counting either would
leave the rule with no satisfiable form. The direction that matters is untouched: a locale the kit
lacks can never enter the offered list either.

**Rationale:** yahoo-keykey-2 shipped through v2.11.4 calling `LanguagePicker()` bare while
shipping only `App/en.lproj` and `App/zh-Hant.lproj`, so its Settings offered Español, Français,
日本語, 한국어 and 简体中文 — and choosing one translated the kit's four panes while every KeyKey
string fell back to English. ice-2 hit the same default first: PR #83 added Simplified Chinese
alone, and its contributor hand-rolled a three-option picker in `GeneralSettingsPane`, the
re-implementation §R4 forbids. DragonKit 3.4.0 added the `languages:` parameter for exactly this
— and **the parameter existing did not stop it happening again.** Nothing failed on keykey's
picker; it was found by eye while verifying an unrelated pin bump, which is the definition of a
rule that needs machine-checking. Fixed in yahoo-keykey-2 PR #103 as
`LanguagePicker(languages: [.en, .zhHant])`.

The checker reads the written argument rather than asserting through the type, because
`LanguagePicker.languages` is `private` and `offeredLanguages` is `internal`, so a constructed
picker reveals nothing to an app-side test. yahoo-keykey-2's
`ConfigContentTests.testLanguagePickerOffersExactlyTheShippedLocalizations` is the app-local
version of this comparison and stays as it is; this rule is what gives the other four apps the
same signal.

## R14 — The About copyright is kit-assembled and names one holder

`copyright:` must come from `DragonAbout.copyright(years:holder:)` and name the app's own
copyright holder only. The checker rejects a string literal in the slot, two `©` on one line, and
the `original:` argument removed in DragonKit 4.0.0.

**Rationale:** the rest of the About pane's slots are closed by the kit's own signature, and need
no rule here. `licensesURL` is a required parameter; the upstream project's repository lives
*inside* `OriginalWork`, so the `Original project` link and the `Based on` credit are one value.
Both were separate optionals, and all four combinations shipped: clipmenu-2 and ice-2 credited an
upstream project the pane never linked, while spectacle-2 and the sample app listed `Sparkle → MIT`
in Credits with no notices page anywhere — found by putting five screenshots side by side, which
is how About drift has been found every time. Under 4.0.0 each of those is a compile error, caught
by the app's own build.

`copyright` is a plain `String`, so no signature can close it — which is exactly why it gets the
rule. The dual-holder line (`© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan`) was in two of five
apps and not the other three.

**The rule is about this slot, not about who holds the copyright.** An earlier draft of it argued
that a Dragon app reimplements its upstream rather than reusing its source and therefore has no
upstream copyright to assert. That is true of yahoo-keykey-2, which had reasoned its way to the
single-holder form on exactly those grounds — and false of the two apps the rule actually touched.
ice-2 is a **git fork** of Jordan Baird's Ice, 1371 commits from its `Initial commit`, GPL-3.0, and
GPL §4 requires the upstream notice to travel with a derivative work; clipmenu-2's own `LICENSE`
names both Naotaka Morimoto and Teddy Chan. Generalising from one app's situation to a legal claim
about all five was wrong, and it was caught by an agent that refused the instruction and went and
read the licences.

So the reason is narrower and holds regardless of lineage: **the About header is a presentation
slot in a settings pane, and it read one way in three apps and another in two.** The upstream
copyright is carried where it legally belongs — the `LICENSE` file and the licences page — neither
of which this rule touches. ice-2's `LICENSE` fills in the GPL's own notice template with Jordan
Baird's name and year, and its `Acknowledgements.rtf` states the fork inherits GPL-3.0; clipmenu-2's
`LICENSE` names Naotaka Morimoto and Teddy Chan. Lineage in the pane is `OriginalWork`'s job, twice
over: the `Original project` link and the `Based on` credit.

**`NSHumanReadableCopyright` is not on that list, and all five apps set it to `© 2026 Teddy
Chan`.** This document used to cite ice-2's dual-holder value as the example of an upstream notice
travelling correctly outside the pane. ice-2 changed it in 2.14.7 and the reasoning is worth
keeping: the key is an *optional* Apple one that no licence names — three of the five apps shipped
without it at all — so it draws a line in Finder's Get Info panel rather than discharging an
obligation, and having it disagree with About made the app state two different things about itself
depending on where you looked. It is still out of scope for this rule; it simply is not where §4
is satisfied. Nothing here requires an app to set it, or to set it any particular way — but if the
five ever diverge there, that is a second presentation slot drifting, not a licence question.

## R15 — About's Website row addresses the app's canonical page

`websiteURL`'s path must equal the repository name in `supportURL` — `dragonapp.com/ice-2/`
against `github.com/teddychan/ice-2/issues`. The site convention is
`dragonapp.com/{app-name}-{major}`, which is also the GitHub repo name for every Dragon app, so
the Website row and the Support row check each other and there is no table of URLs to maintain.

This is the per-app assertion of `AboutContent.websiteMatchesSupportRepo`, which the kit has had
since the About slots were fixed. The checker reads the written literals out of the app's
sources — the way §R13 reads the `languages:` argument — because the property is only reachable
from a *constructed* `AboutContent`, and constructing one means building the app. It follows one
hop of indirection: clipmenu-2 and ice-2 both name their URLs in a `let` before passing them, and
a rule that only understood a literal at the call site would read nothing at all for two of the
five apps.

**Rationale:** nothing checked this per app. clipmenu-2 and yahoo-keykey-2 assert it in their own
test suites; spectacle-2, ice-2 and dragon-sample-app shipped the row on trust, and giving those
three the signal is the point of the rule. The failure it catches is silent by construction — a
wrong Website row still resolves in a browser. `dragonapp.com/clipmenu/` is a `<meta refresh>`
stub whose `rel=canonical` points at `/clipmenu-2/`; it opens fine, and only this comparison
distinguishes it from the page the app actually has.

**Anything the rule cannot read is a violation, never a skip** — an argument that resolves to no
literal, a support row that names no `github.com/owner/repo`, or no `AboutContent(…)` construction
under `sources` at all. §R0, §R10 and §R13 all take the same line, for the same reason: a checker
that goes quiet when an app restructures reports a pass on every app that stopped conforming.

**dragon-sample-app is the one sanctioned divergence** (§R11) and it is declared in its own
repository. It has no public page on purpose: the site hosts `/dragon-sample-app/licenses/` but
no product page for the app, so the canonical path would be a 404 and the row addresses the
studio hub. `websiteMatchesSupportRepo` is `false` for it and `true` for the other four.

## Out of scope, deliberately

- **Shipping localizations.** Not having `.strings` isn't re-implementing a kit module. The
  rule is that localization *goes through* `L()`/`LocalizationManager` — not that every app
  must ship 7 languages. As of ice-2 PR #102 all five happen to, but an English-only app would
  still be compliant, and no rule here should be read as requiring otherwise. §R13 doesn't change
  this: it constrains what a picker *claims*, so an app with no `LanguagePicker` is outside it
  entirely, and an app with one is only ever asked to agree with whatever it does ship.
- **App-domain code.** Hot-key recorders, window-management engines, clipboard capture,
  input-method engines: the kit has no such modules, so there is nothing to duplicate.
