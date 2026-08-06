import Testing
import AppKit
@testable import DragonKit

/// Guards the menu bar `DragonSettingsWindowController` installs while settings is open.
///
/// The controller flips an accessory app to `.regular`, which shows a menu bar — and until the
/// engineering-standard audit found it, that menu bar was empty in every Dragon app, so settings
/// had no ⌘W, no ⌘Q, and no working Cut/Copy/Paste/Undo in any text field. These tests drive
/// `makeSettingsMainMenu(appName:)` directly: a real menu bar can't be asserted from a unit test,
/// which is exactly why the builder is pure. No windows are created and `show()` is never called.
@MainActor
@Suite struct SettingsMainMenuTests {
    private let appName = "Test App"

    private var menu: NSMenu { DragonSettingsWindowController.makeSettingsMainMenu(appName: appName) }

    private var appMenu: NSMenu? { menu.items.first?.submenu }
    private var editMenu: NSMenu? { menu.items[safe: 1]?.submenu }
    private var windowMenu: NSMenu? { menu.items[safe: 2]?.submenu }

    /// Menu *titles* are localized (and `L()` falls back to the raw key when a translation is
    /// missing), so identity is asserted by action — which is the part behavior depends on.
    private func item(_ menu: NSMenu?, action: Selector) -> NSMenuItem? {
        menu?.items.first { $0.action == action }
    }

    @Test func theThreeTopLevelMenusAreAppEditWindowInOrder() {
        let mainMenu = menu
        #expect(mainMenu.items.count == 3)
        // Every top-level entry must own a submenu: an `NSMenu` without a parent `NSMenuItem`
        // never reaches the menu bar at all.
        #expect(mainMenu.items.allSatisfy { $0.submenu != nil })
        #expect(item(appMenu, action: #selector(NSApplication.terminate(_:))) != nil)
        #expect(item(editMenu, action: #selector(NSText.cut(_:))) != nil)
        #expect(item(windowMenu, action: #selector(NSWindow.performClose(_:))) != nil)
    }

    /// The two shortcuts a settings window is unusable without: ⌘W to dismiss it and ⌘Q to quit.
    @Test func closeIsCommandWAndQuitIsCommandQ() {
        let close = item(windowMenu, action: #selector(NSWindow.performClose(_:)))
        #expect(close?.keyEquivalent == "w")
        #expect(close?.keyEquivalentModifierMask == .command)

        let quit = item(appMenu, action: #selector(NSApplication.terminate(_:)))
        #expect(quit?.keyEquivalent == "q")
        #expect(quit?.keyEquivalentModifierMask == .command)

        let minimize = item(windowMenu, action: #selector(NSWindow.performMiniaturize(_:)))
        #expect(minimize?.keyEquivalent == "m")
    }

    /// A settings pane's text fields get the pasteboard verbs from these items and nowhere else,
    /// so each one has to carry its standard shortcut — and they have to be in the order macOS
    /// users expect, with the separator between the undo pair and the pasteboard group.
    @Test func everyEditItemCarriesItsStandardKeyEquivalent() {
        let expected: [(Selector, String)] = [
            (Selector(("undo:")), "z"),
            (Selector(("redo:")), "z"),
            (#selector(NSText.cut(_:)), "x"),
            (#selector(NSText.copy(_:)), "c"),
            (#selector(NSText.paste(_:)), "v"),
            (#selector(NSText.selectAll(_:)), "a"),
        ]
        for (action, key) in expected {
            #expect(item(editMenu, action: action)?.keyEquivalent == key, "\(action) is not ⌘\(key)")
        }

        let expectedOrder: [Selector?] = [
            Selector(("undo:")),
            Selector(("redo:")),
            nil, // the separator between the undo pair and the pasteboard group
            #selector(NSText.cut(_:)),
            #selector(NSText.copy(_:)),
            #selector(NSText.paste(_:)),
            #selector(NSText.selectAll(_:)),
        ]
        #expect(editMenu?.items.map(\.action) == expectedOrder)
        #expect(editMenu?.items[2].isSeparatorItem == true)
    }

    /// ⇧ travels in the modifier mask. Spelling Redo as a capital `"Z"` key equivalent instead is
    /// the classic version of this bug: macOS still *draws* ⇧⌘Z but matches the event differently.
    @Test func redoCarriesShiftInTheModifierMaskNotTheKeyEquivalent() {
        let redo = item(editMenu, action: Selector(("redo:")))
        #expect(redo?.keyEquivalent == "z")
        #expect(redo?.keyEquivalentModifierMask == [.command, .shift])
        // Undo is the control: same key, no shift.
        #expect(item(editMenu, action: Selector(("undo:")))?.keyEquivalentModifierMask == .command)
    }

    /// **The responder-chain guarantee.** A nil target is what makes ⌘W close whichever window is
    /// key and Cut/Copy/Paste reach the focused text view — AppKit only walks the responder chain
    /// for items that have no target. Giving these items a target (the window controller, say)
    /// compiles fine, looks tidier, and breaks every one of these shortcuts silently. Do not.
    ///
    /// The three top-level items are excluded because they aren't actionable: AppKit points a
    /// submenu parent at its own menu (`submenuAction:`) the moment `submenu` is set, so their
    /// targets are never ours to control.
    @Test func everyActionableItemHasANilTargetSoItTravelsTheResponderChain() {
        let actionable = menu.items
            .flatMap { [$0] + ($0.submenu?.items ?? []) }
            .filter { !$0.isSeparatorItem && $0.submenu == nil }
        #expect(actionable.count == 9) // Quit + 6 Edit + 2 Window — nothing silently skipped
        for item in actionable {
            #expect(item.target == nil, "\(item.title) has a target and will not reach the responder chain")
        }
    }

    /// The app name comes from the host's `Info.plist` at call time — never hardcoded — and is
    /// formatted through the existing `DragonKit.menu.quit` ("Quit %@") that the dropdown uses.
    @Test func theQuitItemTitleIncludesTheAppName() {
        let quit = item(appMenu, action: #selector(NSApplication.terminate(_:)))
        #expect(quit?.title.contains(appName) == true)
        #expect(menu.items.first?.title == appName)
    }
}

private extension Array {
    /// Index-or-nil, so a structural regression fails one clear expectation instead of trapping
    /// the whole test run.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
