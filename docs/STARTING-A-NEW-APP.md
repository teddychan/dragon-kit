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
- **Version to depend on:** the **newest** `vX.Y.Z` tag — §R10 fails a pin that is behind, so
  look it up rather than copying a number out of this guide:
  ```bash
  gh release view --repo teddychan/dragon-kit --json tagName -q '.tagName | ltrimstr("v")'
  ```
  — always the **newest** `vX.Y.Z` tag, not the oldest that resolves. `CONFORMANCE.md` §R10
  fails an app whose pin is behind, because a stale pin is how an app silently misses shared
  fixes; check `git tag --sort=-v:refname` in the kit before you write the number.
- **The kit's rules are machine-checked.** `CONFORMANCE.md` is normative and a checker enforces
  it in your app's CI — read it alongside this guide. The §3 scaffold wires your new app into
  it and is written to pass.
- **The release lifecycle is shared too.** Read
  [`MAC-APP-RELEASE-LIFECYCLE.md`](MAC-APP-RELEASE-LIFECYCLE.md): Debug is a local test loop,
  not a second version or public channel; only a passing public tag may ship, and the marketing
  site refreshes independently afterward. Every app—including Dragon Sample App—uses an exact
  `vX.Y.Z` public tag. One repository owns one public version series; never invent a Debug,
  Sample, App Store, or other channel-specific tag prefix.
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
- **Do not push / create the GitHub repo until the owner confirms** (outward-facing). Build locally first.
- **Debug/test builds:** when building a local hands-on test build (not a release), give it its own
  identity — bundle id `<release-bundle-id>.debug`, display name `"<App> Debug"` — so it runs beside
  any installed copy without TCC/UserDefaults/menu-bar clashes. This is local packaging only:
  do not create a Debug tag, GitHub Release, appcast, or separate marketing version, and do not
  put `Debug` inside `CFBundleShortVersionString`. Render it only as the Debug bundle's name and
  build-channel label; the local bundle remains runtime-independent through its `.debug` identity.

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
    // A localization KEY, resolved through L() at render time — a String, not a
    // LocalizedStringKey. L() falls back to the key itself, so a plain "General" renders
    // as "General" until you add Localizable.strings.
    var title: String { get }
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

### Menu-bar dropdown — `DragonAppMenu` (**required**, §R1)
```swift
statusItem.menu = DragonAppMenu.menu(DragonAppMenu.Config(
    appName: "My App",
    onAbout:  { … },
    onSettings: { … },
    onCheckForUpdates: { … },   // nil OMITS the item — pass nil for a Mac App Store build
    includeQuit: true           // false OMITS Quit — an IME is quit by the system
))
// Own menu content above the shared items? Build your menu, add your own separator, then:
myMenu.addItem(.separator()); for item in DragonAppMenu.items(config) { myMenu.addItem(item) }
```
Order, titles, casing, ellipses and SF Symbols are **canon, not per-app config** — the kit owns
them so the menus can't drift the way hand-rolled `NSMenu`s did. Constructing your own
`NSMenuItem` for About / Check for Updates / Settings / Quit is an §R1 violation and fails CI.
**Uninstall is deliberately not in this menu** (§R2) and there is no parameter to add it; it
lives in Settings as `UninstallSettingsPane`, last in the sidebar. Rebuild the menu on
`.dragonLanguageChanged` so its titles switch language live.

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
**Fixed slots.** You supply URLs and proper nouns; the kit assembles every row title, SF Symbol,
order and detail string. There is no `links` / `credits` / `acknowledgementsURL` array and no
`AboutLink` type — they existed until 3.0.0, and five apps used them to ship five visibly
different panes ("Support on GitHub" beside "Report an issue on GitHub" beside "Source", three
symbols for that one row). Adding, renaming, re-iconing or reordering a row is now a compile
error instead of something spotted in a screenshot months later.

