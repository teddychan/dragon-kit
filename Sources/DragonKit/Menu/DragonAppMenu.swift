import AppKit

/// The canonical menu-bar dropdown for every Dragon app — built once, here, so the apps
/// can't drift apart the way hand-rolled `NSMenu`s did.
///
/// Canonical order, naming, and leading SF Symbol (macOS title-case, ellipsis on items that
/// open a window/dialog, app name appended to About / Quit):
///
/// ```
/// info.circle        About <App>
/// arrow.down.circle  Check for Updates…   (omitted when `onCheckForUpdates` is nil — e.g. Mac App Store)
/// gearshape          Settings…       ⌘,
/// ──────────
/// power              Quit <App>      ⌘Q   (omitted when `includeQuit` is false — e.g. an IME)
/// ```
///
/// **Uninstall is deliberately absent.** It lives in Settings, as `UninstallSettingsPane` —
/// a rarely-used destructive action does not belong one click away in the everyday dropdown,
/// next to Quit. Every app ships that pane in its Settings sidebar, so the flow is still one
/// click from Settings…; the menu just stops advertising it.
///
/// The symbols are fixed here rather than injected: the design spec is "lead every item with
/// an SF Symbol … only the name string differs", so the icon is part of the canon, not per-app
/// config. `arrow.down.circle` matches ``UpdatesSettingsPane``'s sidebar symbol.
///
/// Apps whose dropdown is *only* these items use ``menu(_:)``. Apps with their own
/// content above (a clipboard history, input-method toggles, …) build their menu and then
/// append ``items(_:)`` after their own leading separator.
@MainActor
public enum DragonAppMenu {
    public struct Config {
        /// Display name substituted into About / Quit (e.g. "ClipMenu 2").
        public var appName: String
        public var onAbout: () -> Void
        public var onSettings: () -> Void
        /// `nil` omits the item — for builds without Sparkle (Mac App Store).
        public var onCheckForUpdates: (() -> Void)?
        /// `false` omits Quit — an IME is quit by the system, not the user.
        public var includeQuit: Bool

        public init(
            appName: String,
            onAbout: @escaping () -> Void,
            onSettings: @escaping () -> Void,
            onCheckForUpdates: (() -> Void)? = nil,
            includeQuit: Bool = true
        ) {
            self.appName = appName
            self.onAbout = onAbout
            self.onSettings = onSettings
            self.onCheckForUpdates = onCheckForUpdates
            self.includeQuit = includeQuit
        }
    }

    /// The standard app items in canonical order, ready to append to an existing `NSMenu`.
    /// Does **not** include a leading separator — a caller appending these after its own
    /// content adds that itself (so a full standalone menu has no dangling divider on top).
    public static func items(_ config: Config) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        items.append(ClosureMenuItem(
            title: String(format: L("DragonKit.menu.about"), config.appName),
            symbolName: "info.circle",
            handler: config.onAbout
        ))
        if let onCheckForUpdates = config.onCheckForUpdates {
            items.append(ClosureMenuItem(
                title: L("DragonKit.menu.checkForUpdates"),
                symbolName: "arrow.down.circle",
                handler: onCheckForUpdates
            ))
        }
        items.append(ClosureMenuItem(
            title: L("DragonKit.menu.settings"),
            symbolName: "gearshape",
            keyEquivalent: ",",
            handler: config.onSettings
        ))

        // Quit is the only item after the divider, so both are omitted together — an IME's
        // menu must not end on a dangling separator.
        if config.includeQuit {
            items.append(.separator())
            let quit = NSMenuItem(
                title: String(format: L("DragonKit.menu.quit"), config.appName),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
            quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
            items.append(quit)
        }
        return items
    }

    /// A complete standalone `NSMenu` containing only the standard app items.
    public static func menu(_ config: Config) -> NSMenu {
        let menu = NSMenu()
        for item in items(config) { menu.addItem(item) }
        return menu
    }
}

/// An `NSMenuItem` that runs a closure when selected, so callers pass behavior directly
/// instead of wiring `target`/`action` and retaining a separate handler object.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, symbolName: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        self.target = self
        self.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func invoke() { handler() }
}
