# dragon-kit v0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the open-source `dragon-kit` Swift package (DragonKit library: design primitives, settings shell + window controller, localization helper, About module) plus a runnable minimal menu-bar **Example** app that uses it.

**Architecture:** One SwiftPM library `DragonKit` (namespaced modules) consumed by an SPM-based Example app. DragonKit's primitives are **source-compatible ports** of ice-2's `IceForm`/`IceSection`/`.annotation` (same API surface + defaults), so later app migration is a near-mechanical rename. Settings is a data-driven `NavigationSplitView` shell with host-owned selection, opened via a reusable accessory-app `NSWindowController`. App-specific data (About content, app name) is injected by the host.

**Tech Stack:** Swift 6.1, SwiftUI + AppKit, SwiftPM, swift-testing, macOS 26 deployment target. Repo: `~/git/dragon-kit` (local; public `teddychan/dragon-kit` pushed only after v0 builds green).

**Reference spec:** `docs/superpowers/specs/2026-06-30-dragon-kit-v0-template-design.md`

**Conventions:** Commit as `teddychan <teddychan@gmail.com>` (repo already configured). End each commit message with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Run all `swift` commands from `~/git/dragon-kit` unless noted.

---

## File structure (locked)

```
dragon-kit/
  Package.swift
  Sources/DragonKit/
    DesignSystem/DragonForm.swift
    DesignSystem/DragonSection.swift
    DesignSystem/Annotation.swift
    Settings/SettingsPane.swift            # SettingsPane protocol + AnySettingsPane
    Settings/SettingsShell.swift           # SettingsShell + ManagedSettingsShell
    Settings/SettingsWindowController.swift # DragonSettingsWindowController
    Localization/L.swift
    About/AboutContent.swift               # AboutContent + AboutLink
    About/AboutPane.swift                  # AboutPane view + AboutSettingsPane
    Resources/en.lproj/DragonKit.strings
  Tests/DragonKitTests/
    LocalizationTests.swift
    AboutContentTests.swift
    SettingsPaneTests.swift
  Example/
    Package.swift
    Sources/DragonAppTemplate/App.swift          # @main entry
    Sources/DragonAppTemplate/AppDelegate.swift
    Sources/DragonAppTemplate/GeneralPane.swift
    Sources/DragonAppTemplate/AboutConfig.swift
    Resources/Info.plist
    scripts/run.sh
  LICENSE
  README.md
  .gitignore
  .github/workflows/ci.yml
```

---

## Task 1: Package skeleton that builds

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `Sources/DragonKit/DragonKit.swift` (temporary marker, removed in Task 2)
- Create: `Sources/DragonKit/Resources/en.lproj/DragonKit.strings`
- Create: `Tests/DragonKitTests/SmokeTests.swift`

- [ ] **Step 1: Write `.gitignore`**

```gitignore
.DS_Store
.build/
*.xcodeproj
Example/.build/
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DragonKit",
    defaultLocalization: "en",
    platforms: [.macOS("26")],
    products: [
        .library(name: "DragonKit", targets: ["DragonKit"]),
    ],
    targets: [
        .target(
            name: "DragonKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DragonKitTests",
            dependencies: ["DragonKit"]
        ),
    ]
)
```

- [ ] **Step 3: Add a temporary source + resource + smoke test so it compiles**

`Sources/DragonKit/DragonKit.swift`:

```swift
// Temporary marker so the empty target compiles; removed in Task 2.
enum DragonKit {}
```

`Sources/DragonKit/Resources/en.lproj/DragonKit.strings`:

```
"DragonKit.ping" = "pong";
```

`Tests/DragonKitTests/SmokeTests.swift`:

```swift
import Testing

@Test func packageBuilds() {
    #expect(Bool(true))
}
```

- [ ] **Step 4: Build and test**

Run: `swift build`
Expected: `Build complete!`
Run: `swift test`
Expected: `Test run with 1 test ... passed`

- [ ] **Step 5: Commit**

