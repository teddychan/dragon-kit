# DragonKit

Shared SwiftUI foundations for [Dragon App](https://www.dragonapp.com) macOS
menu-bar apps (ice-2, clipmenu-2, KeyKey) — built and updated once.

## Status: v0

- **Design primitives** — `DragonForm`, `DragonSection`, `.dragonAnnotation`
  (source-compatible ports of ice-2's grouped-`Form` look).
- **Settings** — `SettingsShell` (host-owned selection) + `ManagedSettingsShell`;
  `DragonSettingsWindowController` opens it reliably for accessory apps; modules
  conform to `SettingsPane`.
- **About** — `AboutContent` + `AboutPane` / `AboutSettingsPane`.
- **Localization** — `L(_:)` (module bundle → app bundle → key).
- **Example/** — a runnable minimal menu-bar app template using all of the above.

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

## Roadmap
Backup & Restore → Check for Update → Uninstall → settings-shell hardening →
app-template polish → KeyKey onboarding.

## License
MIT.
