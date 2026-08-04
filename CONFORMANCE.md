# DragonKit conformance spec

Normative rules every Dragon app must satisfy. The point is narrow and absolute:

> **An app supplies content and app-domain logic. It never re-implements what DragonKit owns.**

Five apps are in scope — `dragon-kit/Example` (Dragon Sample App), `clipmenu-2`, `ice-2`,
`spectacle-2`, `yahoo-keykey-2`.

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
    uses: teddychan/dragon-kit/.github/workflows/conformance.yml@v2
```

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
General → (the app's own panes) → Permissions → Sync & Backup → What's New → Updates → About → Uninstall
```

The checker extracts kit pane identifiers in declaration order from the file named by
`paneOrder` and requires their **relative** order to match. App-specific panes anywhere
between General and Permissions are fine.

## R10 — The DragonKit pin is current

The version at `pin.file`/`pin.pattern` must be `>=` the newest `vX.Y.Z` tag in dragon-kit.
An app that depends on the kit by path rather than version declares `"pin": {"kind": "path"}`
and satisfies the rule by construction — only the Dragon Sample App, which lives inside
dragon-kit, qualifies. It must still be declared, so it reads as a stated fact rather than a
silently skipped rule.

**Rationale:** a stale pin is how an app silently misses shared fixes. Every app sat on 1.3.0
while the kit was at 1.4.0, so none had the shared menu at all.

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

## Out of scope, deliberately

- **Shipping localizations.** Not having `.strings` isn't re-implementing a kit module. The
  rule is that localization *goes through* `L()`/`LocalizationManager` — not that every app
  must ship 7 languages. ice-2 is English-only and compliant.
- **App-domain code.** Hot-key recorders, window-management engines, clipboard capture,
  input-method engines: the kit has no such modules, so there is nothing to duplicate.
