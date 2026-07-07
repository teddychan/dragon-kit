import AppKit

/// The canonical menu-bar dropdown for every Dragon app — built once, here, so the apps
/// can't drift apart the way hand-rolled `NSMenu`s did.
///
/// Canonical order and naming (macOS title-case, ellipsis on items that open a window/dialog,
/// app name appended to About / Uninstall / Quit):
///
/// ```
/// About <App>
/// Check for Updates…        (omitted when `onCheckForUpdates` is nil — e.g. Mac App Store)
/// Settings…            ⌘,
/// ──────────
/// Uninstall <App>…          (omitted when `onUninstall` is nil)
/// Quit <App>           ⌘Q   (omitted when `includeQuit` is false — e.g. an IME)
/// ```
///
/// Apps whose dropdown is *only* these items use ``menu(_:)``. Apps with their own
/// content above (a clipboard history, input-method toggles, …) build their menu and then
/// append ``items(_:)`` after their own leading separator.
@MainActor
public enum DragonAppMenu {
    public struct Config {
        /// Display name substituted into About / Uninstall / Quit (e.g. "ClipMenu 2").
        public var appName: String
        public var onAbout: () -> Void
        public var onSettings: () -> Void
        /// `nil` omits the item — for builds without Sparkle (Mac App Store).
        public var onCheckForUpdates: (() -> Void)?
        /// `nil` omits the item — for apps that don't ship an uninstall flow.
        public var onUninstall: (() -> Void)?
        /// `false` omits Quit — an IME is quit by the system, not the user.
        public var includeQuit: Bool

        public init(
            appName: String,
            onAbout: @escaping () -> Void,
            onSettings: @escaping () -> Void,
            onCheckForUpdates: (() -> Void)? = nil,
            onUninstall: (() -> Void)? = nil,
            includeQuit: Bool = true
        ) {
            self.appName = appName
            self.onAbout = onAbout
            self.onSettings = onSettings
            self.onCheckForUpdates = onCheckForUpdates
            self.onUninstall = onUninstall
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
            handler: config.onAbout
        ))
        if let onCheckForUpdates = config.onCheckForUpdates {
            items.append(ClosureMenuItem(
                title: L("DragonKit.menu.checkForUpdates"),
                handler: onCheckForUpdates
            ))
        }
        items.append(ClosureMenuItem(
            title: L("DragonKit.menu.settings"),
            keyEquivalent: ",",
            handler: config.onSettings
        ))

        // Divider before the destructive / terminal group.
        let hasTrailingGroup = config.onUninstall != nil || config.includeQuit
        if hasTrailingGroup {
            items.append(.separator())
        }
        if let onUninstall = config.onUninstall {
            items.append(ClosureMenuItem(
                title: String(format: L("DragonKit.menu.uninstall"), config.appName),
                handler: onUninstall
            ))
        }
        if config.includeQuit {
            let quit = NSMenuItem(
                title: String(format: L("DragonKit.menu.quit"), config.appName),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
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

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        self.target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func invoke() { handler() }
}
