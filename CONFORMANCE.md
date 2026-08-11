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
  "traits": ["sparkle", "mac-app-store"],   // see §R6, §R9
  "exceptions": [                        // §R11 — each needs a reason and an owner
    { "rule": "R3", "path": "app/Sources/ClipMenu/SyncBackupPane.swift",
      "reason": "iCloud sync + versioned folder backup; DragonBackup is UserDefaults-suite only",
      "sanctionedBy": "README: backup generalization deferred until a 2nd app needs it" }
  ]
}
```

## R1 — The menu-bar dropdown comes from `DragonAppMenu`

The app-lifecycle items (About, Check for Updates, Settings, Quit) **must** be produced by
`DragonAppMenu.menu(_:)` or `DragonAppMenu.items(_:)`. An app must not construct an
`NSMenuItem` for any of them.

Apps may build their own menu *content* freely — clipboard history, input-method toggles, an
Accessibility warning row — and append the shared items after their own separator.

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
satisfied by `BackupSettingsPane` (which the kit titles "Backup & Restore") *or* by an app's
sanctioned equivalent in the same position: clipmenu-2 ships `SyncBackupPane` ("Sync & Backup")
there under §R11. The canon line names what the kit itself ships; a sanctioned divergence sits
in the same slot and is listed in §R11, not renamed in the canon.

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

A sanctioned divergence goes in `exceptions` with a `reason` and a `sanctionedBy`. The
checker prints every exception on each run, so they stay visible instead of becoming
permanent. Currently sanctioned:

| App | Rule | Divergence | Why |
|---|---|---|---|
| clipmenu-2, ice-2 | R3/R4 | own versioned folder backup pane | `DragonBackup` snapshots a UserDefaults suite only; generalizing it is deferred until a second app needs the folder shape |
| clipmenu-2 | R6 | MAS target links `DragonKit` only | Sparkle is forbidden in a sandboxed App Store build |
| yahoo-keykey-2 | R1 | `includeQuit: false` | an IME is quit by the system; quitting only makes typing unresponsive |
| yahoo-keykey-2 | R5 | no Permissions pane | an IME receives keystrokes via the IMK server and needs no TCC grant |

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

## R14 — The About copyright is kit-assembled and names one holder

> **R13 is deliberately vacant here.** It belongs to the language-picker rule in the open PR #60,
> which had claimed the number first — including a sanctioned ice-2 exception recorded against it
> — while this rule was written and merged in parallel. Two live rules sharing one number is worse
> than a gap, and the reusable workflow reads this repo's default branch, so whichever number sits
> on `main` is immediately live for all five apps. Delete this note when #60 lands.

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
apps, and dropping it is not only about consistency: a Dragon app reimplements its upstream rather
than reusing its source, so asserting the upstream author's copyright over *this* binary
contradicts the app's own notices — yahoo-keykey-2 had already reasoned its way to the
single-holder form on those grounds. Lineage is carried by `OriginalWork`, twice; upstream licence
text that must travel with copies belongs on the licences page.

## Out of scope, deliberately

- **Shipping localizations.** Not having `.strings` isn't re-implementing a kit module. The
  rule is that localization *goes through* `L()`/`LocalizationManager` — not that every app
  must ship 7 languages. ice-2 is English-only and compliant.
- **App-domain code.** Hot-key recorders, window-management engines, clipboard capture,
  input-method engines: the kit has no such modules, so there is nothing to duplicate.
