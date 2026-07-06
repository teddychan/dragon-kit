# Start a new Dragon menu-bar app on DragonKit

> **Hand this file to a fresh chat session.** It is self-contained: it assumes zero prior
> context. Follow it top to bottom to scaffold a new macOS menu-bar app that consumes the
> published **DragonKit** package, then build the app's real features.

---

## 0. What you're doing

Build a new macOS **menu-bar (LSUIElement) app** on top of **DragonKit** — a published,
open-source Swift package that provides the shared foundations every "Dragon App" shares, so
you don't rebuild them: a settings window + sidebar shell, **About** and **What's New** panes,
grouped-form design primitives (the canonical look), a reliable settings-window controller for
accessory apps, and a localization helper.

- **DragonKit repo:** https://github.com/teddychan/dragon-kit (public, MIT)
- **Version to depend on:** `1.0.0` (tag), i.e. `.package(url: "https://github.com/teddychan/dragon-kit", from: "1.0.0")`
- The kit's own design spec + plan live in that repo under `docs/superpowers/` if you want the rationale.

Your job = **scaffold a runnable shell first** (this doc gives you the complete starter files),
**then** brainstorm → spec → plan → TDD the app's actual features.

---

## 1. Environment & conventions (read before writing code)

- **Toolchain:** macOS 26, Swift 6.1 (Xcode 26). Build/test with `swift build` / `swift test`.
- **Deployment target:** macOS 26 (DragonKit requires it).
- **GitHub:** `gh` is authenticated as **teddychan**. Create repos under `teddychan/`.
- **Git identity:** commit/push as `teddychan <teddychan@gmail.com>` (a global hook enforces this;
  a new local repo needs `git config user.name teddychan` + `git config user.email teddychan@gmail.com`).
- **Commit messages:** end every commit body with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- **Do not push / create the GitHub repo until the owner confirms** (outward-facing). Build locally first.
- **Debug/test builds:** when building a local hands-on test build (not a release), give it its own
  identity — bundle id `<release-bundle-id>.debug`, display name `"<App> Debug"` — so it runs beside
  any installed copy without TCC/UserDefaults/menu-bar clashes. (This is the standard Dragon-app rule.)

---

## 2. DragonKit public API cheat-sheet

Everything below is `public` in `import DragonKit`. You do **not** need to read DragonKit's source.

### Design primitives (grouped-form look; ports of ice-2)
```swift
DragonForm { /* sections */ }                                   // grouped Form
DragonSection("Header") { /* rows */ }                          // titled section
DragonSection { /* rows */ }                                    // untitled section
// also: header/content/footer overloads + DragonSectionOptions (.plain/.default/.isBordered/.hasDividers)
someRow.dragonAnnotation("Secondary caption under the row.")    // ice-2 .annotation port
someRow.dragonAnnotation { AnyCaptionView() }                   // view-builder variant
```

### Settings panes + shell
```swift
// Conform your panes to this (note: paneBody, NOT body):
public protocol SettingsPane: Identifiable where ID == String {
    var id: String { get }
    var title: LocalizedStringKey { get }
    var systemImage: String { get }
    associatedtype PaneBody: View
    @MainActor @ViewBuilder var paneBody: PaneBody { get }
}

AnySettingsPane(myPane)                                         // type-erase for the array

// Host owns selection (persist via @AppStorage, open directly to a pane):
SettingsShell(appName: "My App", panes: [AnySettingsPane], selection: Binding<String?>)
// Or self-managed (simplest; used by the scaffold below):
ManagedSettingsShell(appName: "My App", panes: [AnySettingsPane], initialSelection: String? = nil)
```

### Reliable settings window (for LSUIElement apps)
```swift
let controller = DragonSettingsWindowController(
    title: "My App Settings",
    minSize: NSSize(width: 720, height: 480),     // optional
    defaultSize: NSSize(width: 800, height: 560), // optional
    rootView: ManagedSettingsShell(appName: "My App", panes: panes)
)
controller.show()   // flips app to .regular + fronts the window; back to .accessory on close
```

### About module
```swift
AboutContent(
    appName: "My App",
    versionString: DragonAbout.versionString(), // "v1.0.0 (1) · 2026-Jul-06 13:34:56 UTC"
    copyright: "© 2026 Teddy Chan",
    appIcon: NSImage? = <app icon by default>,
    links: [AboutLink(title: "Website", detail: "dragonapp.com", systemImage: "globe", url: URL(...))],
    credits: [(label: "Created by", value: "Teddy Chan")],
    acknowledgementsURL: URL? = nil
)
AboutSettingsPane(content: AboutContent)   // drop-in SettingsPane (id "about", icon "info.circle")
```