```bash
cd ~/git/dragon-kit
git add Package.swift .gitignore Sources Tests
git commit -m "feat: DragonKit package skeleton (builds + smoke test)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Localization helper `L`

**Files:**
- Create: `Sources/DragonKit/Localization/L.swift`
- Delete: `Sources/DragonKit/DragonKit.swift` (temporary marker)
- Test: `Tests/DragonKitTests/LocalizationTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/DragonKitTests/LocalizationTests.swift`:

```swift
import Testing
@testable import DragonKit

@Suite struct LocalizationTests {
    @Test func resolvesKeyFromModuleBundle() {
        #expect(L("DragonKit.ping") == "pong")
    }

    @Test func fallsBackToKeyWhenMissing() {
        #expect(L("DragonKit.no.such.key") == "DragonKit.no.such.key")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LocalizationTests`
Expected: FAIL — `cannot find 'L' in scope`.

- [ ] **Step 3: Implement `L` and remove the marker file**

`Sources/DragonKit/Localization/L.swift`:

```swift
import Foundation

/// Resolve a localized string for `key`: DragonKit's module bundle first, then the
/// host app's `Localizable.strings`, else the key itself. Lets each module ship its
/// own strings while letting the app override any key.
public func L(_ key: String, table: String = "DragonKit") -> String {
    let sentinel = "\u{0}"
    let fromModule = Bundle.module.localizedString(forKey: key, value: sentinel, table: table)
    if fromModule != sentinel { return fromModule }
    let fromApp = Bundle.main.localizedString(forKey: key, value: sentinel, table: nil)
    if fromApp != sentinel { return fromApp }
    return key
}
```

Delete the temporary marker:

```bash
rm Sources/DragonKit/DragonKit.swift
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter LocalizationTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: L() module-then-app localization helper

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Design primitives (source-compatible ports of ice-2)

**Files:**
- Create: `Sources/DragonKit/DesignSystem/DragonForm.swift`
- Create: `Sources/DragonKit/DesignSystem/DragonSection.swift`
- Create: `Sources/DragonKit/DesignSystem/Annotation.swift`

> These mirror ice-2's `IceForm`/`IceSection`/`.annotation` **API surface and defaults**
> (compat params, `DragonSectionOptions`, the full init overload set, and an annotation
> with `.subheadline`/spacing-2 defaults), so later ice-2 migration is a rename, not a
> rewrite. Pure view wrappers — verified by `swift build`, exercised on screen in Task 8.

- [ ] **Step 1: Write `DragonForm`**

`Sources/DragonKit/DesignSystem/DragonForm.swift`:

```swift
import SwiftUI

/// A settings form on the system's grouped `Form`. Source-compatible port of ice-2's
/// `IceForm`: layout params are accepted for call-site compatibility; layout is driven
/// by the grouped `Form`.
public struct DragonForm<Content: View>: View {
    private let content: Content

    public init(
        alignment: HorizontalAlignment = .center,
        padding: EdgeInsets = .dragonFormDefaultPadding,
        spacing: CGFloat = .dragonFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    public init(
        alignment: HorizontalAlignment = .center,
        padding: CGFloat,
        spacing: CGFloat = .dragonFormDefaultSpacing,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
    }

    public var body: some View {
        Form { content }
            .formStyle(.grouped)
            .focusSection()
            .accessibilityElement(children: .contain)
    }
}

public extension EdgeInsets {
    /// Default padding for a ``DragonForm`` (port of ice-2's `iceFormDefaultPadding`).
    static let dragonFormDefaultPadding = EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20)
}

public extension CGFloat {
    /// Default spacing for a ``DragonForm``.
    static let dragonFormDefaultSpacing: CGFloat = 10
}
```

- [ ] **Step 2: Write `DragonSection` + `DragonSectionOptions`**

`Sources/DragonKit/DesignSystem/DragonSection.swift`:

```swift
import SwiftUI

/// Compatibility options carried over from ice-2's `IceSectionOptions`. Grouping and
/// dividers are provided by the system grouped `Form`; these are accepted for source
/// compatibility with ice-2 call sites.
public struct DragonSectionOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let isBordered = DragonSectionOptions(rawValue: 1 << 0)
    public static let hasDividers = DragonSectionOptions(rawValue: 1 << 1)

    public static let plain: DragonSectionOptions = []
    public static let `default`: DragonSectionOptions = [.isBordered, .hasDividers]
}

/// A grouped settings section. Source-compatible port of ice-2's `IceSection`:
/// `spacing`/`options` are accepted for call-site compatibility.
public struct DragonSection<Header: View, Content: View, Footer: View>: View {
    private let header: Header
    private let content: Content
    private let footer: Footer

    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.header = header()
        self.content = content()
        self.footer = footer()
    }

    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) where Header == EmptyView {
        self.init(spacing: spacing, options: options) { EmptyView() } content: { content() } footer: { footer() }
    }

    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(spacing: spacing, options: options) { header() } content: { content() } footer: { EmptyView() }
    }

    public init(
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder content: () -> Content
    ) where Header == EmptyView, Footer == EmptyView {
        self.init(spacing: spacing, options: options) { EmptyView() } content: { content() } footer: { EmptyView() }
    }

    public init(
        _ title: LocalizedStringKey,
        spacing: CGFloat = .dragonSectionDefaultSpacing,
        options: DragonSectionOptions = .default,
        @ViewBuilder content: () -> Content
    ) where Header == Text, Footer == EmptyView {
        self.init(spacing: spacing, options: options) { Text(title) } content: { content() }
    }

    public var body: some View {
        Section {
            content
        } header: {
            header
        } footer: {
            footer
        }
    }
}

