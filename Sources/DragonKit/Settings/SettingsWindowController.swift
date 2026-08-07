import AppKit
import SwiftUI

/// Opens the settings window reliably for `LSUIElement` (accessory) menu-bar apps. Owns
/// one resizable window with a content minimum size, created once and reused; flips the
/// app to `.regular` + activates on show, and back to `.accessory` when the window closes
/// (an accessory app otherwise can't make a window key).
///
/// Becoming `.regular` also puts a menu bar on screen — and nothing in the kit or in any of
/// the five apps ever assigned `NSApp.mainMenu` (no Dragon app has a `MainMenu.xib`), so
/// settings opened under a completely **empty** menu bar: no ⌘W, no ⌘Q, and no
/// Undo/Cut/Copy/Paste/Select All in any settings text field, because those verbs reach the
/// focused view from menu items travelling the responder chain, not from the text system.
/// ``makeSettingsMainMenu(appName:includeQuit:)`` supplies the minimum standard menu and ``show()``
/// installs it for as long as the window is open. Found by the macOS engineering-standard
/// audit of the kit; fixing it here fixes it for every Dragon app at once.
@MainActor
public final class DragonSettingsWindowController: NSWindowController, NSWindowDelegate {
    private let installsMainMenu: Bool
    private let includeQuit: Bool

    /// Whether *this* controller is what put the current `NSApp.mainMenu` there. Tracked as a
    /// stored flag rather than re-derived at close time, because a non-nil menu then says
    /// nothing about who owns it — and tearing down an app's own menu would leave it without
    /// one for the rest of the session.
    private var installedMainMenu = false

    /// - Parameter installsMainMenu: Install the standard settings menu bar while the window
    ///   is open (default `true`). Pass `false` from an app that wants no menu bar at all here.
    ///   An app that already owns `NSApp.mainMenu` keeps it either way — ``show()`` only ever
    ///   fills a `nil` one. Defaulted and placed ahead of `rootView` so the existing
    ///   `init(title:rootView:)` and `init(title:minSize:defaultSize:rootView:)` call sites in
    ///   the five apps keep compiling untouched.
    /// - Parameter includeQuit: Include Quit ⌘Q in that menu bar (default `true`). Pass `false`
    ///   from a system-managed input method, which is quit by the system and not by the user —
    ///   the same reason, and the same spelling, as ``DragonAppMenu/Config/includeQuit``.
    ///   yahoo-keykey-2 already passes it there and had no way to say it here, so v2.3.0 would
    ///   have given its Settings window a Quit its own dropdown deliberately omits. The Edit and
    ///   Window menus are unaffected, which is the point: an IME's settings still need
    ///   Cut/Copy/Paste and ⌘W, and those only ever arrive via menu items.
    public init(
        title: String,
        minSize: NSSize = NSSize(width: 720, height: 480),
        defaultSize: NSSize = NSSize(width: 800, height: 560),
        installsMainMenu: Bool = true,
        includeQuit: Bool = true,
        rootView: some View
    ) {
        self.installsMainMenu = installsMainMenu
        self.includeQuit = includeQuit
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
        // Only ever fill a *nil* menu. An app that ships its own main menu (from a
        // `MainMenu.xib`, or installed at launch) must keep it — overwriting it would
        // silently delete every app-specific command while settings happened to be open.
        if installsMainMenu, NSApp.mainMenu == nil {
            NSApp.mainMenu = Self.makeSettingsMainMenu(
                appName: Self.hostAppName(),
                includeQuit: includeQuit
            )
            installedMainMenu = true
        }
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Restore what was there before, which — because we only install into a nil menu — is
        // nil. Cleared *after* the policy change, so the app is already an accessory and the
        // teardown can't flash an empty menu bar.
        if installedMainMenu {
            NSApp.mainMenu = nil
            installedMainMenu = false
        }
    }