### What's New module (release notes)
```swift
WhatsNewContent(
    version: "v1.0.0",
    date: "2026-07-01",
    summary: "One-line summary of the release.",
    sections: [
        ChangeSection(kind: .added,    entries: ["…", "…"]),
        ChangeSection(kind: .changed,  entries: ["…"]),
        ChangeSection(kind: .fixed,    entries: ["…"]),
        // Kind: .added .changed .fixed .removed .improved .security
    ]
)
WhatsNewSettingsPane(content: WhatsNewContent)  // drop-in SettingsPane (id "whatsnew", icon "sparkles")
```

### App Settings (persistence + launch at login)
```swift
// Persist an app-defined Codable value as JSON in a named UserDefaults suite:
let store = DragonSettingsStore(suiteName: "\(bundleID).settings", defaultValue: MySettings())
var settings = store.load(); settings.foo = true; store.save(settings)

LoginItem.isEnabled                 // launch-at-login state (SMAppService.mainApp)
LoginItem.setEnabled(true)          // register / unregister
```

### Permissions module
```swift
PermissionsSettingsPane(permissions: [
    .accessibility(),               // convenience factories (also .screenRecording())
    DragonPermission(id: "custom", title: "…", check: { /* Bool */ }, request: { /* prompt */ }),
])                                  // pane shows live status + Request / Open System Settings
```

### Backup & Restore module (backs up the settings suite)
```swift
BackupSettingsPane(config: BackupConfig(
    appName: "My App",
    suiteName: "\(bundleID).settings",     // the DragonSettingsStore suite
    appVersion: "1.0.0",
    relaunch: { /* re-open the app after a restore */ }
))
// Pure logic is also usable directly: DragonBackup.writeBackup(...) / .restore(...) / .prune(...)
```

### Uninstall module
```swift
UninstallSettingsPane(config: UninstallConfig(
    appName: "My App",
    suiteNames: ["\(bundleID).settings"],  // extra domains to wipe (bundle id is wiped too)
    checklistItems: ["The app and its login item", "All settings"],
    optionalDataToggle: (                  // optional, default-off toggle in the confirmation;
        label: "Also delete my data",      // its paths are deleted only if the user opts in
        paths: [appSupportFolder]
    ),
    extraCleanupPaths: [                   // always removed on uninstall
        library.appending(path: "Caches/\(bundleID)"),
        library.appending(path: "HTTPStorages/\(bundleID)"),
    ]
))                                          // confirms, then DragonUninstaller.run(...)
```

### Check for Update module (`DragonKitUpdates` product — Sparkle)
```swift
import DragonKitUpdates
let updater = DragonUpdater()               // lazily wraps SPUStandardUpdaterController
UpdatesSettingsPane(updater: updater)       // auto-check/-download toggles, Check Now, last-checked
updater.checkForUpdates()                   // e.g. from a menu item
// Needs SUFeedURL (+ SUPublicEDKey) in Info.plist. Link DragonKitUpdates ONLY for
// direct-download apps — Mac App Store apps must not bundle Sparkle.
```

### Localization
```swift
L("Some.Key")   // resolves DragonKit module bundle → app bundle → the key itself
```
For your own visible strings, `LocalizedStringKey` literals auto-localize from your app's
`Localizable.strings`. Use `L(_:)` when you need module-aware lookups.

---

## 3. Scaffold the new app (complete starter files)

Create a new **SPM executable app** at `~/git/<APP_DIR>`. Replace the placeholders everywhere:

- `<APP_DISPLAY>` — display name, e.g. `My App`
- `<TARGET>` — Swift target name (no spaces), e.g. `MyApp`
- `<BUNDLE_ID>` — e.g. `com.dragonapp.myapp`
- `<APP_DIR>` — repo folder name, e.g. `myapp`

Structure:
```
<APP_DIR>/
  Package.swift
  Sources/<TARGET>/App.swift
  Sources/<TARGET>/AppDelegate.swift
  Sources/<TARGET>/GeneralPane.swift
  Sources/<TARGET>/AboutConfig.swift
  Sources/<TARGET>/WhatsNewConfig.swift
  Resources/Info.plist
  scripts/run.sh
  .gitignore
```

### `Package.swift`
```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "<TARGET>",
    platforms: [.macOS("26")],
    dependencies: [
        .package(url: "https://github.com/teddychan/dragon-kit", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "<TARGET>",
            dependencies: [
                .product(name: "DragonKit", package: "dragon-kit"),
                // Add ONLY for direct-download (non-Mac-App-Store) apps that want Sparkle:
                .product(name: "DragonKitUpdates", package: "dragon-kit"),
            ]
        ),
    ]
)
```

### `Sources/<TARGET>/App.swift`
```swift
import AppKit

@main
struct <TARGET> {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar app, no Dock icon
        app.run()
    }
}
```

