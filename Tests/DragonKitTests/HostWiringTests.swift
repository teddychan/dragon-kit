import Testing
import Foundation
import SwiftUI
// A plain import, deliberately not `@testable`. This suite stands in for a host app, and an app
// sees only the public surface — `@testable` would let it reach internal symbols and so let a
// public-API break pass here while breaking all five apps.
import DragonKit

/// Assembly coverage for the way a host app wires the kit's shared panes and configs together.
///
/// This replaces `sample-app/`, which lived in this repository until Dragon Sample App moved to
/// its own repo (`docs/MAC-APP-RELEASE-LIFECYCLE.md`: one public `vX.Y.Z` series per repository,
/// and this one's belongs to the Swift package). CI ran `cd sample-app && swift build`, and that
/// build was the *only* thing in the repo that constructed a real `AboutSettingsPane`,
/// `BackupSettingsPane`, `PermissionsSettingsPane`, `WhatsNewSettingsPane`,
/// `UninstallSettingsPane` or `SettingsShell` — `SettingsPaneTests` uses a `FakePane`, and no test
/// touched `AboutContent`'s 12-parameter initializer, `BackupConfig` or `UninstallConfig` the way
/// an `AppDelegate` does. Deleting the app without replacing that would have let the kit add a
/// non-defaulted parameter to any of those, go green, ship a tag, and break five apps on bump —
/// the exact failure CLAUDE.md's "Public API is a contract with five apps" exists to stop.
///
/// The app's own repository cannot supply this signal: its CI builds against the *published* pin
/// (`from: "3.3.0"`), so a break on this branch is invisible there until the kit tags a release
/// and the app bumps. Cloning it here instead would be worse — an intentional breaking change
/// would red-X kit CI with no way to fix it in the same PR.
///
/// Shaped as the **Mac App Store host**: every pane a sandboxed build wires, with
/// `DragonKitUpdates` out of scope. That is what keeps clipmenu-2's core-only link honest — see
/// `Tests/DragonKitUpdatesTests/HostWiringTests.swift` for the Sparkle shape.
///
/// No windows are created and nothing is rendered, for the reason `SettingsMainMenuTests` records.
@MainActor
@Suite struct HostWiringTests {
    // MARK: The host's own material

    /// The app-owned pane that occupies the General slot. Every Dragon app writes its own; the kit
    /// owns the slots around it.
    private struct GeneralPane: SettingsPane {
        let id = "general"
        let title = "General"
        let systemImage = "gearshape"
        var paneBody: some View { Text(verbatim: "general") }
    }

    private let appName = "Host App"
    private let bundleID = "com.example.hostapp"
    private var suiteName: String { bundleID + ".settings" }
    private var library: URL {
        URL(fileURLWithPath: "/Users/host/Library", isDirectory: true)
    }

