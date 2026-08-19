import Testing
import Foundation
@testable import DragonKit

private let releaseID = "com.dragonapp.dragon-sample-app"
private let debugID = "com.dragonapp.dragon-sample-app.debug"
// `isDirectory:` is spelled out on every one: the plain `URL(fileURLWithPath:)` stats the real
// disk to decide, so a bundle that happens to be installed on the machine running the tests
// gains a trailing slash and an identical-looking one that isn't installed does not. These are
// fixtures for an injected world and must not depend on what this Mac has in /Applications.
private let installed = URL(fileURLWithPath: "/Applications/Dragon Sample App.app", isDirectory: true)
private let localBuild = URL(fileURLWithPath: "/Users/x/DerivedData/Build/Products/Release/Dragon Sample App.app", isDirectory: true)
private let aliasOfInstalled = URL(fileURLWithPath: "/Applications/../Applications/Dragon Sample App.app", isDirectory: true)
private let deleted = URL(fileURLWithPath: "/private/tmp/gone/Dragon Sample App.app", isDirectory: true)

/// A canonicalizer over a fixed world: a URL resolves to its canonical form when the world says
/// it exists, and to `nil` when it doesn't. Injected so no test reads the real LaunchServices
/// database or the real filesystem.
private func world(_ existing: [URL: URL]) -> (URL) -> URL? {
    { existing[$0] }
}

/// The gate in front of a complete uninstall.
///
/// `DragonUninstaller` moves *the running bundle* to the Trash, which is path-scoped and safe.
/// Everything either side of that is scoped to the bundle *identity*: the login item, the
/// defaults domains, the preference and saved-state plists, the configured cleanup paths, and
/// the Homebrew token. Those resources belong to whichever copy Homebrew or the user installed,
/// and two bundles with the same identity share every one of them.
///
/// So a second copy carrying the release identity — a local Release-configuration build in a
/// DerivedData or scratch folder is the ordinary way to get one — can uninstall the *installed*
/// app's state, and with a cask token can have Homebrew delete the installed app outright, while
/// `recycle()` moves only the local copy. The identity check the flow already had authorises on
/// identity alone, so it hands the token to any same-identity copy; it tests who you are, not
/// whether you are the only one.
///
/// This decision therefore fails closed and runs before every destructive step.
@Suite struct UninstallPreflightTests {
    // MARK: - Identity must be verifiable

    /// A build that cannot state its own identity authorises nothing. This is the case the
    /// sample app's `Bundle.main.bundleIdentifier ?? releaseBundleID` fallback got wrong: it
    /// answered *the release id* for the one build that couldn't name itself.
    @Test func missingActualIdentityFailsClosed() {
        for missing in [nil, ""] {
            let decision = DragonUninstaller.preflight(
                configBundleID: releaseID,
                actualBundleID: missing,
                currentBundleURL: installed,
                discoveredCopies: [],
                canonicalize: world([installed: installed])
            )
            #expect(decision == .identityUnverified)
        }
    }

