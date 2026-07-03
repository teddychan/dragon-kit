# DragonKit

Shared SwiftUI foundations for [Dragon App](https://www.dragonapp.com) macOS
menu-bar apps (ice-2, clipmenu-2, KeyKey) — built and updated once.

## Status: v1

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
.package(url: "https://github.com/teddychan/dragon-kit", from: "0.1.0")
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

## Roadmap
Done: App Settings, Permissions, Backup & Restore, Check for Update, Uninstall (all
demonstrated in `Example/`). Next: migrate ice-2 / clipmenu-2 onto the kit →
settings-shell hardening → KeyKey onboarding.

## License
MIT.
