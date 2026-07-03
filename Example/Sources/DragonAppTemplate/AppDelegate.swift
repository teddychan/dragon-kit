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

    // Host-owned selection: the AppDelegate can set the pane before showing the window (so
    // the menu-bar "About" item lands on the About pane), which is why this uses
    // `SettingsShell` rather than self-owned `ManagedSettingsShell`.
    private let selection = SampleSettingsSelection()

    private lazy var settingsController: DragonSettingsWindowController = {
        let panes = settingsPanes
        if selection.paneID == nil { selection.paneID = panes.first?.id }
        return DragonSettingsWindowController(
            title: "\(appName) Settings",
            rootView: SampleSettingsRoot(appName: appName, panes: panes, selection: selection)
        )
    }()

    private var settingsPanes: [AnySettingsPane] {
        [
            AnySettingsPane(GeneralPane(model: model)),
            AnySettingsPane(BackupSettingsPane(config: backupConfig)),
            AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),
            AnySettingsPane(WhatsNewSettingsPane(content: WhatsNewConfig.content)),
            AnySettingsPane(UpdatesSettingsPane(updater: updater)),
            AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),
            AnySettingsPane(UninstallSettingsPane(config: uninstallConfig, onCancel: { [selection] in
                selection.paneID = "general"
            })),
        ]
    }

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
        let settings = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let checkUpdates = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdates.target = self
        menu.addItem(checkUpdates)
        let about = NSMenuItem(title: "About", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
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
        // Open the Updates pane for context (so the "Last checked" time updates in view), then
        // run the check. The result itself is shown by Sparkle's own standard UI.
        selection.paneID = "updates"
        settingsController.show()
        updater.checkForUpdates()
    }

    @objc private func openAbout() {
        // Set the pane before showing so it always lands on About (matches
        // `AboutSettingsPane().id`), even on the first, lazy open of the window.
        selection.paneID = "about"
        settingsController.show()
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

/// Host-owned settings selection. The AppDelegate sets `paneID` before showing the window,
/// so the menu can open directly to a specific pane (e.g. About) — including on first open.
@MainActor
@Observable
final class SampleSettingsSelection {
    var paneID: String?
}

/// Settings root wired to the host's ``SampleSettingsSelection``. Uses ``SettingsShell``
/// (host-owned selection) rather than ``ManagedSettingsShell`` (self-owned) for exactly this
/// reason.
private struct SampleSettingsRoot: View {
    let appName: String
    let panes: [AnySettingsPane]
    @Bindable var selection: SampleSettingsSelection

    var body: some View {
        SettingsShell(appName: appName, panes: panes, selection: $selection.paneID)
    }
}