### `Sources/<TARGET>/AppDelegate.swift`
```swift
import AppKit
import SwiftUI
import DragonKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    private lazy var settingsController = DragonSettingsWindowController(
        title: "<APP_DISPLAY> Settings",
        rootView: ManagedSettingsShell(
            appName: "<APP_DISPLAY>",
            panes: [
                AnySettingsPane(GeneralPane()),
                AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),
                AnySettingsPane(WhatsNewSettingsPane(content: WhatsNewConfig.content)),
            ]
        )
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "<APP_DISPLAY>")

        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        self.statusItem = item
    }

    @objc private func openSettings() {
        settingsController.show()
    }
}
```

### `Sources/<TARGET>/GeneralPane.swift` (your first app pane — replace the placeholder body with real settings)
```swift
import SwiftUI
import DragonKit

struct GeneralPane: SettingsPane {
    let id = "general"
    let title: LocalizedStringKey = "General"
    let systemImage = "gearshape"

    var paneBody: some View {
        DragonForm {
            DragonSection("General") {
                Toggle("Launch at login", isOn: .constant(false))
                    .dragonAnnotation("Placeholder — replace with the app's real settings.")
            }
        }
    }
}
```

### `Sources/<TARGET>/AboutConfig.swift`
```swift
import Foundation
import DragonKit

enum AboutConfig {
    static var content: AboutContent {
        AboutContent(
            appName: "<APP_DISPLAY>",
            versionString: DragonAbout.versionString(), // v<short> (<build>) · <UTC build time>
            copyright: "© 2026 Teddy Chan",
            links: [
                AboutLink(title: "Website", detail: "dragonapp.com",
                          systemImage: "globe", url: URL(string: "https://www.dragonapp.com")!),
            ],
            credits: [(label: "Created by", value: "Teddy Chan")]
        )
    }
}
```

### `Sources/<TARGET>/WhatsNewConfig.swift`
```swift
import Foundation
import DragonKit

enum WhatsNewConfig {
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v0.1.0",
            date: "2026-07-01",
            summary: "First build.",
            sections: [
                ChangeSection(kind: .added, entries: ["Initial menu-bar app on DragonKit."]),
            ]
        )
    }
}
```

### `Resources/Info.plist`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string><APP_DISPLAY></string>
	<key>CFBundleDisplayName</key>
	<string><APP_DISPLAY></string>
	<key>CFBundleIdentifier</key>
	<string><BUNDLE_ID></string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>LSUIElement</key>
	<true/>
</dict>
</plist>
```

### `scripts/run.sh` (then `chmod +x scripts/run.sh`)
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="<APP_DISPLAY>"
BIN_NAME="<TARGET>"

swift build -c debug
BIN_DIR="$(swift build -c debug --show-bin-path)"

APP="$BIN_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $BIN_NAME" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $BIN_NAME" "$APP/Contents/Info.plist"
cp -R "$BIN_DIR"/*.bundle "$APP/Contents/MacOS/" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

pkill -f "$APP/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
sleep 1
open "$APP"
echo "Launched $APP"
```

### `.gitignore`
```gitignore
.DS_Store
.build/
Package.resolved
```

### Verify the scaffold
```bash
cd ~/git/<APP_DIR>
swift build            # expect: Build complete!
./scripts/run.sh       # ✦ menu-bar icon appears → Settings… shows General / About / What's New; Quit works
```

---

## 4. Then build the real app

Once the shell runs:

1. **Brainstorm** the app's purpose and features first (don't jump to code).
2. Write a **spec**, then an **implementation plan** with **bite-sized TDD tasks**.
3. Add feature panes as `SettingsPane` conformers (like `GeneralPane`); use `DragonForm` /
   `DragonSection` / `.dragonAnnotation` for the look so it matches every other Dragon app.
4. Keep `AboutConfig` / `WhatsNewConfig` updated per release.
5. App Settings, Permissions, Backup & Restore, Check for Update, and Uninstall now ship
   in DragonKit (see the cheat-sheet above; the `Example/` app wires up all of them). For
   anything DragonKit still doesn't provide, flag it: it should be added to DragonKit and
   consumed, not reimplemented per app.

## 5. Gotchas
- Use `paneBody` (not `body`) in `SettingsPane` conformers.
- `List` selection: DragonKit already handles optional-selection tags; you only supply panes.
- `@main` + `@MainActor static func main()` — do **not** add a `main.swift` (they conflict).
- SwiftPM identity: the product is `.product(name: "DragonKit", package: "dragon-kit")`
  (identity = repo name `dragon-kit`).
- If `from: "1.0.0"` can't resolve, confirm the tag exists on the repo and your network/gh access.

---

*DragonKit v1.0.0 · this guide lives at `docs/STARTING-A-NEW-APP.md` in the dragon-kit repo.*
