import AppKit
import SwiftUI
import DragonKit
import DragonKitUpdates

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appName = "Dragon Sample App"
    private var bundleID: String { Bundle.main.bundleIdentifier ?? "com.dragonapp.dragon-sample-app" }
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
        if selection.paneID == nil { selection.paneID = "general" }
        return DragonSettingsWindowController(
            title: "\(appName) Settings",
            rootView: SampleSettingsRoot(
                appName: appName,
                panesBuilder: { [weak self] in self?.settingsPanes ?? [] },
                selection: selection
            )
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
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return UninstallConfig(
            appName: appName,
            bundleID: bundleID,
            suiteNames: [SettingsModel.suiteName],
            checklistItems: [
                L("app.uninstall.item.app"),
                L("app.uninstall.item.settings"),
                L("app.uninstall.item.state"),
            ],
            // Default-off: user data survives unless the user opts in.
            optionalDataToggle: (
                label: L("app.uninstall.optionalData"),
                paths: [library.appending(path: "Application Support/\(appName)")]
            ),
            // Always removed — transient state no uninstall should leave behind.
            extraCleanupPaths: [
                library.appending(path: "Caches/\(bundleID)"),
                library.appending(path: "HTTPStorages/\(bundleID)"),
            ]
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The app's own Localizable.strings ship in the SwiftPM resource bundle
        // (Package.swift `resources: [.process("Resources")]`), so resolve app keys from
        // that bundle rather than the default Bundle.main — this is what lets the release CI
        // build (which copies the SwiftPM bundle, not loose .lproj) show localized strings.
        // Use AppResources (not raw .module): in a packaged .app the bundle lives in
        // Contents/Resources, which SwiftPM's .module accessor misses and fatalErrors on.
        LocalizationManager.shared.appStringsBundle = AppResources.stringsBundle

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Per-bundle-id autosave name: without one the item persists anonymously as "Item-0"
        // in whatever defaults domain launched it, so debug/release builds (and agent-exec'd
        // runs) pollute each other's macOS menu-bar visibility store.
        item.autosaveName = "DragonKitSampleStatusItem-\(bundleID)"
        // A plain "D" marks this as the DragonKit sample app in the menu bar.
        if let button = item.button {
            button.title = "D"
            button.font = .systemFont(ofSize: 15, weight: .heavy)
        }

        item.menu = buildMenu()
        item.isVisible = model.showInMenuBar
        self.statusItem = item

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showInMenuBarChanged(_:)),
            name: .sampleShowInMenuBarChanged,
            object: nil
        )
        // Rebuild the menu when the language changes so its titles switch live.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .dragonLanguageChanged,
            object: nil
        )

        // Never trap the user: if the icon is hidden at launch, open Settings so they can
        // toggle it back on.
        if !model.showInMenuBar {
            settingsController.show()
        }
    }

    /// Build the menu-bar menu with localized titles. Rebuilt on language change.
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let settings = NSMenuItem(title: L("app.menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let checkUpdates = NSMenuItem(title: L("app.menu.checkForUpdates"), action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdates.target = self
        menu.addItem(checkUpdates)
        let about = NSMenuItem(title: L("app.menu.about"), action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("app.menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func languageChanged() {
        statusItem?.menu = buildMenu()
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

/// Settings root wired to the host's ``SampleSettingsSelection``. Observes
/// ``LocalizationManager`` and rebuilds the panes (so host-supplied content like About and
/// What's New re-localizes) whenever the language changes, then applies `.dragonLocalized()`
/// so the whole window switches language live — without a restart. Uses ``SettingsShell``
/// (host-owned selection) so the menu can open directly to a specific pane.
private struct SampleSettingsRoot: View {
    @ObservedObject private var localization = LocalizationManager.shared
    let appName: String
    let panesBuilder: () -> [AnySettingsPane]
    let selection: SampleSettingsSelection

    var body: some View {
        // This view observes only the language, so `panesBuilder()` re-runs on a language
        // change — not on every pane selection (which `SettingsPaneList` handles).
        SettingsPaneList(appName: appName, panes: panesBuilder(), selection: selection)
            .dragonLocalized()
    }
}

/// Holds the (language-stable) pane list and binds selection, so switching panes re-renders
/// the sidebar/detail without rebuilding every pane.
private struct SettingsPaneList: View {
    let appName: String
    let panes: [AnySettingsPane]
    @Bindable var selection: SampleSettingsSelection

    var body: some View {
        SettingsShell(appName: appName, panes: panes, selection: $selection.paneID)
    }
}