```swift
AboutContent(
    appName: "My App",
    versionString: DragonAbout.versionString(),  // "v1.0.0 (1) · 2026-Jul-06 13:34:56 UTC"
    copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),  // ONE holder — §R13
    websiteURL: URL(string: "https://www.dragonapp.com/my-app-1/")!,
    supportURL: URL(string: "https://github.com/teddychan/my-app-1/issues")!,
    licensesURL: URL(string: "https://www.dragonapp.com/my-app-1/licenses/")!,  // required
    license: "MIT",                              // the app's OWN licence, not third-party notices
    // Everything below is optional; an omitted slot collapses without reordering the rest.
    appIcon: NSImage? = <app icon by default>,
    createdBy: String = "Teddy Chan",
    // OriginalWork(name:author:url:) → a "Based on <name> by <author>" credit AND an
    // "Original project" link to `url`. One value, both rows — see below.
    originalWork: OriginalWork? = nil,
    attributions: [Attribution] = []             // Attribution(name: "Sparkle", license: "MIT")
)
AboutSettingsPane(content: AboutContent)   // drop-in SettingsPane (id "about", icon "info.circle")
```
Rows the kit assembles from the above, in this order — the `*` slot collapses when nil:
```
header:  icon → name → versionString → copyright
links:   Website globe · Support on GitHub lifepreserver · Original project heart* · Open-source licenses doc.text
Credits: Created by · Based on* · Built with → DragonKit vX.Y.Z · License · attributions*
```
Five rules the type carries, each because an app got it wrong:

- **`websiteURL` must address `dragonapp.com/{app-name}-{major}`, the same string as
  `supportURL`'s repo name** — `content.websiteMatchesSupportRepo` checks one against the other,
  so pick a repo name that carries the major (`my-app-1`) and reuse it in both.
- **Never type the detail text beside a link.** `AboutLinkDetail` derives it from the URL, so a
  typed string can't disagree with where the row goes.
- **The upstream project is one value, not two.** `OriginalWork` carries the repository URL, so
  the `Original project` link and the `Based on` credit cannot ship apart. They were separate
  optionals until 4.0.0 and clipmenu-2 and ice-2 both filled the credit and left the link nil,
  shipping "Based on ClipMenu by Naotaka Morimoto" with nothing linking to ClipMenu.
- **`licensesURL` is required.** Name a bundled component in `attributions` and its notices have
  to be reachable; spectacle-2 and the sample app both listed `Sparkle → MIT` with no page. Every
  Dragon app links Sparkle or bundles third-party data, so the row belongs on all of them —
  publish `dragonapp.com/{app-name}-{major}/licenses/` as part of shipping the app.
- **The copyright names one holder** — the app's own, via `DragonAbout.copyright(years:holder:)`.
  A Dragon app reimplements its upstream rather than reusing its source, so it has no upstream
  copyright to assert; lineage is `OriginalWork`'s job and upstream licence text the licences
  page's. CONFORMANCE §R13 rejects a hand-typed string here.
- **An attribution is `name → licence`**, never a role label: `Attribution(name: "Sparkle",
  license: "MIT")`, not `Attribution(name: "Update framework", license: "Sparkle (MIT)")`.
  Use the SPDX identifier when the component declares one, otherwise the upstream wording
  verbatim. `Attribution(component:source:)` is deprecated for exactly this reason. DragonKit
  itself is not an attribution — the kit writes its own "Built with" row.

### What's New module (release notes)
```swift
WhatsNewContent(
    // No `version:`. The heading derives from CFBundleShortVersionString, and its `v` comes from
    // DragonVersion.display(_:). Passing one is a release blocker, not a style preference: the
    // tag gate's check 5 (MAC-APP-RELEASE-LIFECYCLE.md) rejects an explicit current-version
    // argument here, because a literal goes stale against the bundle on the very next release —
    // which is what the retired in-tree sample app did. `version` is not even public; only the
    // normalized `displayVersion` is.
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
- `<APP_DIR>` — repo folder **and** GitHub repo name, `{app-name}-{major}`, e.g. `my-app-1`. The
  major belongs in the name (`ice-2`, `clipmenu-2`, `spectacle-2`), and the same string is the
  marketing page — `dragonapp.com/<APP_DIR>` — which is why `AboutContent` can check the website
  row against the support row without a table to maintain.

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
  .dragon-conformance.json               # required by CONFORMANCE §R0 — see below
  .github/workflows/conformance.yml      # calls the kit's reusable workflow — see below
```

