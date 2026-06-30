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
                AnySettingsPane(WhatsNewSettingsPane(content: WhatsNewConfig.content)),
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