    /// The configured id is what every deletion below is keyed on, so it may not be trusted
    /// past the running bundle disagreeing with it. No fallback: a mismatch is a stop, not a
    /// hint about which of the two to believe.
    @Test func configuredIdentityDifferingFromTheRunningBundleFailsClosed() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: debugID,
            currentBundleURL: installed,
            discoveredCopies: [],
            canonicalize: world([installed: installed])
        )
        #expect(decision == .identityUnverified)
    }

    // MARK: - Only one copy may exist

    /// The P0 case. Two bundles, one identity: the shared state cannot be attributed to either,
    /// so nothing is removed.
    @Test func twoDistinctExistingCopiesBlock() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installed,
            discoveredCopies: [installed, localBuild],
            canonicalize: world([installed: installed, localBuild: localBuild])
        )
        #expect(decision == .duplicateCopies([installed, localBuild]))
    }

    /// Two spellings of one bundle are one bundle. Canonicalization happens before counting, so
    /// a symlink, an alias or an unstandardized path cannot fake a duplicate and block a
    /// legitimate uninstall.
    @Test func twoSpellingsOfTheSameBundleAreNotTwoCopies() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installed,
            discoveredCopies: [installed, aliasOfInstalled],
            canonicalize: world([installed: installed, aliasOfInstalled: installed])
        )
        #expect(decision == .proceed)
    }

    /// LaunchServices keeps records of bundles that were deleted long ago — this machine held 19
    /// dead `com.dragonapp.ice` records against a single live copy. A dead record describes
    /// nothing on disk and must never block an uninstall.
    @Test func deadRecordsAreIgnored() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installed,
            discoveredCopies: [installed, deleted],
            canonicalize: world([installed: installed])
        )
        #expect(decision == .proceed)
    }

    /// The running bundle is counted whether or not discovery returned it, so a copy launched
    /// directly and absent from the database cannot slip past as "no copies at all".
    @Test func theRunningBundleIsCountedWhenDiscoveryOmitsIt() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: localBuild,
            discoveredCopies: [installed],
            canonicalize: world([installed: installed, localBuild: localBuild])
        )
        #expect(decision == .duplicateCopies([installed, localBuild]))
    }

    /// The ordinary case, which must stay ordinary: one installed copy, uninstall proceeds.
    @Test func aSingleCanonicalCopyProceeds() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installed,
            discoveredCopies: [installed],
            canonicalize: world([installed: installed])
        )
        #expect(decision == .proceed)
    }

    /// Release and Debug are different identities, so holding one of each — the fleet's normal
    /// development state — blocks neither. Discovery is queried for the exact running identity,
    /// so the other build is never in the candidate set to begin with.
    @Test func aDebugBuildBesideTheReleaseDoesNotBlockEither() {
        let debugBuild = URL(fileURLWithPath: "/Users/x/dragon-sample-app/.build/Dragon Sample App Debug.app", isDirectory: true)

        let release = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installed,
            discoveredCopies: [installed],
            canonicalize: world([installed: installed, debugBuild: debugBuild])
        )
        #expect(release == .proceed)

        let debug = DragonUninstaller.preflight(
            configBundleID: debugID,
            actualBundleID: debugID,
            currentBundleURL: debugBuild,
            discoveredCopies: [debugBuild],
            canonicalize: world([installed: installed, debugBuild: debugBuild])
        )
        #expect(debug == .proceed)
    }

    // MARK: - What a blocked decision is allowed to do

    /// Everything the flow does is behind one of three injected effects or is a direct call
    /// ordered after the gate, so a blocked run is proved two ways: the injected effects are
    /// never invoked, and the two uninjected ones — the configured cleanup paths and the
    /// defaults domains — are still there afterwards.
    ///
    /// `bundleID` is a per-run fake. `leftoverPaths` builds real `~/Library` paths from it, and a
    /// real fleet id would aim this test's `removeItem` calls at the preferences of an app
    /// actually installed on the machine running it.
    @MainActor @Test func aBlockedPreflightReportsAndTouchesNothing() throws {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory.appending(path: "dk-preflight-\(UUID().uuidString)")
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }

        let supportFile = scratch.appending(path: "support-file")
        try Data("survives".utf8).write(to: supportFile)

        let suite = "com.dragonapp.preflight-test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("survives", forKey: "canary")
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        var recycled = false, scheduled = false, completed = false, failed = false
        var reported: UninstallPreflight?

        DragonUninstaller.run(
            config: UninstallConfig(
                appName: "Dragon Sample App",
                bundleID: "com.dragonapp.preflight-test.\(UUID().uuidString)",
                suiteNames: [suite],
                checklistItems: ["x"],
                extraCleanupPaths: [supportFile],
                homebrewCask: "dragon-sample-app"
            ),
            deleteOptionalData: false,
            onComplete: { completed = true },
            recycle: { _, _ in recycled = true },
            scheduleCleanup: { _, _ in scheduled = true },
            reportFailure: { _, _ in failed = true },
            preflight: { .duplicateCopies([installed, localBuild]) },
            reportBlocked: { reported = $0 }
        )

        #expect(reported == .duplicateCopies([installed, localBuild]))
        #expect(!recycled, "the bundle must not reach the Trash")
        #expect(!scheduled, "no post-exit cleanup, and above all no brew uninstall")
        #expect(!completed, "onComplete terminates by default — a blocked uninstall must not quit")
        #expect(!failed, "the removal-failure alert is a different story and must not be told")
        #expect(fileManager.fileExists(atPath: supportFile.path), "configured cleanup paths survive")
        #expect(defaults.string(forKey: "canary") == "survives", "the defaults domain survives")
    }

    /// The control for the test above. Those two survival assertions only mean something if the
    /// same setup loses both when the gate opens — otherwise a flow that had quietly stopped
    /// deleting anything at all would pass the block test just as happily.
    @MainActor @Test func anAllowedPreflightPerformsWhatTheBlockPrevented() throws {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory.appending(path: "dk-preflight-\(UUID().uuidString)")
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }

        let supportFile = scratch.appending(path: "support-file")
        try Data("removed".utf8).write(to: supportFile)

        let suite = "com.dragonapp.preflight-test.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("removed", forKey: "canary")
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        var recycled = false
        var reported: UninstallPreflight?

        DragonUninstaller.run(
            config: UninstallConfig(
                appName: "Dragon Sample App",
                bundleID: "com.dragonapp.preflight-test.\(UUID().uuidString)",
                suiteNames: [suite],
                checklistItems: ["x"],
                extraCleanupPaths: [supportFile],
                homebrewCask: nil
            ),
            deleteOptionalData: false,
            onComplete: {},
            // Left uninvoked on purpose: its callback is what gates the post-exit cleanup and the
            // completion, and this control is only about the teardown that runs *before* it.
            recycle: { _, _ in recycled = true },
            scheduleCleanup: { _, _ in },
            reportFailure: { _, _ in },
            preflight: { .proceed },
            reportBlocked: { reported = $0 }
        )

        #expect(reported == nil, "nothing to report when the gate opens")
        #expect(recycled)
        #expect(!fileManager.fileExists(atPath: supportFile.path))
        #expect(defaults.string(forKey: "canary") == nil)
    }
}