### `Package.swift`
```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "<TARGET>",
    platforms: [.macOS("26")],
    dependencies: [
        // Replace X.Y.Z with the newest tag (see "Version to depend on" above).
        .package(url: "https://github.com/teddychan/dragon-kit", from: "X.Y.Z"),
    ],
    targets: [
        .executableTarget(
            name: "<TARGET>",
            dependencies: [
                .product(name: "DragonKit", package: "dragon-kit"),
                // Sparkle updates — direct-download apps only; a Mac App Store build must not
                // link this. Uncommenting it is three changes, not one, or §R5 fails the first
                // PR: add the product here, add "sparkle" to `traits` in
                // .dragon-conformance.json, AND put `UpdatesSettingsPane` in the sidebar
                // between What's New and About.
                // .product(name: "DragonKitUpdates", package: "dragon-kit"),
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

    // Host-owned selection, so a menu item can open Settings directly on a specific pane
    // (About). `ManagedSettingsShell` keeps selection private and can't be re-targeted after
    // the window exists, which is why the menu path uses `SettingsShell` instead.
    private let selection = SettingsSelection()

    private lazy var settingsController = DragonSettingsWindowController(
        title: "<APP_DISPLAY> Settings",
        rootView: SettingsRoot(
            appName: "<APP_DISPLAY>",
            // Canonical sidebar order. Permissions and Uninstall are NOT optional extras:
            // §R5 requires both (Permissions only if you don't declare the `no-permissions`
            // trait), so a scaffold without them fails conformance on its first PR.
            panes: [
                AnySettingsPane(GeneralPane()),
                AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),
                AnySettingsPane(WhatsNewSettingsPane(content: WhatsNewConfig.content)),
                AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),
                AnySettingsPane(UninstallSettingsPane(config: UninstallConfig(
                    appName: "<APP_DISPLAY>",
                    suiteNames: ["<BUNDLE_ID>.settings"],
                    checklistItems: ["The app and its login item", "All settings"]
                ))),
            ],
            selection: selection
        )
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "<APP_DISPLAY>")
        // Without an autosave name the item persists anonymously as "Item-0" in whatever
        // defaults domain launched it, so debug and release builds fight over visibility.
        item.autosaveName = "<TARGET>StatusItem-<BUNDLE_ID>"

        item.menu = buildMenu()
        self.statusItem = item

        // Rebuild the menu on a language change so its titles switch live, no restart.
        NotificationCenter.default.addObserver(
            self, selector: #selector(languageChanged),
            name: .dragonLanguageChanged, object: nil
        )
    }

    /// The canonical dropdown — never hand-rolled. §R1 requires these items come from
    /// `DragonAppMenu`, which owns their order, titles, casing and SF Symbols so every
    /// Dragon app's menu matches. Uninstall is deliberately absent (§R2).
    private func buildMenu() -> NSMenu {
        DragonAppMenu.menu(DragonAppMenu.Config(
            appName: "<APP_DISPLAY>",
            onAbout: { [weak self] in self?.openAbout() },
            onSettings: { [weak self] in self?.openSettings() }
            // Add `onCheckForUpdates:` once you wire DragonKitUpdates; leaving it nil omits
            // the item, which is exactly what a Mac App Store build wants.
        ))
    }

    @objc private func languageChanged() { statusItem?.menu = buildMenu() }

    @objc private func openSettings() { settingsController.show() }

    // Set the pane BEFORE showing, so it lands on About even on the window's first, lazy open.
    @objc private func openAbout() {
        selection.paneID = "about"
        settingsController.show()
    }
}

/// Host-owned settings selection — the delegate sets `paneID`, the shell renders it.
@MainActor
@Observable
final class SettingsSelection {
    var paneID: String?
}

/// Settings root. Observing `LocalizationManager` and applying `.dragonLocalized()` makes the
/// whole window switch language live; dragon-sample-app additionally rebuilds its panes on that
/// change so injected content (About / What's New) re-localizes too.
private struct SettingsRoot: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let appName: String
    let panes: [AnySettingsPane]
    @Bindable var selection: SettingsSelection

    var body: some View {
        SettingsShell(appName: appName, panes: panes, selection: $selection.paneID)
            .dragonLocalized()
    }
}
```

> Pane order matters: `General → (your panes) → Permissions → Backup & Restore → What's New →
> Updates → About → Uninstall` is canon and §R9 checks it. The scaffold ships five of those
> slots in that relative order; slot Backup & Restore and Updates in as you add them.
>
> Swap `.accessibility()` for the permission your app actually needs. If it genuinely needs
> none — an IME receives keystrokes via the IMK server, for instance — drop the pane and add
> `"no-permissions"` to `traits` in `.dragon-conformance.json`, so the omission is a stated
> fact the checker can see rather than a silent gap.

