import Testing
import AppKit
@testable import DragonKit

@MainActor
@Suite struct DragonAppMenuTests {
    private func config(
        onCheckForUpdates: (() -> Void)? = {},
        onUninstall: (() -> Void)? = {},
        includeQuit: Bool = true
    ) -> DragonAppMenu.Config {
        DragonAppMenu.Config(
            appName: "Test App",
            onAbout: {},
            onSettings: {},
            onCheckForUpdates: onCheckForUpdates,
            onUninstall: onUninstall,
            includeQuit: includeQuit
        )
    }

    @Test func fullMenuIsInCanonicalOrder() {
        let titles = DragonAppMenu.items(config()).map(\.title)
        #expect(titles == [
            "About Test App",
            "Check for Updates…",
            "Settings…",
            "", // separator
            "Uninstall Test App…",
            "Quit Test App",
        ])
    }

    /// §5A: "lead every item with an SF Symbol" — a missing symbol is the drift this guards.
    @Test func everyItemLeadsWithASymbol() {
        for item in DragonAppMenu.items(config()) where !item.isSeparatorItem {
            #expect(item.image != nil, "\(item.title) has no SF Symbol")
        }
    }

    @Test func settingsAndQuitCarryTheStandardKeyEquivalents() {
        let items = DragonAppMenu.items(config())
        #expect(items.first { $0.title == "Settings…" }?.keyEquivalent == ",")
        #expect(items.first { $0.title == "Quit Test App" }?.keyEquivalent == "q")
    }

    /// A Mac App Store build passes `onCheckForUpdates: nil` — the App Store does the updating.
    @Test func nilCheckForUpdatesOmitsTheItem() {
        let titles = DragonAppMenu.items(config(onCheckForUpdates: nil)).map(\.title)
        #expect(!titles.contains("Check for Updates…"))
    }

    /// An IME is quit by the system, so it passes `includeQuit: false`.
    @Test func anImeMenuHasNoQuitAndNoDanglingSeparator() {
        let items = DragonAppMenu.items(config(onUninstall: nil, includeQuit: false))
        #expect(items.map(\.title) == ["About Test App", "Check for Updates…", "Settings…"])
        #expect(!items.contains { $0.isSeparatorItem })
    }

    /// `menu(_:)` is the standalone case — it must not open with a dangling divider.
    @Test func standaloneMenuDoesNotStartWithASeparator() {
        let menu = DragonAppMenu.menu(config())
        #expect(menu.items.first?.isSeparatorItem == false)
        #expect(menu.items.count == DragonAppMenu.items(config()).count)
    }
}