    /// Every About slot a host can fill, on purpose: this fixture is the only place the kit builds
    /// a real ``AboutContent``, so a slot it skips is a slot whose initializer can change
    /// unnoticed. `originalWork` carries the upstream URL, and `licensesURL` is required — the two
    /// invariants 4.0.0 added after clipmenu-2 and ice-2 shipped a `Based on` credit with no link,
    /// and spectacle-2 and the sample app listed bundled components with no notices page.
    private var aboutContent: AboutContent {
        AboutContent(
            appName: appName,
            versionString: DragonAbout.versionString(),
            copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),
            websiteURL: URL(string: "https://www.dragonapp.com/host-app-1/")!,
            supportURL: URL(string: "https://github.com/teddychan/host-app-1/issues")!,
            licensesURL: URL(string: "https://www.dragonapp.com/host-app-1/licenses/")!,
            license: "MIT",
            originalWork: OriginalWork(
                name: "Host App",
                author: "Some Author",
                url: URL(string: "https://github.com/someauthor/host-app")!
            ),
            attributions: [Attribution(name: "Sparkle", license: "MIT")]
        )
    }

    /// No `version:` argument, which is the point: the lifecycle spec's release gate rejects an
    /// explicit current-version literal here, and every host must let the initializer read
    /// `CFBundleShortVersionString`.
    private var whatsNewContent: WhatsNewContent {
        WhatsNewContent(
            date: "2026-08-10",
            summary: "Summary",
            sections: [ChangeSection(kind: .fixed, entries: ["An entry"])]
        )
    }

    private var backupConfig: BackupConfig {
        BackupConfig(appName: appName, suiteName: suiteName, appVersion: "1.0.0", relaunch: {})
    }

    private var uninstallConfig: UninstallConfig {
        UninstallConfig(
            appName: appName,
            bundleID: bundleID,
            suiteNames: [suiteName],
            checklistItems: ["The app", "Its settings"],
            optionalDataToggle: (
                label: "Also delete data",
                paths: [library.appending(path: "Application Support/\(appName)")]
            ),
            extraCleanupPaths: [library.appending(path: "Caches/\(bundleID)")],
            homebrewCask: UninstallConfig.caskToken("host-app", ifBundleIs: bundleID, actual: bundleID)
        )
    }

    /// The sidebar a sandboxed host assembles: the canon order with the Updates slot absent,
    /// which is what `onCheckForUpdates: nil` buys a Mac App Store build (§R6/§R11).
    private var panes: [AnySettingsPane] {
        [
            AnySettingsPane(GeneralPane()),
            AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),
            AnySettingsPane(BackupSettingsPane(config: backupConfig)),
            AnySettingsPane(WhatsNewSettingsPane(content: whatsNewContent)),
            AnySettingsPane(AboutSettingsPane(content: aboutContent)),
            AnySettingsPane(UninstallSettingsPane(config: uninstallConfig)),
        ]
    }

    // MARK: - The assembly

    /// CONFORMANCE §R9's canon, asserted on the kit's own pane identifiers rather than on an app's
    /// source order. The ids are load-bearing beyond the sidebar: apps set `selection.paneID =
    /// "about"` to open a pane from the menu, and `dragon-conformance.py` matches its slots on
    /// these spellings — so renaming one silently breaks both, in five apps at once.
    @Test func theSidebarAssemblesInTheCanonicalOrder() {
        #expect(panes.map(\.id) == ["general", "permissions", "backup", "whatsnew", "about", "uninstall"])
    }

    /// A pane with no SF Symbol renders a blank sidebar row. The kit fixes the symbols precisely
    /// so they can't be per-app choices, so a missing one is a kit bug, not an app's.
    @Test func everyPaneCarriesATitleAndAnSFSymbol() {
        for pane in panes {
            #expect(!pane.title.isEmpty, "\(pane.id) has no title")
            #expect(!pane.systemImage.isEmpty, "\(pane.id) has no SF Symbol")
        }
    }

    /// Both shells a host can choose between. Constructing the values type-checks the public
    /// initializers; SwiftUI renders nothing until a window asks it to.
    @Test func bothSettingsShellsAcceptTheAssembledPanes() {
        _ = SettingsShell(appName: appName, panes: panes, selection: .constant("about"))
        _ = ManagedSettingsShell(appName: appName, panes: panes)
    }

    /// Type-checked, never called — these tests create no windows. What must not break is the
    /// *call site*: the initializer's own doc comment explains that `installsMainMenu` and
    /// `includeQuit` were defaulted and placed ahead of `rootView` so the five apps' existing
    /// `init(title:rootView:)` calls keep compiling. This is what fails if that ordering moves.
    @Test func theWindowControllerStillTakesTitleAndRootViewAlone() {
        let make: @MainActor () -> DragonSettingsWindowController = { [appName, panes] in
            DragonSettingsWindowController(
                title: "\(appName) Settings",
                rootView: ManagedSettingsShell(appName: appName, panes: panes)
            )
        }
        #expect(Bool(true), "\(type(of: make)) type-checks")
    }

    /// The version reaches What's New through the bundle, never a literal — so it arrives
    /// `v`-prefixed via `DragonVersion`. The in-tree sample app passed `version: "1.4.0"` here and
    /// went stale against its own `Info.plist`; `WhatsNewContent.version` is non-public so that
    /// the un-prefixed form is unreachable from an app at all.
    @Test func whatsNewTakesItsVersionFromTheBundle() {
        #expect(whatsNewContent.displayVersion.hasPrefix("v"))
    }

    /// Both call shapes of the language picker a host drops into its own General pane, from the
    /// plain import an app has. The no-argument form is what the four apps matching the kit's
    /// language coverage write; the restricted form is ice-2's, which ships Simplified Chinese
    /// alone and relaunches because a SwiftUI String Catalog resolves at launch.
    ///
    /// Wired here for the reason this whole suite exists: both parameters are defaulted today, so
    /// nothing else in the repository would notice one becoming required — `LanguagePickerOptionTests`
    /// calls the static option logic, never the initializer.
    @Test func bothLanguagePickerShapesCompileForAHost() {
        _ = LanguagePicker()
        _ = LanguagePicker(languages: [.en, .zhHans]) { _ in }
    }

    /// The host supplies URLs and proper nouns; the kit assembles every row. `AboutCanonTests`
    /// pins the rows themselves — this only checks that a host's own values survive the trip,
    /// which is what a free-form `links`/`credits` array used to let five apps get wrong.
    @Test func aboutKeepsTheHostsValuesAndDerivesTheRest() {
        let content = aboutContent
        #expect(content.appName == appName)
        #expect(content.websiteMatchesSupportRepo)
        #expect(content.versionString.hasPrefix("v"))
    }
}