public extension CGFloat {
    /// Default spacing for a ``DragonSection``.
    static let dragonSectionDefaultSpacing: CGFloat = 11
}
```

- [ ] **Step 3: Write the annotation port**

`Sources/DragonKit/DesignSystem/Annotation.swift`:

```swift
import SwiftUI

/// Displays content as an annotation below a parent view. Port of ice-2's `AnnotationView`.
public struct DragonAnnotationView<Parent: View, Content: View, FG: ShapeStyle>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat
    private let font: Font?
    private let foregroundStyle: FG
    private let parent: Parent
    private let content: Content

    public init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .dragonAnnotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: FG = .secondary,
        @ViewBuilder parent: () -> Parent,
        @ViewBuilder content: () -> Content
    ) {
        self.alignment = alignment
        self.spacing = spacing
        self.font = font
        self.foregroundStyle = foregroundStyle
        self.parent = parent()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing) {
            parent
            content
                .font(font)
                .foregroundStyle(foregroundStyle)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .fixedSize(horizontal: false, vertical: true)
    }
}

public extension View {
    /// Adds a view as an annotation below this view. Port of ice-2's `.annotation`.
    func dragonAnnotation<Content: View, FG: ShapeStyle>(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .dragonAnnotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: FG = .secondary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        DragonAnnotationView(
            alignment: alignment, spacing: spacing, font: font, foregroundStyle: foregroundStyle
        ) { self } content: { content() }
    }

    /// Adds text as an annotation below this view. Port of ice-2's `.annotation(_:)`.
    func dragonAnnotation<FG: ShapeStyle>(
        _ titleKey: LocalizedStringKey,
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat = .dragonAnnotationDefaultSpacing,
        font: Font? = .subheadline,
        foregroundStyle: FG = .secondary
    ) -> some View {
        dragonAnnotation(
            alignment: alignment, spacing: spacing, font: font, foregroundStyle: foregroundStyle
        ) { Text(titleKey) }
    }
}

