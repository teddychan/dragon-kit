# DragonKit

Shared SwiftUI foundations for [Dragon App](https://www.dragonapp.com) macOS
menu-bar apps (ice-2, clipmenu-2, KeyKey) — built and updated once.

## Status: v1.2.0 — uninstall learns about user data

Two products in one package:

- **`DragonKit`** (core, no external deps) and **`DragonKitUpdates`** (adds Sparkle) —
  so Mac App Store apps can link the core and skip Sparkle.

Modules:

- **Design primitives** — `DragonForm`, `DragonSection`, `.dragonAnnotation`
  (source-compatible ports of ice-2's grouped-`Form` look).
- **Menu** — `DragonAppMenu` builds the canonical status-item dropdown (About, Check for
  Updates, Settings, Uninstall, Quit) so every app's menu order and naming match.
- **Settings** — `SettingsShell` (host-owned selection) + `ManagedSettingsShell`;
  `DragonSettingsWindowController` opens it reliably for accessory apps; modules
  conform to `SettingsPane`.
- **App Settings** — `DragonSettingsStore<Value>` (Codable persistence in a UserDefaults
  suite) + `LoginItem` (launch at login via `SMAppService`).
- **About** — `AboutContent` + `AboutPane` / `AboutSettingsPane`.
- **What's New** — release-notes pane: `WhatsNewContent` / `ChangeSection` (Added /
  Changed / Fixed …) + `WhatsNewPane` / `WhatsNewSettingsPane`.
- **Permissions** — `DragonPermission` (+ `.accessibility()` / `.screenRecording()`) +
  `PermissionsSettingsPane` (live status, Open System Settings).
- **Backup & Restore** — `DragonBackup` (snapshot/restore a UserDefaults suite) +
  `BackupSettingsPane` (`BackupConfig`).
- **Uninstall** — `DragonUninstaller` + `UninstallView` / `UninstallSettingsPane`
  (`UninstallConfig`) — incl. an optional, default-off "also delete user data" toggle
  (`optionalDataToggle`) and always-removed `extraCleanupPaths` (caches, support files).
- **Updates** (`DragonKitUpdates`) — `DragonUpdater` (Sparkle wrapper) +
  `UpdatesSettingsPane`.
- **Localization** — `L(_:)` (module bundle → app bundle → key) with a runtime
  `LocalizationManager` + `LanguagePicker` and `.dragonLocalized()`. Ships **7 languages**
  (en, es, fr, ja, ko, zh-Hans, zh-Hant); switches **live, no restart**. Apps add their own
  `Localizable.strings` per language and drop in `LanguagePicker`.
- **Example/** — the **Dragon Sample App**, a runnable, installable **reference app** wiring up every module end-to-end:
  General (real persisted toggles), Permissions, Backup & Restore, What's New, Updates,
  About, Uninstall, plus Check-for-Updates and Quit in the menu.

## Requirements
macOS 26+, Swift 6.1.

## Use it

```swift
.package(url: "https://github.com/teddychan/dragon-kit", from: "1.0.0")
```

```swift
import DragonKit

let panes = [
    AnySettingsPane(MyGeneralPane()),
    AnySettingsPane(AboutSettingsPane(content: myAboutContent)),
]
let controller = DragonSettingsWindowController(
    title: "My App Settings",
    rootView: ManagedSettingsShell(appName: "My App", panes: panes)
)
controller.show()
```

## Settings pane order

Every Dragon app lists its settings panes in the same sidebar order, so the apps
feel like one family. The order is **host-owned** — `SettingsShell` renders panes in
the order the app puts them in its `settingsPanes` list, so each app is responsible
for following this convention:

```
General → (the app's own panes) → Permissions → Sync & Backup → What's New → Updates → About → Uninstall
```

The Dragon Sample App (`Example/`) wires its panes up in this order — mirror it in new apps.

## Menu-bar dropdown order

Every Dragon app builds its status-item dropdown from **`DragonAppMenu`** — one source of
truth for order and naming, so the menus can't drift the way hand-rolled `NSMenu`s did. The
canonical order and naming (macOS title-case, ellipsis on items that open a window/dialog,
app name appended to About / Uninstall / Quit):

```
About <App>
Check for Updates…        (omit for Mac App Store builds — pass onCheckForUpdates: nil)
Settings…            ⌘,
──────────
Uninstall <App>…          (omit if the app ships no uninstall flow)
Quit <App>           ⌘Q   (omit for an IME — pass includeQuit: false)
```

Apps whose dropdown is only these items use `DragonAppMenu.menu(_:)`; apps with their own
content above (clipboard history, input-method toggles, …) build that and append
`DragonAppMenu.items(_:)` after their own separator. The Dragon Sample App (`Example/`) uses
`DragonAppMenu.menu(_:)` — mirror it in new apps.

## Try it: the Dragon Sample App

DragonKit ships a real, installable reference app — **Dragon Sample App** — that wires up
every module (Settings, Permissions, Backup & Restore, Updates, Uninstall, About, What's New,
live localization). Install the released build with Homebrew:

```bash
brew install --cask teddychan/tap/dragon-sample-app
```

Or build and run it locally from source. `run.sh` produces a separate **Dragon Sample App
Debug** build (`com.dragonapp.dragon-sample-app.debug`) so it won't collide with an installed
copy's permissions or settings:

```bash
cd Example && ./scripts/run.sh
```

## Start a new app on DragonKit
See [`docs/STARTING-A-NEW-APP.md`](docs/STARTING-A-NEW-APP.md) — a self-contained guide
(API cheat-sheet + complete starter files) for scaffolding a new menu-bar app on this kit.

## For AI agents: how to use this template

DragonKit is a **published SwiftPM package** — the one place the shared parts of every
Dragon menu-bar app live. **Depend on it; never copy its code into your app.**

1. Read [`docs/STARTING-A-NEW-APP.md`](docs/STARTING-A-NEW-APP.md) (self-contained) and the
   `Example/` app — `Example/` is the reference wiring for every module.
2. Create an SPM executable app that depends on `dragon-kit` at a version tag
   (`from: "1.0.0"`). Link `DragonKit`; add `DragonKitUpdates` **only** for
   direct-download (non-Mac-App-Store) apps.
3. Build settings screens as `SettingsPane` conformers using `DragonForm` /
   `DragonSection` / `.dragonAnnotation`.
4. Supply your app's **content/config** — `AboutContent`, `WhatsNewContent`, a settings
   model (`DragonSettingsStore`), a `[DragonPermission]`, `BackupConfig`,
   `UninstallConfig`, `DragonUpdater` — and wire them into `ManagedSettingsShell` +
   `DragonSettingsWindowController`.

## Single source of truth

Two layers, deliberately separated:

- **Shared behavior lives here, once.** Pane layouts, the settings shell, backup logic,
  the updater, and the uninstall flow are owned by this repo. Fix or improve them **in
  `dragon-kit`**, tag a new version, and every app picks the change up by bumping its
  dependency (`swift package update`). Apps must not fork or re-implement these.
- **App-specific content is injected by each app.** Your About text, What's New entries,
  settings shape, permission list, and configs are yours — DragonKit renders them but does
  not own them.

So, for example, to change the **About pane's layout for every app**, edit `AboutPane` in
`dragon-kit` and release a new tag. To change **one app's About content** (name, links),
edit that app's `AboutConfig`. And the **version** is itself a single source of truth: read
it from the app's `Info.plist` (`CFBundleShortVersionString`) — never hardcode it (see
[`Example/Sources/DragonAppTemplate/AboutConfig.swift`](Example/Sources/DragonAppTemplate/AboutConfig.swift))
— so About, backups, and update checks all report the same value.

## Roadmap
Done: App Settings, Permissions, Backup & Restore, Check for Update, Uninstall (all
demonstrated in `Example/`). Next: migrate ice-2 / clipmenu-2 onto the kit →
settings-shell hardening → KeyKey onboarding.

Deferred, deliberately: a generalized **folder-based versioned backup** pane
(user-picked folder with a security-scoped bookmark, versioned snapshot files,
retention, restore list — the shape clipmenu-2 ships app-side). Generalize it here
only when a second app (KeyKey / ice-2) needs that same shape; until then
`DragonBackup` stays UserDefaults-suite-only.

## License
MIT.