### `Sources/<TARGET>/GeneralPane.swift` (your first app pane — replace the placeholder body with real settings)
```swift
import SwiftUI
import DragonKit

struct GeneralPane: SettingsPane {
    let id = "general"
    let title = "General"          // a localization key; L() falls back to the literal
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
            versionString: DragonAbout.versionString(), // v<short> (<build>) · <commit date> UTC
            copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),
            // Same repo name on all three rows — `websiteMatchesSupportRepo` compares the first
            // two, and the licences page lives under the same canonical path.
            websiteURL: URL(string: "https://www.dragonapp.com/<APP_DIR>/")!,
            supportURL: URL(string: "https://github.com/teddychan/<APP_DIR>/issues")!,
            licensesURL: URL(string: "https://www.dragonapp.com/<APP_DIR>/licenses/")!,
            license: "MIT"
        )
    }
}
```
`licensesURL` is required, so publishing that page is part of shipping the app — the row exists
because naming a bundled component in `attributions` and linking its notices nowhere is the half
of MIT compliance the page carries. The remaining slots are optional and omitted here on purpose:
this scaffold reimplements no upstream project (`originalWork`, which carries both the `Based on`
credit and the `Original project` link) and attributes no third-party code (`attributions` —
DragonKit is not one; the kit writes its own "Built with" row). Add each when it becomes true, not
before.

### `Sources/<TARGET>/WhatsNewConfig.swift`
```swift
import Foundation
import DragonKit

enum WhatsNewConfig {
    static var content: WhatsNewContent {
        // No `version:` — the heading reads CFBundleShortVersionString, so it can never disagree
        // with the build. Passing one fails the release gate (check 5). See §2.
        WhatsNewContent(
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
`CFBundleShortVersionString` stays the bare numeric candidate `X.Y.Z` — no `v`, no `Debug`, no
prerelease suffix; the release tag is asserted against this exact string. `CFBundleVersion` is a
placeholder that `scripts/run.sh` overwrites with the commit count, and the script also adds
`DragonCommitDate`; between them About's `v0.1.0 (123) · … UTC` line is a fingerprint of one
commit. Whatever else packages this app — a release workflow, an Xcode target — has to stamp both
the same way.

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

PLIST="$APP/Contents/Info.plist"
stamp() {  # Add-or-Set, because the key may or may not already be in the source plist
  /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PLIST"
}
stamp CFBundleExecutable "$BIN_NAME"
# Both halves of About's version line must describe the SAME commit. The build number is the
# commit count, never a hardcoded "1"; DragonCommitDate is that commit's own timestamp, and
# CONFORMANCE §R12 fails a repo where no build step stamps it — About then silently renders no
# timestamp at all rather than falling back to something that means something else.
stamp CFBundleVersion "$(git rev-list --count HEAD)"
stamp DragonCommitDate "$(git log -1 --format=%cI)"

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

### `.dragon-conformance.json` (repo root — required by §R0)
Without this file the app is in violation by definition: the checker can't find your sources,
and a missing config had to count as a failure or deleting it would be the easiest way to pass.
**Strict JSON — no comments.** The checker parses it with `json.load`, so a `//` line does not
"document" the file, it crashes the run with a `JSONDecodeError` before a single rule is
evaluated. (CONFORMANCE §R0 annotates the schema in prose; that listing is not a file to copy.)

```json
{
  "app": "<APP_DISPLAY>",
  "sources": ["Sources"],
  "strings": ["Sources/**/*.lproj/Localizable.strings"],
  "pin": {
    "file": "Package.swift",
    "pattern": "dragon-kit\", from: \"([0-9.]+)\""
  },
  "paneOrder": { "file": "Sources/<TARGET>/AppDelegate.swift" },
  "traits": [],
  "exceptions": []
}
```

- **`pin.pattern` must anchor on `dragon-kit`.** The pattern is one search over the whole file, so
  an unanchored version regex matches whichever dependency appears first. That is a live trap, not
  a hypothetical — in ice-2's `.pbxproj` it matched Sparkle's version and reported a false PASS.
- **`traits`** — add `"sparkle"` when you link `DragonKitUpdates` (and then §R5 requires
  `UpdatesSettingsPane`), `"mac-app-store"` for a sandboxed target, `"no-permissions"` if the app
  genuinely needs no TCC grant.
- **`exceptions`** — §R11; each needs a `reason` and a `sanctionedBy`.

### `.github/workflows/conformance.yml`
```yaml
name: DragonKit conformance
on: pull_request
jobs:
  conformance:
    uses: teddychan/dragon-kit/.github/workflows/conformance.yml@main
```
`@main` is deliberate and is what every Dragon app uses — the workflow reads the kit at its
default branch for the rules anyway, so a tag pin would freeze the interface while the rules
moved. Rules live in dragon-kit and only there, so you get every future rule for free.

### Verify the scaffold