public extension CGFloat {
    /// Default spacing for a ``DragonAnnotationView`` (ice-2 parity).
    static let dragonAnnotationDefaultSpacing: CGFloat = 2
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/DragonKit/DesignSystem
git commit -m "feat: DragonForm/DragonSection/.dragonAnnotation (source-compatible ice-2 ports)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: SettingsPane protocol + AnySettingsPane

**Files:**
- Create: `Sources/DragonKit/Settings/SettingsPane.swift`
- Test: `Tests/DragonKitTests/SettingsPaneTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/DragonKitTests/SettingsPaneTests.swift`:

```swift
import Testing
import SwiftUI
@testable import DragonKit

private struct FakePane: SettingsPane {
    let id: String
    let title: LocalizedStringKey
    let systemImage: String
    var paneBody: some View { Text(verbatim: id) }
}

@MainActor
@Suite struct SettingsPaneTests {
    @Test func anySettingsPanePreservesIdentity() {
        let pane = FakePane(id: "general", title: "General", systemImage: "gearshape")
        let erased = AnySettingsPane(pane)
        #expect(erased.id == "general")
        #expect(erased.systemImage == "gearshape")
    }

    @Test func arrayPreservesOrder() {
        let panes = [
            AnySettingsPane(FakePane(id: "a", title: "A", systemImage: "1.circle")),
            AnySettingsPane(FakePane(id: "b", title: "B", systemImage: "2.circle")),
        ]
        #expect(panes.map(\.id) == ["a", "b"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsPaneTests`
Expected: FAIL — `cannot find type 'SettingsPane'` / `'AnySettingsPane'`.

- [ ] **Step 3: Implement the protocol + eraser**

`Sources/DragonKit/Settings/SettingsPane.swift`:

```swift
import SwiftUI

/// A registrable settings pane. Modules (or apps) conform; the settings shell renders
/// them from an ordered array. Uses `paneBody` (not `body`) so a type can be both a
/// `SettingsPane` and a `View` without collision.
public protocol SettingsPane: Identifiable where ID == String {
    var id: String { get }
    var title: LocalizedStringKey { get }
    var systemImage: String { get }
    associatedtype PaneBody: View
    @MainActor @ViewBuilder var paneBody: PaneBody { get }
}

/// Type-erased pane for storage in a homogeneous array and the shell's sidebar.
public struct AnySettingsPane: Identifiable {
    public let id: String
    public let title: LocalizedStringKey
    public let systemImage: String
    let view: AnyView

    @MainActor
    public init<P: SettingsPane>(_ pane: P) {
        self.id = pane.id
        self.title = pane.title
        self.systemImage = pane.systemImage
        self.view = AnyView(pane.paneBody)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingsPaneTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DragonKit/Settings/SettingsPane.swift Tests/DragonKitTests/SettingsPaneTests.swift
git commit -m "feat: SettingsPane protocol + AnySettingsPane eraser

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: SettingsShell (host-owned selection) + ManagedSettingsShell

**Files:**
- Create: `Sources/DragonKit/Settings/SettingsShell.swift`

> `SettingsShell` takes a `Binding<String?>` so the host can persist the selected pane
> and open directly to a pane; `ManagedSettingsShell` is the self-managed convenience for
> the simple template. SwiftUI views — verified by `swift build`, exercised in Task 8.

- [ ] **Step 1: Write `SettingsShell` + `ManagedSettingsShell`**

`Sources/DragonKit/Settings/SettingsShell.swift`:

```swift
import SwiftUI

/// A `NavigationSplitView` settings window driven by an ordered list of panes — the
/// data-driven generalization of ice-2's `SettingsView`. The host owns `selection`, so it
/// can persist the choice (e.g. `@AppStorage`) and open directly to a specific pane.
public struct SettingsShell: View {
    private let appName: String
    private let panes: [AnySettingsPane]
    @Binding private var selection: String?

