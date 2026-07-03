import AppKit
import SwiftUI
import DragonKit
import DragonKitUpdates

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appName = "DragonKit Sample"
    private var bundleID: String { Bundle.main.bundleIdentifier ?? "com.dragonapp.dragonkit-sample" }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private let model = SettingsModel()
    private let updater = DragonUpdater()
    private var statusItem: NSStatusItem?

    private lazy var settingsController = DragonSettingsWindowController(
        title: "\(appName) Settings",
        rootView: ManagedSettingsShell(
            appName: appName,
            panes: [
                AnySettingsPane(GeneralPane(model: model)),
                AnySettingsPane(BackupSettingsPane(config: backupConfig)),
                AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),
                AnySettingsPane(WhatsNewSettingsPane(content: WhatsNewConfig.content)),
                AnySettingsPane(UpdatesSettingsPane(updater: updater)),
                AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),
                AnySettingsPane(UninstallSettingsPane(config: uninstallConfig)),
            ]
        )
    )

    private var backupConfig: BackupConfig {
        BackupConfig(
            appName: appName,
            suiteName: SettingsModel.suiteName,
            appVersion: appVersion,
            relaunch: { [weak self] in self?.relaunch() }
        )
    }

    private var uninstallConfig: UninstallConfig {
        UninstallConfig(
            appName: appName,
            bundleID: bundleID,
            suiteNames: [SettingsModel.suiteName],
            checklistItems: [
                "The app and its login item",
                "All settings",
                "Saved application state",
            ]
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A plain "D" marks this as the DragonKit sample app in the menu bar.
        if let button = item.button {
            button.title = "D"
            button.font = .systemFont(ofSize: 15, weight: .heavy)
        }

        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let checkUpdates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdates.target = self
        menu.addItem(checkUpdates)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        item.isVisible = model.showInMenuBar
        self.statusItem = item

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showInMenuBarChanged(_:)),
            name: .sampleShowInMenuBarChanged,
            object: nil
        )

        // Never trap the user: if the icon is hidden at launch, open Settings so they can
        // toggle it back on.
        if !model.showInMenuBar {
            settingsController.show()
        }
    }

    @objc private func openSettings() {
        settingsController.show()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
    }

    @objc private func showInMenuBarChanged(_ note: Notification) {
        statusItem?.isVisible = (note.object as? Bool) ?? true
    }

    private func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
