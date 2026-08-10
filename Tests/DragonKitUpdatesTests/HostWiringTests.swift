import Testing
import Foundation
import SwiftUI
// Plain imports, deliberately not `@testable`, for the reason
// `Tests/DragonKitTests/HostWiringTests.swift` records: this suite stands in for a host app, and
// an app sees only the public surface.
import DragonKit
import DragonKitUpdates

/// The direct-download half of the host-wiring coverage that replaced `sample-app/`.
///
/// `Tests/DragonKitTests/HostWiringTests.swift` assembles the Mac App Store shape — every pane a
/// sandboxed build wires, with this module out of scope, which is what keeps clipmenu-2's
/// core-only link honest. This one adds the slot that link cannot have: `UpdatesSettingsPane`,
/// between What's New and About. Together they are what `cd sample-app && swift build` used to
/// prove, and the only place in this repository where the full canonical sidebar is built from
/// real panes.
///
/// Nothing here touches Sparkle. `DragonUpdater.init` only stores its config — the framework is
/// built lazily on first property access, which is exactly why `start()` exists — so constructing
/// one creates no `SPUUpdater` and starts no timer.
@MainActor
@Suite struct HostWiringWithUpdatesTests {
    private struct GeneralPane: SettingsPane {
        let id = "general"
        let title = "General"
        let systemImage = "gearshape"
        var paneBody: some View { Text(verbatim: "general") }
    }

    private let appName = "Host App"
    private let updater = DragonUpdater()

    private var panes: [AnySettingsPane] {
        [
            AnySettingsPane(GeneralPane()),
            AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),
            AnySettingsPane(BackupSettingsPane(config: BackupConfig(
                appName: appName,
                suiteName: "com.example.hostapp.settings",
                appVersion: "1.0.0",
                relaunch: {}
            ))),
            AnySettingsPane(WhatsNewSettingsPane(content: WhatsNewContent(date: "2026-08-10"))),
            AnySettingsPane(UpdatesSettingsPane(updater: updater)),
            AnySettingsPane(AboutSettingsPane(content: AboutContent(
                appName: appName,
                versionString: DragonAbout.versionString(),
                copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),
                websiteURL: URL(string: "https://www.dragonapp.com/host-app-1/")!,
                supportURL: URL(string: "https://github.com/teddychan/host-app-1/issues")!,
                license: "MIT"
            ))),
            AnySettingsPane(UninstallSettingsPane(config: UninstallConfig(
                appName: appName,
                bundleID: "com.example.hostapp",
                checklistItems: ["The app"]
            ))),
        ]
    }

    /// CONFORMANCE §R9's canon, whole, on the kit's own pane identifiers. The four shipping apps
    /// are checked against this order by `dragon-conformance.py`, which matches its slots on these
    /// exact spellings — so the kit renaming one breaks the checker and five apps' `paneID`
    /// deep-links at the same time, and nothing else here would notice.
    @Test func theFullSidebarAssemblesInTheCanonicalOrder() {
        #expect(panes.map(\.id) == [
            "general", "permissions", "backup", "whatsnew", "updates", "about", "uninstall",
        ])
    }

    /// A host that opts into gentle reminders wires the config through the initializer, not by
    /// mutating the updater afterwards — the shape ice-2 adopted after its own Sparkle wiring
    /// silently dropped both settings.
    @Test func theUpdaterAcceptsAConfigAndErasesIntoTheSidebar() {
        let configured = DragonUpdater(config: DragonUpdaterConfig(
            usesGentleScheduledReminders: true,
            onUpdateFoundInBackground: {}
        ))
        let pane = AnySettingsPane(UpdatesSettingsPane(updater: configured))
        #expect(pane.id == "updates")
        #expect(!pane.systemImage.isEmpty)
    }

    @Test func bothSettingsShellsAcceptTheAssembledPanes() {
        _ = SettingsShell(appName: appName, panes: panes, selection: .constant("updates"))
        _ = ManagedSettingsShell(appName: appName, panes: panes)
    }
}