    public init(appName: String, panes: [AnySettingsPane], selection: Binding<String?>) {
        self.appName = appName
        self.panes = panes
        self._selection = selection
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(panes) { pane in
                        Label(pane.title, systemImage: pane.systemImage)
                            .tag(pane.id as String?)
                    }
                } header: {
                    Text(appName)
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .padding(.bottom, 8)
                }
                .collapsible(false)
            }
            .navigationSplitViewColumnWidth(220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            if let selection, let pane = panes.first(where: { $0.id == selection }) {
                pane.view
            } else {
                Text("Select a setting")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Convenience that owns its own selection `@State` and renders `SettingsShell` — for the
/// simple case (the basic template) where the host doesn't need to persist or redirect.
public struct ManagedSettingsShell: View {
    private let appName: String
    private let panes: [AnySettingsPane]
    @State private var selection: String?

    public init(appName: String, panes: [AnySettingsPane], initialSelection: String? = nil) {
        self.appName = appName
        self.panes = panes
        _selection = State(initialValue: initialSelection ?? panes.first?.id)
    }

    public var body: some View {
        SettingsShell(appName: appName, panes: panes, selection: $selection)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/DragonKit/Settings/SettingsShell.swift
git commit -m "feat: SettingsShell (host-owned selection) + ManagedSettingsShell

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: DragonSettingsWindowController (reliable accessory-app window)

**Files:**
- Create: `Sources/DragonKit/Settings/SettingsWindowController.swift`

> The genuinely hard, reusable part for `LSUIElement` apps: the SwiftUI `Settings` scene
> doesn't open cleanly for accessory apps (clipmenu-2 ships its own `SettingsWindowController`
> for this). AppKit — verified by `swift build`, exercised in Task 8.

- [ ] **Step 1: Write the controller**

`Sources/DragonKit/Settings/SettingsWindowController.swift`:

```swift
import AppKit
import SwiftUI

/// Opens the settings window reliably for `LSUIElement` (accessory) menu-bar apps. Owns
/// one resizable window with a content minimum size, created once and reused; flips the
/// app to `.regular` + activates on show, and back to `.accessory` when the window closes
/// (an accessory app otherwise can't make a window key).
@MainActor
public final class DragonSettingsWindowController: NSWindowController, NSWindowDelegate {
    public init(
        title: String,
        minSize: NSSize = NSSize(width: 720, height: 480),
        defaultSize: NSSize = NSSize(width: 800, height: 560),
        rootView: some View
    ) {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.contentMinSize = minSize
        window.setContentSize(defaultSize)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Bring settings to front. Accessory apps can't key a window, so temporarily become
    /// a regular app while the window is open.
    public func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/DragonKit/Settings/SettingsWindowController.swift
git commit -m "feat: DragonSettingsWindowController (reliable accessory-app settings window)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: About module (AboutContent + AboutPane + AboutSettingsPane)

**Files:**
- Create: `Sources/DragonKit/About/AboutContent.swift`
- Create: `Sources/DragonKit/About/AboutPane.swift`
- Test: `Tests/DragonKitTests/AboutContentTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/DragonKitTests/AboutContentTests.swift`:

```swift
import Testing
import Foundation
@testable import DragonKit

@Suite struct AboutContentTests {
    @Test func storesExplicitValues() {
        let content = AboutContent(
            appName: "Test App",
            versionString: "1.2.3 (45)",
            copyright: "© 2026 Someone"
        )
        #expect(content.appName == "Test App")
        #expect(content.versionString == "1.2.3 (45)")
        #expect(content.copyright == "© 2026 Someone")
    }

    @Test func defaultsAreEmptyOrNil() {
        let content = AboutContent(appName: "X", versionString: "1.0", copyright: "©")
        #expect(content.links.isEmpty)
        #expect(content.credits.isEmpty)
        #expect(content.acknowledgementsURL == nil)
    }

    @Test func linkStoresFields() {
        let url = URL(string: "https://example.com")!
        let link = AboutLink(title: "Website", detail: "example.com", systemImage: "globe", url: url)
        #expect(link.title == "Website")
        #expect(link.url == url)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AboutContentTests`
Expected: FAIL — `cannot find type 'AboutContent'` / `'AboutLink'`.

- [ ] **Step 3: Implement `AboutContent` + `AboutLink`**

`Sources/DragonKit/About/AboutContent.swift`:

```swift
import AppKit

/// A single labeled link shown in the About pane.
public struct AboutLink: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let detail: String
    public let systemImage: String
    public let url: URL

    public init(title: String, detail: String, systemImage: String, url: URL) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.url = url
    }
}

/// App-supplied content for the shared About pane.
public struct AboutContent {
    public let appName: String
    public let versionString: String
    public let copyright: String
    public let appIcon: NSImage?
    public let links: [AboutLink]
    public let credits: [(label: String, value: String)]
    public let acknowledgementsURL: URL?

    public init(
        appName: String,
        versionString: String,
        copyright: String,
        appIcon: NSImage? = NSImage(named: NSImage.applicationIconName),
        links: [AboutLink] = [],
        credits: [(label: String, value: String)] = [],
        acknowledgementsURL: URL? = nil
    ) {
        self.appName = appName
        self.versionString = versionString
        self.copyright = copyright
        self.appIcon = appIcon
        self.links = links
        self.credits = credits
        self.acknowledgementsURL = acknowledgementsURL
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AboutContentTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Write `AboutPane` + `AboutSettingsPane`**

`Sources/DragonKit/About/AboutPane.swift`:

```swift
import SwiftUI

/// The shared About view, reproducing ice-2's About pane: centered icon, name, version,
/// copyright; a links section; and a credits section.
public struct AboutPane: View {
    private let content: AboutContent

    public init(content: AboutContent) {
        self.content = content
    }

    public var body: some View {
        DragonForm {
            DragonSection {
                header
            }
            if !content.links.isEmpty || content.acknowledgementsURL != nil {
                DragonSection {
                    linkRows
                }
            }
            if !content.credits.isEmpty {
                DragonSection {
                    creditRows
                }
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 6) {
            if let icon = content.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            }
            Text(content.appName)
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(content.versionString)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(content.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var linkRows: some View {
        ForEach(content.links) { link in
            LabeledContent {
                Link(link.detail, destination: link.url)
            } label: {
                Label(link.title, systemImage: link.systemImage)
            }
        }
        if let ack = content.acknowledgementsURL {
            Button {
                NSWorkspace.shared.open(ack)
            } label: {
                Label("Acknowledgements", systemImage: "doc.text")
            }
        }
    }

    @ViewBuilder
    private var creditRows: some View {
        ForEach(content.credits, id: \.label) { credit in
            LabeledContent(credit.label) { Text(credit.value) }
        }
    }
}

/// Drop-in About pane for the settings shell.
public struct AboutSettingsPane: SettingsPane {
    public let id = "about"
    public let title: LocalizedStringKey = "About"
    public let systemImage = "info.circle"
    private let content: AboutContent

    public init(content: AboutContent) {
        self.content = content
    }

    public var paneBody: some View { AboutPane(content: content) }
}
```

- [ ] **Step 6: Build + test**

Run: `swift build && swift test`
Expected: `Build complete!` and all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/DragonKit/About Tests/DragonKitTests/AboutContentTests.swift
git commit -m "feat: About module (AboutContent, AboutPane, AboutSettingsPane)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Example menu-bar app (the basic template)

**Files:**
- Create: `Example/Package.swift`
- Create: `Example/Sources/DragonAppTemplate/App.swift`
- Create: `Example/Sources/DragonAppTemplate/AppDelegate.swift`
- Create: `Example/Sources/DragonAppTemplate/GeneralPane.swift`
- Create: `Example/Sources/DragonAppTemplate/AboutConfig.swift`
- Create: `Example/Resources/Info.plist`
- Create: `Example/scripts/run.sh`

> An SPM executable assembled into a `.app` by `run.sh` (mirrors clipmenu-2). Uses
> `DragonSettingsWindowController` + `ManagedSettingsShell` so the template stays tiny and
> the hard window logic lives in the kit. `@main` + `@MainActor static main()` keeps Swift 6
> concurrency happy (no `main.swift`). Verified by building, then launching manually.

- [ ] **Step 1: Write `Example/Package.swift`**

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DragonAppTemplate",
    platforms: [.macOS("26")],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "DragonAppTemplate",
            dependencies: [.product(name: "DragonKit", package: "dragon-kit")]
        ),
    ]
)
```

> Note: the parent package directory is `dragon-kit`, so `package:` is `"dragon-kit"`. If
> `swift build` reports a different expected package identifier, use the name SwiftPM prints.

- [ ] **Step 2: Write the `@main` entry**

`Example/Sources/DragonAppTemplate/App.swift`:

```swift
import AppKit

@main
struct DragonAppTemplate {
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

- [ ] **Step 3: Write the app delegate**

`Example/Sources/DragonAppTemplate/AppDelegate.swift`:

```swift
import AppKit
import SwiftUI
import DragonKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    private lazy var settingsController = DragonSettingsWindowController(
        title: "Dragon App Settings",
        rootView: ManagedSettingsShell(
            appName: "Dragon App",
            panes: [
                AnySettingsPane(GeneralPane()),
                AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),
            ]
        )
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Dragon App")

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

- [ ] **Step 4: Write the placeholder General pane**

`Example/Sources/DragonAppTemplate/GeneralPane.swift`:

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
                    .dragonAnnotation("Placeholder — wire this up in a real app.")
            }
        }
    }
}
```

- [ ] **Step 5: Write the About config**

`Example/Sources/DragonAppTemplate/AboutConfig.swift`:

```swift
import Foundation
import DragonKit

enum AboutConfig {
    static var content: AboutContent {
        AboutContent(
            appName: "Dragon App",
            versionString: "0.1.0",
            copyright: "© 2026 Teddy Chan",
            links: [
                AboutLink(
                    title: "Website",
                    detail: "dragonapp.com",
                    systemImage: "globe",
                    url: URL(string: "https://www.dragonapp.com")!
                ),
                AboutLink(
                    title: "Source",
                    detail: "teddychan/dragon-kit",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: URL(string: "https://github.com/teddychan/dragon-kit")!
                ),
            ],
            credits: [
                (label: "Built with", value: "DragonKit"),
                (label: "License", value: "MIT"),
            ]
        )
    }
}
```

- [ ] **Step 6: Write `Example/Resources/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>Dragon App</string>
	<key>CFBundleDisplayName</key>
	<string>Dragon App</string>
	<key>CFBundleIdentifier</key>
	<string>com.dragonapp.template</string>
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

- [ ] **Step 7: Write the run script**

`Example/scripts/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Dragon App"
BIN_NAME="DragonAppTemplate"

swift build -c debug
BIN_DIR="$(swift build -c debug --show-bin-path)"

APP="$BIN_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $BIN_NAME" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $BIN_NAME" "$APP/Contents/Info.plist"
# Copy SwiftPM resource bundles (DragonKit strings) next to the binary.
cp -R "$BIN_DIR"/*.bundle "$APP/Contents/MacOS/" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

pkill -f "$APP/Contents/MacOS/$BIN_NAME" 2>/dev/null || true
sleep 1
open "$APP"
echo "Launched $APP"
```

Make it executable:

```bash
chmod +x Example/scripts/run.sh
```

- [ ] **Step 8: Build the example executable**

Run: `cd ~/git/dragon-kit/Example && swift build`
Expected: `Build complete!` (DragonKit resolves via the local path dependency).
If the product line errors, run `swift build` once to read the resolved package name SwiftPM expects and update `package:` in `Example/Package.swift`, then rebuild.

- [ ] **Step 9: Launch and verify manually**

Run: `cd ~/git/dragon-kit/Example && ./scripts/run.sh`
Expected: a status-bar ✦ icon appears (no Dock icon). Click it → **Settings…** opens a
resizable window with a sidebar (General, About). **About** shows icon/name/version/links/
credits like ice-2. Closing the window returns the app to accessory (no Dock icon).
**Quit** terminates the app.

- [ ] **Step 10: Commit**

```bash
cd ~/git/dragon-kit
git add Example
git commit -m "feat: Example menu-bar app template (window controller + shell + About)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: OSS scaffolding (LICENSE, README, CI)

**Files:**
- Create: `LICENSE`
- Create: `README.md`
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write `LICENSE` (MIT)**

```
MIT License

Copyright (c) 2026 Teddy Chan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: Write `README.md`**

````markdown
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
````

- [ ] **Step 3: Write CI**

`.github/workflows/ci.yml`:

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Build & test DragonKit
        run: swift test
      - name: Build Example app
        run: cd Example && swift build
```

- [ ] **Step 4: Verify the whole package once more**

Run: `cd ~/git/dragon-kit && swift test && (cd Example && swift build)`
Expected: all tests pass; Example builds.

- [ ] **Step 5: Commit**

```bash
git add LICENSE README.md .github
git commit -m "chore: MIT license, README, CI (macos-26)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Publish (only after v0 is green) — requires user confirmation

> Outward-facing. Do this only once Tasks 1–9 are green and the Example app runs, and only
> after confirming with the owner.

- [ ] **Step 1: Confirm with the owner** that v0 builds green and they want it public.

- [ ] **Step 2: Create the public repo and push**

```bash
cd ~/git/dragon-kit
gh repo create teddychan/dragon-kit --public --source=. --remote=origin \
  --description "Shared SwiftUI foundations for Dragon App macOS menu-bar apps"
git branch -M main
git push -u origin main
```

- [ ] **Step 3: Verify**

Run: `gh repo view teddychan/dragon-kit --web` (or check the Actions tab).
Expected: repo exists; CI runs green.

---

## Post-plan addition — Task 11: What's New module
Added after review at the owner's request ("we should have a section called 'What's New' …
add it as the basic info"). `DragonKit/WhatsNew/` — `WhatsNewContent` + `ChangeSection`
(`Kind`: added/changed/fixed/removed/improved/security, with uppercased `label` +
per-kind `systemImage`) + `WhatsNewPane` + `WhatsNewSettingsPane`. TDD: 4 tests
(`WhatsNewContentTests`) for label/symbol/storage/defaults; library now 12 tests. Wired
into the Example as a third pane (`WhatsNewConfig`). String `DragonKit.whatsNew.title`.

## Self-review notes
- **Spec coverage:** primitives as source-compatible ports (T3), SettingsPane (T4),
  host-owned shell + managed convenience (T5), reusable accessory window controller (T6),
  About (T7), localization (T2), Example template w/ window controller + About + General +
  Quit (T8), MIT+README+CI (T9), publish-after-green (T10), macOS 26 + SPM app (T1, T8).
  All §2 in-scope items covered; §2 out-of-scope (Backup/Updates/Uninstall, scaffolding,
  app migration, KeyKey) intentionally excluded. Review items #1 (T3), #2 (T5), #3 (T6,T8),
  #4 (spec §5), #5 (spec §8) addressed.
- **Type consistency:** `SettingsPane.paneBody` / `AnySettingsPane(_:)` used identically in
  T4–T8. `SettingsShell(...selection:)` / `ManagedSettingsShell(...initialSelection:)`
  consistent between T5 and T8. `DragonSettingsWindowController(title:rootView:)` matches
  between T6 and T8. `AboutContent`/`AboutLink`/`AboutSettingsPane` match T7↔T8.
- **Known risks:** (1) `Example/Package.swift` `package:` identifier (`dragon-kit`) — T8
  Step 8 has a fallback. (2) `List` optional-selection: rows use `.tag(pane.id as String?)`
  to match `Binding<String?>`; if selection still doesn't update, verify the tag type in T8
  Step 9. (3) SwiftUI module-bundle string localization deferred to the Localization module
  spec; v0 visible strings localize via the app bundle (`LocalizedStringKey`); `L()` covers
  module lookups. (4) macOS 26 / Swift 6.1 toolchain assumed present (Darwin 25 = macOS 26).
```
