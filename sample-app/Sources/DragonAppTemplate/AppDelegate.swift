import AppKit
import SwiftUI
import DragonKit
import DragonKitUpdates

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Read from the bundle, never hardcoded — `UninstallConfig.optionalDataToggle` builds
    /// `Application Support/\(appName)` from this, so a literal meant a Debug build offered to
    /// delete the *release* build's data directory, and the uninstall sheet named the release app.
    ///
    /// Found by the first hands-on Debug-isolation test, in the app the other four mirror. It is
    /// the same defect spectacle-2's `AppIdentity` was written to prevent — its doc comment spells
    /// it out — and yahoo-keykey-2 had it too. Static review of the scripts had missed it here
    /// because nothing in this file *looked* like a path.
    ///
    /// In a release build `CFBundleDisplayName` is "Dragon Sample App", so this resolves to exactly
    /// the string it replaced.
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Dragon Sample App"
    }
    /// Names caches, storages and the menu-bar autosave slot. The fallback keeps a build that
    /// can't state its id out of `~/Library/Caches/` itself — it must never stand in for the
    /// real id anywhere a decision is destructive, which is why the Homebrew cask below asks
    /// `UninstallConfig.caskToken` (it reads `Bundle.main.bundleIdentifier` unfallen-back)
    /// rather than comparing this.
    private var bundleID: String { Bundle.main.bundleIdentifier ?? "com.dragonapp.dragon-sample-app" }
    /// The id Homebrew installs. `scripts/run.sh` builds `\(releaseBundleID).debug` instead, and
    /// the uninstall flow keys the cask cleanup off the difference.
    private let releaseBundleID = "com.dragonapp.dragon-sample-app"
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
            AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),
            AnySettingsPane(BackupSettingsPane(config: backupConfig)),
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
            ],
            // Distributed as a Homebrew cask. An app that deletes itself leaves brew's receipt
            // claiming it is still installed, so `brew install` then refuses for an app that
            // isn't there; the token lets the post-exit cleanup clear that record.
            //
            // Release build ONLY, and that condition is load-bearing. `scripts/run.sh` re-ids the
            // debug build to `…dragon-sample-app.debug`, which Homebrew never installed. With a
            // flat token, uninstalling the *debug* build would run
            // `brew uninstall --cask dragon-sample-app --force` and delete the *release* app out
            // of /Applications along with its receipt — a debug build destroying the installed
            // copy it was re-id'd specifically to stay away from. ice-2 caught this while adopting
            // the flag and guarded it; this app had shipped the unguarded version first.
            //
            // The kit owns the comparison so all five apps get the same one — and so a build with
            // no bundle id at all resolves to `nil` rather than to `bundleID`'s release-id
            // fallback, which would have authorised the delete on the one build least entitled
            // to it.
            homebrewCask: UninstallConfig.caskToken("dragon-sample-app", ifBundleIs: releaseBundleID)
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

        // Wake Sparkle now. `DragonUpdater` builds it lazily on first property access, so an app
        // that never reads one never starts the scheduled-check timer — apps used to poke
        // `canCheckForUpdates` to force it, which is what `start()` exists to replace. Info.plist
        // ships `SUEnableAutomaticChecks = false`, so this schedules nothing until the user turns
        // the Updates pane's toggle on; without it that toggle would do nothing this launch.
        //
        // Not in a Debug build. MAC-APP-RELEASE-LIFECYCLE.md requires the local build to never
        // read the production appcast, and clearing `SUEnableAutomaticChecks` alone does not
        // achieve that — the user can still turn the toggle on, and `start()` having run is what
        // makes that live. Leaving Sparkle uninitialized is the actual off switch.
        if !DragonAbout.isDebugBuild() {
            updater.start()
        }
    }

    /// Build the canonical Dragon menu-bar menu via `DragonAppMenu` — the single source of
    /// truth for order, naming, and icons, so this sample app stays the reference every app
    /// mirrors.
    /// Rebuilt on language change.
    private func buildMenu() -> NSMenu {
        // A Debug build passes `onCheckForUpdates: nil`, which drops the item from the dropdown
        // entirely — the same mechanism a Mac App Store build uses (§R1/§R6). An item left in
        // place but made inert reads as a bug; the lifecycle spec wants the Debug build to have
        // no route to the production appcast at all, not a route that silently does nothing.
        DragonAppMenu.menu(DragonAppMenu.Config(
            appName: appName,
            onAbout: { [weak self] in self?.openAbout() },
            onSettings: { [weak self] in self?.openSettings() },
            onCheckForUpdates: DragonAbout.isDebugBuild()
                ? nil
                : { [weak self] in self?.checkForUpdates() }
        ))
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
