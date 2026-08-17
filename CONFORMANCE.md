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
from its own CI, so a violation fails the PR. Rules live here and only here — every app calls the
workflow `@main`, so **a rule merged here is live in all five apps' CI the same day.** See "How to
comply" below for why the pin is `@main` and not a tag.

**Every rule below is a failure that actually happened, with one stated exception.** §R16 is a
convention adopted before the divergence it prevents cost anything, and it says so in its own
text rather than borrowing an incident that did not happen — which is itself one of the mistakes
[Incidents](docs/CONFORMANCE-INCIDENTS.md) collects. The failure itself — which app, which
bug, which wrong first attempt at the rule — is recorded once, in
[`docs/CONFORMANCE-INCIDENTS.md`](docs/CONFORMANCE-INCIDENTS.md), section by section. Read it
before relaxing a rule or writing a new one. This file states the rules; that one says why they
are shaped the way they are.

## Why this exists

Documentation did not prevent any of the drift these rules exist to stop. Four shipping apps had
independently hand-rolled the same lifecycle menu; the design spec even *mandated* one of the
drifted items. That is the whole argument for machine-checking, and the detail is in
[Incidents → Why the spec exists at all](docs/CONFORMANCE-INCIDENTS.md#why-the-spec-exists-at-all).

Three consequences that govern how every rule below is written:

- **A rule that is only written down is not a rule.** `CONFORMANCE.md` (the rule),
  `Scripts/dragon-conformance.py` (the enforcement) and `Scripts/test_conformance.py` (the test for
  the enforcement) change **together**, or not at all.
- **A broken checker is worse than no checker** — it passes everything silently.
- **Anything a rule cannot read is a violation, never a skip.** A checker that goes quiet when an
  app restructures reports a pass on every app that stopped conforming.

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

Starting a new app? [`docs/STARTING-A-NEW-APP.md`](docs/STARTING-A-NEW-APP.md) carries a scaffold
written to pass every rule here, including a copyable `.dragon-conformance.json`.

---

## R0 — Declare the app

**`.dragon-conformance.json` must exist at the app repo root**, and **`sources`, `strings` and
`paneOrder` are all required.** A missing file, or a missing key, used to switch off its rule in
silence — which is the same shape as deleting the file to "pass".

The listing below is **annotated JSONC for reading. The real file is strict JSON** — the checker
parses it with `json.load`, so a `//` line raises `JSONDecodeError` before a single rule is
evaluated. Copy the file from
[`docs/STARTING-A-NEW-APP.md`](docs/STARTING-A-NEW-APP.md#dragon-conformancejson-repo-root--required-by-r0),
not from here.

```jsonc
{
  "app": "ClipMenu 2",
  "sources": ["app/Sources"],            // Swift source roots to scan. REQUIRED.
  // REQUIRED. Double duty: §R8 reads the keys inside these files, and §R13 reads the `.lproj`
  // directory names in the paths to learn which languages the app ships its own strings in.
  "strings": ["app/Sources/**/*.lproj/Localizable.strings"],
  "pin": {                               // where the DragonKit version is declared
    "file": "app/Package.swift",
    // MUST anchor on dragon-kit — see §R10. An unanchored version regex matches whichever
    // dependency appears first in the file. In an Xcode .pbxproj, anchor it:
    //   "dragon-kit\";[^}]*minimumVersion = ([0-9.]+)"
    "pattern": "dragon-kit\", from: \"([0-9.]+)\""
  },
  "paneOrder": { "file": "app/Sources/ClipMenu/SettingsWindowController.swift" },  // REQUIRED. §R9.
  "traits": ["sparkle", "mac-app-store"],   // see §R5, §R6
  "exceptions": []                       // §R11. Empty is the starting point for a new app.
}
```

If an app genuinely cannot supply `sources`, `strings` or `paneOrder` — String Catalogs instead of
`.lproj`, say — that is what §R11 is for: a sanctioned exception with a reason and an owner,
printed on every run.

→ [Incidents §R0](docs/CONFORMANCE-INCIDENTS.md#r0--declare-the-app)

## R1 — The lifecycle menu comes from `DragonAppMenu`

The app-lifecycle items (About, Check for Updates, Settings, Quit) **must** be produced by
`DragonAppMenu.menu(_:)` or `DragonAppMenu.items(_:)`. An app must not construct an
`NSMenuItem` for any of them.

Apps may build their own menu *content* freely — clipboard history, input-method toggles, an
Accessibility warning row — and append the shared items after their own separator.

The host still owns dispatch at a system boundary. KeyKey's IMK menu obtains the canonical
`NSMenuItem`s from `DragonAppMenu.items(_:)`, then retargets those same items to `@objc` selectors
on `InputController`. This adapter does not hand-build a lifecycle item and is not an R11
exception: DragonKit still supplies each item's title, icon, order, and omission behavior.

**Violation:** any `NSMenuItem(…)` whose arguments contain a title literal or `L()` key matching a
lifecycle item, or an app that never references `DragonAppMenu` **in code**. Both halves read the
code, not the line: arguments are read as a whole, from a copy that keeps literals but not comments.

**Why:** every one of these properties is canon, and four apps proved they drift when each app owns
them. Omissions are canon too — they come from `DragonAppMenu.Config`, not from a hand-built item.

→ [Incidents §R1](docs/CONFORMANCE-INCIDENTS.md#r1--the-lifecycle-menu-comes-from-dragonappmenu)

## R2 — Uninstall is not in the menu

There is no `Uninstall` item in the dropdown, and no way to add one — `DragonAppMenu.Config`
has no such parameter since v2.0.0. Uninstall is `UninstallSettingsPane`, last in the
sidebar.

**Violation:** any menu item whose arguments contain "uninstall" (case-insensitive), read across
the whole construction — see §R1 on why one line was not enough.

**This rule has its own `exceptions` key.** Sanctioning `R2` suppresses `R2` and nothing else.

**Why:** destructive and rare is the wrong neighbour for Quit.

→ [Incidents §R2](docs/CONFORMANCE-INCIDENTS.md#r2--uninstall-is-not-in-the-menu)

## R3 — No app type may shadow a public DragonKit type

An app must not declare a **top-level** `struct`/`class`/`enum`/`protocol` whose name matches a
top-level public DragonKit type. The checker derives the list from the kit's own sources, so it
stays correct as the kit grows.

**Violation:** e.g. an app-local top-level `UpdatesSettingsPane`, `BackupSettingsPane`,
`UninstallView`.

**Top-level on both sides, and that is the rule, not a limitation of the checker.** A nested type
lives in its own namespace and cannot shadow anything.

**Why:** an app-local copy compiles — Swift resolves the local type — so the app silently uses its
own version while looking like it uses the kit's. Name collision is the most dangerous drift
because it is invisible.

→ [Incidents §R3](docs/CONFORMANCE-INCIDENTS.md#r3--no-app-type-may-shadow-a-public-dragonkit-type)

## R4 — No re-implemented design primitives

Settings UI uses `DragonForm`, `DragonSection` and `.dragonAnnotation`. An app must not
declare its own grouped-`Form` wrapper.

**Violation:** a type declaration containing both `Form {` and `.formStyle(.grouped)`, or a
type named `*Form`/`*Section`/`*GroupBox` that isn't from the kit.

**Rationale:** `IceForm`/`IceSection` were line-for-line identical to the kit types — the kit
was *ported from them* and ice-2 never adopted the port back.

→ [Incidents §R4](docs/CONFORMANCE-INCIDENTS.md#r4--no-re-implemented-design-primitives) — including
a parked owner decision about this rule's prose. Do not act on it without the owner.

## R5 — Shared panes come from the kit

About, What's New, Permissions, Updates and Uninstall must be the kit's panes. Required
references: `AboutSettingsPane` or `AboutPane`; `WhatsNewSettingsPane` or `WhatsNewPane`;
`UninstallSettingsPane`; `UpdatesSettingsPane` (unless the app lacks the `sparkle` trait);
`PermissionsSettingsPane` (unless the app has the `no-permissions` trait).

The reference must be **in code**, not in a comment.

**Why:** every pane an app writes itself is a pane that stops receiving shared fixes.

→ [Incidents §R5](docs/CONFORMANCE-INCIDENTS.md#r5--shared-panes-come-from-the-kit)

## R6 — Updates go through `DragonKitUpdates`

An app must not import Sparkle directly or touch `SPUStandardUpdaterController`/`SPUUpdater`.
Use `DragonUpdater`. Apps with the `mac-app-store` trait link `DragonKit` only and pass
`onCheckForUpdates: nil`.

## R7 — Launch-at-login goes through `LoginItem`

No direct `SMAppService` or `SMLoginItemSetEnabled` use, no `LSSharedFileList` route, and no
third-party launch-at-login package (`LaunchAtLogin`, `LoginServiceKit`).

Third-party names are matched on `import` or a member access, never bare, so that *naming* a
library stays distinguishable from *using* one.

**Why:** two code paths writing the same `SMAppService.mainApp` registration is a split-brain
waiting to happen, and the uninstall flow has to unregister it too.

**§R6 and §R7 are deny-lists, deliberately — neither has a positive form.** A positive form would
fail an app with the `mac-app-store` trait, or an app that simply has no launch-at-login feature.
What a deny-list costs is that it only knows the routes written into it.

→ [Incidents §R6 and §R7](docs/CONFORMANCE-INCIDENTS.md#r6-and-r7--why-both-are-deny-lists)

## R8 — The app owns no kit string keys

App `.strings` files must not define any key beginning `DragonKit.`, nor any key that is one
of the kit's canonical menu titles used verbatim as a key (`About %@`, `Check for Updates…`,
`Settings…`, `Quit %@`, `Uninstall %@…`).

**Why:** duplicated kit keys are how the menu's casing drifted invisibly. `L()` resolves the module
bundle **first**, so a duplicate cannot even take effect — it is dead weight that merely *looks*
authoritative.

→ [Incidents §R8](docs/CONFORMANCE-INCIDENTS.md#r8--the-app-owns-no-kit-string-keys)

## R9 — Settings pane order matches the canon

```
General → (the app's own panes) → Permissions (when applicable) → Backup & Restore → What's New → Updates (when applicable) → About → Uninstall
```

**This exact line is the canon**, and it is quoted from here by `CLAUDE.md`, `README.md`,
`TechDebt.md` and the two guides.

**Two slots are conditional, and §R5 owns both conditions** — Permissions is omitted for an app
declaring the `no-permissions` trait, Updates for an app without `sparkle`. Both carry the marker
so neither reads as mandatory: annotating one and not the other is how a reader concludes the
unmarked one is required, which for Updates would mean telling a Mac App Store target to ship a
pane it cannot link. Every other slot is required, and the relative order never changes.

The checker extracts kit pane identifiers in declaration order from the file named by
`paneOrder` — a **required** key (§R0) — and requires their **relative** order to match.
App-specific panes anywhere between General and Permissions are fine.

Each slot is matched on the **pane identifier**, never on its display title — so a slot is
satisfied by `BackupSettingsPane` (which the kit titles "Backup & Restore") or by a recognized
app-specific spelling in the same position. The Backup slot recognizes clipmenu-2's
`SyncBackupPane` and ice-2's `IceBackupSettingsPane`, both of which are R9 slot spellings and not
R11 exceptions. Both go when those two apps migrate to `BackupSettingsPane` + `DragonBackup` — see
[TechDebt.md](TechDebt.md); they are migration debt, not a supported difference. The canon line
names what the kit itself ships rather than every recognized identifier.

→ [Incidents §R9](docs/CONFORMANCE-INCIDENTS.md#r9--settings-pane-order-matches-the-canon)

## R10 — The DragonKit pin is current

The version at `pin.file`/`pin.pattern` must be `>=` the newest `vX.Y.Z` tag in dragon-kit.
**Every app pins a published version — there is no path-dependency exemption**, and declaring
`"pin": {"kind": "path"}` is itself an R10 violation.

**`pin.pattern` must anchor on dragon-kit, and the checker reads the pattern to make sure it
does.** The pattern is one search over the whole file, so an unanchored version regex matches
whichever dependency appears first and reports a false PASS on a stale pin. The anchor is tested on
the pattern with its separators removed, so yahoo-keykey-2's `DRAGONKIT_TAG="v([0-9.]+)"` satisfies
it exactly as `dragon-kit", from: "([0-9.]+)"` does.

**Why:** a stale pin is how an app silently misses shared fixes.

→ [Incidents §R10](docs/CONFORMANCE-INCIDENTS.md#r10--the-dragonkit-pin-is-current) — the Sparkle
false-PASS trap, and the test that asserted it as expected behaviour.

## R11 — Exceptions are explicit, reasoned, and few

A sanctioned divergence goes in the app's own `.dragon-conformance.json` — which is the only
place the checker reads them from — with a `reason` and a `sanctionedBy`. **All four fields are
validated:**

| Field | Rule |
|---|---|
| `rule` | must be one the checker can actually suppress: `R1`–`R9`, `R12`–`R16`. `R0`, `R10` and `R11` are not suppressible by design |
| `path` | optional — but **not accepted on `R5`, `R8`, `R9`, `R12` or `R16`**, which are whole-app checks |
| `reason` | non-empty |
| `sanctionedBy` | non-empty |

```jsonc
"exceptions": [
  { "rule": "R15", "path": "Sources/DragonAppTemplate/AboutConfig.swift",
    "reason": "no public app page exists; the site hosts only /dragon-sample-app/licenses/",
    "sanctionedBy": "CONFORMANCE.md §R11" }
]
```

The checker prints every exception on each run, so they stay visible instead of becoming
permanent. **The target is none at all.** An exception is the last resort, after a trait, a slot
spelling, and changing the app.

### The registry is what the apps declare, and an empty one proves nothing

**The exception registry is the union of the entries in the five apps' `.dragon-conformance.json`
files, and nothing else.** No prose here, no historical note, and no memory adds an entry to it.
The schema shown in §R0 is the empty starting point for a new app, not a statement about the fleet.

**An empty registry means only that no divergence is *declared*.** It does not mean the app was
checked, and it does not mean the app conforms — the two are independent, and reading one off the
other is a reasoning error this section has made twice. Where current source or a current checker
run has not established a result, say **not currently verified** rather than "conforming".

Three things follow, and each has already been got wrong here:

- **A prose-only reservation was never an exception.** If it was never declared in an app's
  config, it never suppressed anything, so it is historical context — not a live sanction, and not
  a "resolved" one either. Retiring it changes nothing about that app's conformance.
- **The checker validates an entry's shape, not its necessity.** It enforces all four fields
  above, but nothing checks that the rule would actually *fire* without the entry. That is still a
  review step: reproduce the unsuppressed violation before treating an entry as load-bearing.
- **A sample or reference app is not a special case.** It declares an exception on exactly the
  same terms as a production app would.

**To learn what is currently sanctioned, read the five apps' config files** — or run the checker,
which prints them:

```bash
for r in clipmenu-2 ice-2 spectacle-2 yahoo-keykey-2 dragon-sample-app; do
  git -C ~/git/$r fetch -q && git -C ~/git/$r show origin/main:.dragon-conformance.json
done
```

This document deliberately keeps no copy of that list. A copy here would be a second registry, and
[Incidents §R11](docs/CONFORMANCE-INCIDENTS.md#the-five-phantom-sanctions) records what happened
the last time one existed: five sanctions sat in this section for months while not one of them was
declared in any app.

→ [Incidents §R11](docs/CONFORMANCE-INCIDENTS.md#r11--exceptions-are-explicit-reasoned-and-few) —
the five phantom sanctions that sat here for months while none was declared anywhere, ice-2's
reserved R13 row, and why dragon-sample-app's §R15 exception landed in its own repo first.

## R12 — The build stamps `DragonCommitDate`

Some build step must write `git log -1 --format=%cI` into the packaged `Info.plist` as
`DragonCommitDate`, alongside the `CFBundleVersion = git rev-list --count HEAD` stamp. The
checker greps the app's build surface for **a stamp**, not for the word. Declare `buildFiles` to
narrow where it looks.

**The recognized spellings are a closed list**, and a correct stamp written any other way is a
violation — add the route here and to `COMMIT_DATE_STAMPS`, or sanction §R12 under §R11:

- PlistBuddy `Set :DragonCommitDate` / `Add :DragonCommitDate`
- a `<key>DragonCommitDate</key>` entry in an `Info.plist`, including an empty placeholder
- `INFOPLIST_KEY_DragonCommitDate` in an Xcode project
- `plutil` or `defaults write` naming the key
- an assignment to the key by index — `pl["DragonCommitDate"] = …` — which is how a `plistlib` or
  Ruby `plist` stamper writes it without shelling out

Saying which spellings count and enforcing a *whitelist* are the same statement here; listing them
descriptively while rejecting everything else would be a rule documented more broadly than it is
enforced, which is the failure this document exists to prevent.

**Why:** About's version line has to fingerprint one commit. Without the stamp it renders no date
at all — a silent fallback to the old, drifting meaning is exactly what this replaced, which is why
*not* stamping it has to be a violation rather than a quietly shorter line.

→ [Incidents §R12](docs/CONFORMANCE-INCIDENTS.md#r12--the-build-stamps-dragoncommitdate)

## R13 — The language picker offers exactly the languages the app ships

Every `LanguagePicker(` construction must offer **exactly** the locales the app has translated
its own strings into. The app's set is read from the `.lproj` directory names in the paths its
`strings` globs match (§R0) — the same config §R8 already uses — and the offered set is either the
literal `languages:` argument or, when there is none, the kit's default of
`DragonLanguage.selectable`.

So a bare `LanguagePicker()` is correct for an app whose coverage matches the kit's, and a
violation for one whose coverage is narrower. A rule that simply demanded an explicit argument
would fail every conforming app that ships all seven.

**Violation:** the offered set differs from the shipped set in either direction; a `languages:`
argument that isn't a literal list, or that names something which is no `DragonLanguage` case; a
`typealias` for `LanguagePicker`, which hides the call site the rule reads; or a picker in an app
with no `.lproj` reachable through `strings` at all, where nothing can be compared.

`LanguagePicker.init()` is the same construction and counts. A call inside `/* … */` does **not**.

A `.lproj` `DragonLanguage` has no case for is not counted — `Base.lproj` is not a language, and a
`de.lproj` is one the picker physically cannot list.

**Why:** an app once offered five languages it had not translated a single string into, so choosing
one translated the kit's four panes and left every app string in English.

→ [Incidents §R13](docs/CONFORMANCE-INCIDENTS.md#r13--the-language-picker-offers-exactly-the-languages-the-app-ships)
— including why it compares as equality, and why it reads the written argument rather than the type.

## R14 — The About copyright is kit-assembled and names one holder

`copyright:` must come from `DragonAbout.copyright(years:holder:)` and name the app's own
copyright holder only.

**The slot is checked positively: whatever fills it must *be* that call.** The checker rejects
anything else — a string literal, a constant, a helper — plus two `©` on one line and the
`original:` argument removed in DragonKit 4.0.0. A rule that reads the written call site cannot
follow an indirection to see what it names, so an indirection is a violation rather than a skip;
§R13 and §R15 take the same line for the same reason.

**This is a rule about a presentation slot, not about who holds a copyright.** The upstream
copyright is carried where it legally belongs — the `LICENSE` file and the licences page — neither
of which this rule touches. Lineage inside the pane is `OriginalWork`'s job, twice over: the
`Original project` link and the `Based on` credit. `NSHumanReadableCopyright` is out of scope;
nothing here requires an app to set it, or to set it any particular way.

**Why:** `copyright` is a plain `String`, so no signature can close it — and the header read one
way in three apps and another in two.

→ [Incidents §R14](docs/CONFORMANCE-INCIDENTS.md#r14--the-about-copyright-is-kit-assembled-and-names-one-holder)
— **read this before editing the rule above.** It records a legal justification that was written
here once, was wrong on the facts for two of the five apps, and must not be reinstated.

## R15 — About's Website row addresses the app's canonical page

`websiteURL`'s path must equal the repository name in `supportURL` — `dragonapp.com/ice-2/`
against `github.com/teddychan/ice-2/issues` — **and both rows must be on the host they claim.**
The site convention is `dragonapp.com/{app-name}-{major}`, which is also the GitHub repo name for
every Dragon app, so the Website row and the Support row check each other and there is no table of
URLs to maintain.

**Violation:** a Website row on any host but `dragonapp.com` or a subdomain of it; a Support row on
any host but `github.com` or a subdomain of it; a path that does not equal the repository name.
Hosts are matched on the label boundary, so `www.` is a subdomain and `notgithub.com` is not.

This is the per-app assertion of `AboutContent.websiteMatchesSupportRepo`, which the kit has had
since the About slots were fixed. The checker reads the written literals out of the app's sources —
the way §R13 reads the `languages:` argument — and follows one hop of indirection, because two apps
name their URLs in a `let` before passing them.

**Anything the rule cannot read is a violation, never a skip** — an argument that resolves to no
literal, a support row that names no `github.com/owner/repo`, or no `AboutContent(…)` construction
under `sources` at all.

**Why:** a wrong Website row still resolves in a browser, so nothing but this comparison
distinguishes a redirect stub from the page the app actually has.

An app with no public page can sanction this rule under §R11, in its own repository.

→ [Incidents §R15](docs/CONFORMANCE-INCIDENTS.md#r15--abouts-website-row-addresses-the-apps-canonical-page)

## R16 — The app bundle's inputs live in `App/`

The files that go **into** the `.app` and are not Swift source — the `Info.plist`, the icon and
the entitlements — live in a directory called `App/` at the repo root. Capital A, at the root, in
every Dragon app, whether it is built by `swiftc`, SwiftPM or an Xcode project:

```
App/
  Info.plist
  AppIcon.icns
  <AppName>.entitlements
  <BundleName>/Info.plist      # one directory per ADDITIONAL bundle the repo ships
```

**Only `App/Info.plist` is required.** The icon and the entitlements are checked *positionally* —
an app that ships one keeps it here; an app that ships none is not asked to invent one. ice-2
draws its icon from an `AppIcon.appiconset` in an asset catalog and three of the five apps sign
with no entitlements file, so requiring either would leave those apps one compliant path:
fabricate the file. That is the `IceGroupBox` mistake §R4 records.

**A multi-bundle app puts the main bundle's inputs directly in `App/`, and gives every additional
bundle a directory named after it.** ice-2 ships `Ice` and `MenuBarItemService`, so it is
`App/Info.plist` plus `App/MenuBarItemService/Info.plist`. The symmetric alternative — a
directory per bundle, the main one included — was considered and rejected: the checker would then
have to be *told* which directory holds the main bundle, and a rule that trusts a declared name
instead of reading a fixed path is the shape §R10's anchoring incident is about.
[Incidents §R16](docs/CONFORMANCE-INCIDENTS.md#r16--the-app-bundles-inputs-live-in-app) records
the comparison.

**Violation:** no `App/` directory at the repo root; no `App/Info.plist`; or an `Info.plist`,
`*.entitlements` or `*.icns` anywhere else in the repo, including more than one directory deep
inside `App/`. `app/` is not `App/` — the check reads the directory listing rather than asking
whether the path exists, because macOS's case-insensitive filesystem answers yes to both and a
case-blind test would report the apps that still have to move as already conforming. A nested
checkout is another repository's working tree and is not read.

**Out of scope:** Swift sources, `.lproj` strings, asset catalogs and every other resource. This
rule places three kinds of file; it says nothing about what else `App/` may contain — KeyKey keeps
its sources there — and nothing about where a bundle's *source* lives.

**Why — and this one is not an incident.** Apple publishes no convention for where these files sit
in a source tree. Xcode 13+ defaults to `GENERATE_INFOPLIST_FILE = YES` and ships no file at all;
where a template does declare a path it is `___PACKAGENAME___/Info.plist`, named explicitly in
`INFOPLIST_FILE` with no auto-discovery; SwiftPM has no `Info.plist` concept for an executable;
and the Human Interface Guidelines cover interface design, not repository structure. **This is a
fleet convention, adopted for mechanical checkability, one debug-build script template and
deterministic new-app onboarding — not an Apple requirement, and nothing here should be read as
claiming otherwise.** Five apps had picked four different places, each internally consistent, and
no user-visible failure resulted; what it cost was paid by everything that reads across the fleet.

**Status: reported, not yet enforced.** Four apps have not migrated, so `R16_ENFORCED` is `False`
in `Scripts/dragon-conformance.py` and a finding prints as `pending R16 …` without failing the
run. It is not a skip: the findings are computed and printed on every run, and
`Scripts/test_conformance.py` asserts both that they appear and that the same findings *are*
violations with the gate flipped, so turning it on stays a one-line change.
[TechDebt.md](TechDebt.md) owns the migration and is what the checker's `TODO(R16)` names.

→ [Incidents §R16](docs/CONFORMANCE-INCIDENTS.md#r16--the-app-bundles-inputs-live-in-app)

## Out of scope, deliberately

- **Shipping localizations.** Not having `.strings` isn't re-implementing a kit module. The
  rule is that localization *goes through* `L()`/`LocalizationManager` — not that every app
  must ship 7 languages. An English-only app is compliant, and no rule here should be read as
  requiring otherwise. §R13 doesn't change this: it constrains what a picker *claims*, so an app
  with no `LanguagePicker` is outside it entirely, and an app with one is only ever asked to agree
  with whatever it does ship.
- **App-domain code.** Hot-key recorders, window-management engines, clipboard capture,
  input-method engines: the kit has no such modules, so there is nothing to duplicate.
- **Current fleet state.** This document states rules, not results. Which apps pass, which declare
  an exception, and which pin what are answered by running the checker — not by reading a headcount
  that was true on the day it was typed.