    /// The minimum standard macOS menu bar for a settings window:
    ///
    /// ```
    /// <App>    Quit <App>   ⌘Q
    /// Edit     Undo ⌘Z · Redo ⇧⌘Z · Cut ⌘X · Copy ⌘C · Paste ⌘V · Select All ⌘A
    /// Window   Close ⌘W · Minimize ⌘M
    /// ```
    ///
    /// Edit is not decoration: a settings pane with a text field gets the pasteboard verbs
    /// *only* from these items. The first submenu is the app menu; macOS renders its title
    /// from the running process no matter what is set here, so only its contents matter.
    ///
    /// Deliberately pure — it takes the app name and touches no `NSApp` state — because a real
    /// menu bar can't be asserted in a unit test but this structure can (`SettingsMainMenuTests`).
    static func makeSettingsMainMenu(appName: String, includeQuit: Bool = true) -> NSMenu {
        let mainMenu = NSMenu()

        // macOS renders whichever menu comes first as the application menu, so one always has to
        // exist — which is why Quit being optional doesn't mean the app menu is. Hide / Hide
        // Others / Show All are the conventional contents, need no app-specific knowledge, and
        // keep the menu from rendering as an empty dropdown under the app's name when an IME
        // omits Quit.
        let appMenu = NSMenu(title: appName)
        appMenu.addItem(menuItem(
            title: String(format: L("DragonKit.mainMenu.hide"), appName),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        ))
        appMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.hideOthers"),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option]
        ))
        appMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.showAll"),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        ))
        // `includeQuit: false` is for a system-managed input method, which is quit by the system
        // and not by the user — the same reason, and the same spelling, as
        // ``DragonAppMenu/Config/includeQuit``. yahoo-keykey-2 already passes it there and had no
        // way to say it here, so adopting v2.3.0 would have handed its Settings window a Quit ⌘Q
        // that its dropdown deliberately omits. Reuses `DragonKit.menu.quit` ("Quit %@") so the
        // dropdown and the menu bar can't drift into different wording.
        if includeQuit {
            appMenu.addItem(.separator())
            appMenu.addItem(menuItem(
                title: String(format: L("DragonKit.menu.quit"), appName),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            ))
        }
        mainMenu.addItem(submenuItem(title: appName, submenu: appMenu))

        let editMenu = NSMenu(title: L("DragonKit.mainMenu.edit"))
        // `undo:`/`redo:` are informal responder-chain methods with no `#selector`-able
        // declaration; NSUndoManager supplies them to whatever view is first responder.
        editMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.undo"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        ))
        editMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.redo"),
            action: Selector(("redo:")),
            // ⇧ belongs in the modifier mask; a capital "Z" as the key equivalent would make
            // macOS draw the shortcut but match the event inconsistently.
            keyEquivalent: "z",
            modifiers: [.command, .shift]
        ))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.cut"),
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        ))
        editMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.copy"),
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        ))
        editMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.paste"),
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        ))
        editMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.selectAll"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))
        mainMenu.addItem(submenuItem(title: L("DragonKit.mainMenu.edit"), submenu: editMenu))

        let windowMenu = NSMenu(title: L("DragonKit.mainMenu.window"))
        windowMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.close"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        windowMenu.addItem(menuItem(
            title: L("DragonKit.mainMenu.minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        mainMenu.addItem(submenuItem(title: L("DragonKit.mainMenu.window"), submenu: windowMenu))

        return mainMenu
    }

    /// One item with **no target** — which is the entire mechanism. A nil-target item is
    /// offered to the responder chain, so ⌘W closes whichever window is key and Cut/Copy/Paste
    /// land on the focused text view. Setting a target here (to the controller, say) would
    /// point every shortcut at one object and silently break both; `SettingsMainMenuTests`
    /// asserts the nil for exactly that reason.
    private static func menuItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    /// A submenu reaches the menu bar only through a parent item that owns it — an `NSMenu`
    /// added to the main menu directly never appears. The `nil` action here is nominal: AppKit
    /// repoints the item at its own menu (`submenuAction:`) as soon as `submenu` is set, which
    /// is why the nil-target rule above applies to leaf items only.
    private static func submenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    /// The host app's display name, in the same order ``DragonUpdater`` reads it for its
    /// "up to date" alert, so Quit and that alert can't disagree. Read from `Info.plist`
    /// rather than taken as an init parameter: adding a required parameter would break all
    /// five apps' call sites, and hardcoding a name is never allowed.
    private static func hostAppName() -> String {
        let bundle = Bundle.main
        return bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }
}
