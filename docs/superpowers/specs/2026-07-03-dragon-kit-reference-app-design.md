# DragonKit v1 — complete reference app (design)

- **Date:** 2026-07-03
- **Status:** Approved in brainstorm; building
- **Owner:** Teddy Chan
- **Related apps:** `ice-2`, `clipmenu-2`, `yahoo-keykey-2`
- **Source material:** ported from `ice-2`, branch `claude/ice-2-rewrite-from-scratch`

## 1. Purpose

Turn the `Example/` app into a **complete reference app** that exercises every key
Dragon-app feature end-to-end — About, What's New, real persisted **Settings**
(Launch at login, Show in menu bar, a demo toggle), **Check for Update**, **Check
Permission**, **Uninstall**, **Backup & Restore**, and **Quit** — by adding the missing
features to DragonKit as bundled modules and wiring them into the sample.

## 2. Key decisions (from brainstorm)

1. **One repo**, current flat folder-module style (`Sources/DragonKit/<Module>/`).
2. **Full feature set** demonstrated in `Example/`, with **real persisted settings** so
   Backup & Restore operates on live data.
3. **DragonKit bundles the real implementations** (SMAppService, Sparkle, TCC APIs) — not
   an injected-protocol design. Reuse working code from ice-2's rewrite branch.
4. **Sparkle is isolated in its own product** so Mac App Store apps (ClipMenu) don't link
   it: core `DragonKit` (no Sparkle) + `DragonKitUpdates` (Sparkle). One repo, one
   `Package.swift`, two library products.

## 3. Package structure

`Package.swift` gains a second product/target:

- **`DragonKit`** (core, no new external deps): existing `DesignSystem/`, `Settings/`,
  `About/`, `WhatsNew/`, `Localization/` **plus new** `AppSettings/`, `Permissions/`,
  `Backup/`, `Uninstall/`.
- **`DragonKitUpdates`** (depends on `DragonKit` + **Sparkle 2.6**): `Updates/`.

MAS apps link only `DragonKit`; direct-download apps link both. `Example/` links both.

## 4. New modules (ported + generalized)

- **`AppSettings/`**
  - `DragonSettingsStore<Value: Codable & Sendable>` — generic persistence of an
    app-defined settings value as JSON under one key in a named UserDefaults suite
    (generalized from `Ice2Core/SettingsStore`).
  - `LoginItem` — `SMAppService.mainApp` register/unregister (ported as-is, made public).
- **`Permissions/`**
  - `DragonPermission` — config model (`id, title, details, isRequired, settingsURLs,
    check, request`) generalized from legacy `Ice/Permissions/Permission.swift`, with
    `.accessibility()` / `.screenRecording()` convenience factories.
  - `PermissionsPane` / `PermissionsSettingsPane` — renders an app-supplied
    `[DragonPermission]` with live status + Request / Open Settings + periodic refresh.
- **`Backup/`**
  - `DragonBackup` — pure/injectable snapshot & restore of a whole UserDefaults **suite**
    (persistent domain) to a `.dragonbackup` binary plist (`schemaVersion, appVersion,
    createdDate, suiteName, defaults`), with list/prune (keep newest 10). Generalized from
    `SettingsBackup` (suite-domain snapshot instead of a fixed key enum).
  - `BackupConfig` + `BackupSettingsPane` — folder chooser, Back Up Now, Reveal, list with
    Restore/Delete, auto-backup-on-quit toggle. App supplies `appName`, `suiteName`,
    `appVersion`, and a `relaunch` handler. Pane's own prefs live in `standard` defaults
    (not the backed-up suite), so backups never include backup settings.
- **`Uninstall/`**
  - `UninstallConfig`, `DragonUninstaller.run(...)` (disable login item, wipe defaults
    domains, delete leftover prefs/saved-state, trash the app, quit), `UninstallView` +
    `UninstallWindowController` (generic, ported), `UninstallSettingsPane` (button).
- **`Updates/`** (in `DragonKitUpdates`)
  - `DragonUpdater` — wraps `SPUStandardUpdaterController`, created lazily on first use
    (launch-safe for unsigned dev builds), proxying auto-check / auto-download / last-check
    / can-check and `checkForUpdates()`.
  - `UpdatesSettingsPane` — auto-check + auto-download toggles, "Check for Updates…",
    last-checked label (ported from legacy `UpdatesSettingsPane`).

DragonKit stays free of app-specific identifiers; everything app-specific is injected.

## 5. Sample (`Example/`) app

Rebranded **DragonKit Sample** (`com.dragonapp.dragonkit-sample`). Settings live in a
dedicated suite `<bundleID>.settings`.

- `SampleSettings: Codable` — `launchAtLogin`, `showInMenuBar`, `playSound` (demo).
- `SettingsModel` (`@MainActor @Observable`) wraps `DragonSettingsStore`; setters persist
  and apply side effects (login item, menu-bar visibility notification).
- Status menu: **Settings… · Check for Updates… · Quit**.
- Panes, in order: **General** (real toggles) · **Permissions** (Accessibility demo) ·
  **Updates** · **Backup & Restore** · **Uninstall** · **About** · **What's New**.
- Safety: at launch the menu-bar icon reflects `showInMenuBar`; if hidden, Settings opens
  automatically so the user can toggle it back (never trapped).

## 6. Testing

swift-testing units: `DragonSettingsStore` round-trip; `DragonBackup` snapshot→restore
round-trip, replace-not-merge, prune-to-10, schema/version errors; `DragonPermission`
model. `Example` must `swift build`. Manual: toggle settings → back up → change → restore
→ values return; permissions status reflects reality; uninstall dialog shows.

## 7. Build order (dependency-sequenced)

1. `Package.swift` (2 products) + `AppSettings` (store + LoginItem) + real General pane.
2. `Permissions` + pane.
3. `Backup` + pane.
4. `Uninstall` + view/controller.
5. `DragonKitUpdates` (Sparkle) + pane.
6. Wire all into `Example`; update README + `STARTING-A-NEW-APP.md`.

## 8. Notes

- For hands-on test builds, follow the standard Dragon rule (re-id `<App> Debug` /
  `<id>.debug`) if running beside an installed copy; the sample ships its own identity so
  there's no clash by default.
- `SUFeedURL` is a placeholder — "Check for Updates" proves the pane/flow, not a live feed.
</content>
