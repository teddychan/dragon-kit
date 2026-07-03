# DragonKit

Shared SwiftUI foundations for [Dragon App](https://www.dragonapp.com) macOS
menu-bar apps (ice-2, clipmenu-2, KeyKey) — built and updated once.

## Status: v1.0.0 — the first template

Two products in one package:

- **`DragonKit`** (core, no external deps) and **`DragonKitUpdates`** (adds Sparkle) —
  so Mac App Store apps can link the core and skip Sparkle.

Modules:

- **Design primitives** — `DragonForm`, `DragonSection`, `.dragonAnnotation`
  (source-compatible ports of ice-2's grouped-`Form` look).
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
  (`UninstallConfig`).
- **Updates** (`DragonKitUpdates`) — `DragonUpdater` (Sparkle wrapper) +
  `UpdatesSettingsPane`.
- **Localization** — `L(_:)` (module bundle → app bundle → key).
- **Example/** — a runnable **reference app** wiring up every module end-to-end:
  General (real persisted toggles), Permissions, Updates, Backup & Restore, Uninstall,
  About, What's New, plus Check-for-Updates and Quit in the menu.

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

## Run the template

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

## License
MIT.