`scripts/run.sh` stamps the build number and commit date from git, so the repo needs one commit
before it will run (`set -euo pipefail` + `git rev-list --count HEAD` in a repo with no `HEAD`
aborts the script). Local only — still no `gh repo create` until the owner confirms.

```bash
cd ~/git/<APP_DIR>
git init && git add -A && git commit -m "chore: scaffold <APP_DISPLAY> on DragonKit"
```
```bash
swift build            # expect: Build complete!
```
```bash
./scripts/run.sh       # ✦ menu-bar icon appears → About / Settings… / Quit; Settings shows
                       #   General / Permissions / What's New / About / Uninstall,
                       #   and About reads "v0.1.0 (1) · <commit date> UTC"
```
```bash
python3 ~/git/dragon-kit/Scripts/dragon-conformance.py --app . --kit ~/git/dragon-kit
                       # expect: PASS — no violations
```

---

## 4. Then build the real app

Once the shell runs:

1. **Brainstorm** the app's purpose and features first (don't jump to code).
2. Write a **spec**, then an **implementation plan** with **bite-sized TDD tasks**.
3. Add feature panes as `SettingsPane` conformers (like `GeneralPane`); use `DragonForm` /
   `DragonSection` / `.dragonAnnotation` for the look so it matches every other Dragon app.
4. Keep `AboutConfig` / `WhatsNewConfig` updated per release — every public release edits the
   What's New content, maintenance-only ones included, because the tag gate requires that source
   to have changed since the previous public tag (check 4) and to carry real notes or an explicit
   maintenance-only statement (check 6). Bump `CFBundleShortVersionString` to the candidate `X.Y.Z`
   and leave the version out of the notes; the heading follows the bundle.
5. App Settings, Permissions, Backup & Restore, Check for Update, and Uninstall now ship
   in DragonKit (see the cheat-sheet above; https://github.com/teddychan/dragon-sample-app wires
   up all of them). For anything DragonKit still doesn't provide, flag it: it should be added to
   DragonKit and consumed, not reimplemented per app.
6. Keep the pin current. §R10 fails a pin behind the newest kit tag, and that is the whole
   point — every app once sat on 1.3.0 while the kit was at 1.4.0, so none of them had the
   shared menu at all.

## 5. Gotchas
- Use `paneBody` (not `body`) in `SettingsPane` conformers.
- `SettingsPane.title` is a `String` localization key resolved via `L()`, **not** a
  `LocalizedStringKey`. It changed in v1.1.0 (live localization) and this guide was not
  updated, so for a month the starter pane it shipped did not conform to `SettingsPane` and
  failed to compile. It then happened a second time at 3.0.0: `AboutContent`'s `links` / `credits`
  arrays were removed, this cheat-sheet kept printing them, and the `AboutConfig.swift` it handed
  out did not compile either — while the sentence claiming verification sat right here.
- **Verified against DragonKit 4.0.0.** §3's starter files were assembled into a scratch package,
  built clean with `swift build`, and passed `dragon-conformance.py` — R10 excepted, because the
  scratch package pinned the kit by `path:` (4.0.0's required `licensesURL` and
  `OriginalWork.url` predate its tag) and the pin pattern finds no version in a path dependency.
  Re-run that before touching this claim — and note that the kit's own
  `Tests/DragonKitTests/HostWiringTests.swift` and `Tests/DragonKitUpdatesTests/HostWiringTests.swift`
  now build the same `AboutContent` / `WhatsNewContent` / `BackupConfig` / `UninstallConfig` call
  sites from a plain, non-`@testable` import, so the kit can no longer change one of them and go
  green.
- Never build an `NSMenuItem` for About / Check for Updates / Settings / Quit — §R1. Use
  `DragonAppMenu`, and note there is no way to add Uninstall to the menu (§R2), by design.
- `List` selection: DragonKit already handles optional-selection tags; you only supply panes.
- `@main` + `@MainActor static func main()` — do **not** add a `main.swift` (they conflict).
- SwiftPM identity: the product is `.product(name: "DragonKit", package: "dragon-kit")`
  (identity = repo name `dragon-kit`).
- If the pin can't resolve, you probably still have the literal `X.Y.Z` in place — replace it
  with the output of `gh release view --repo teddychan/dragon-kit --json tagName -q '.tagName | ltrimstr("v")'`. If a real version still fails, confirm the tag exists on the
  repo and check your network/gh access.

---

*This guide lives at `docs/STARTING-A-NEW-APP.md` in the dragon-kit repo and tracks its default
branch; it names no kit version on purpose.*
