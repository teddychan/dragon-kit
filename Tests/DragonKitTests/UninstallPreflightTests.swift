import AppKit
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

private let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
private let allUsersFolder = URL(fileURLWithPath: "/Library/Input Methods", isDirectory: true)
private let installedForAllUsers = URL(fileURLWithPath: "/Library/Input Methods/Dragon Sample App.app", isDirectory: true)

/// Writability over a fixed world, for the same reason: a folder or bundle is writable by this
/// user only when the test says so.
private func writable(_ urls: Set<URL>) -> (URL) -> Bool {
    { urls.contains($0) }
}

/// For the tests about identity and copies, which are not about removability: everything is
/// writable, so the only thing that can block them is what they test. Spelled out at every call
/// rather than defaulted in the kit, because a default of "writable" would be a fail-open path
/// in production.
private let everythingWritable: @Sendable (URL) -> Bool = { _ in true }

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
                canonicalize: world([installed: installed]),
                isWritable: everythingWritable
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
            canonicalize: world([installed: installed]),
            isWritable: everythingWritable
        )
        #expect(decision == .identityUnverified)
    }

    /// The running bundle must resolve to a real path, and failing to is a stop rather than
    /// something to skip.
    ///
    /// It used to be folded in with the discovered URLs, where a canonicalization failure was
    /// skipped like any dead record — and the surviving count could then be zero, which the
    /// `count <= 1` test read as "no duplicates, proceed". That was a fail-open branch in the
    /// middle of a decision whose entire purpose is failing closed.
    @Test func currentBundleThatCannotBeResolvedFailsClosed() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installed,
            discoveredCopies: [],
            canonicalize: world([:]),
            isWritable: everythingWritable
        )
        #expect(decision == .identityUnverified)
    }

    /// And it stays a stop when discovery *did* resolve something: one resolvable copy plus an
    /// unresolvable running bundle is not "a single copy, proceed" — it is not knowing what is
    /// running, which authorises nothing.
    @Test func unresolvableCurrentBundleFailsClosedEvenWhenDiscoveryResolves() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: localBuild,
            discoveredCopies: [installed],
            canonicalize: world([installed: installed]),
            isWritable: everythingWritable
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
            canonicalize: world([installed: installed, localBuild: localBuild]),
            isWritable: everythingWritable
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
            canonicalize: world([installed: installed, aliasOfInstalled: installed]),
            isWritable: everythingWritable
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
            canonicalize: world([installed: installed]),
            isWritable: everythingWritable
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
            canonicalize: world([installed: installed, localBuild: localBuild]),
            isWritable: everythingWritable
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
            canonicalize: world([installed: installed]),
            isWritable: everythingWritable
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
            canonicalize: world([installed: installed, debugBuild: debugBuild]),
            isWritable: everythingWritable
        )
        #expect(release == .proceed)

        let debug = DragonUninstaller.preflight(
            configBundleID: debugID,
            actualBundleID: debugID,
            currentBundleURL: debugBuild,
            discoveredCopies: [debugBuild],
            canonicalize: world([installed: installed, debugBuild: debugBuild]),
            isWritable: everythingWritable
        )
        #expect(debug == .proceed)
    }

    // MARK: - This user must be able to move the bundle

    /// The case this was written for. Yahoo! KeyKey 2 installed for all users is root:wheel inside
    /// root:wheel 755 /Library/Input Methods, and `NSWorkspace.recycle` asks for no password — it
    /// just fails. The teardown used to run first, so the user lost their settings and learning data
    /// and then read "Uninstall Incomplete" with the app still installed.
    @Test func aBundleInAFolderThisUserCannotWriteIsRefused() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installedForAllUsers,
            discoveredCopies: [installedForAllUsers],
            canonicalize: world([installedForAllUsers: installedForAllUsers]),
            // The bundle alone, so it is the folder that decides.
            isWritable: writable([installedForAllUsers])
        )
        #expect(decision == .bundleNotRemovable(installedForAllUsers))
    }

    /// The folder alone is not enough. Moving a directory into the Trash also rewrites its own
    /// `..`, so the bundle must be writable too — and a root-owned bundle in admin-writable
    /// /Applications, which is what the Mac App Store and every .pkg installer leave behind, is not.
    @Test func aBundleThisUserCannotWriteIsRefusedEvenInAWritableFolder() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installed,
            discoveredCopies: [installed],
            canonicalize: world([installed: installed]),
            isWritable: writable([applications])
        )
        #expect(decision == .bundleNotRemovable(installed))
    }

    /// The positive control, asked of exactly the right two things: the *resolved* bundle and its
    /// resolved folder, which are what the Trash move acts on — not the spelling the process
    /// happened to be launched through, whose parent here is `/Applications/../Applications`.
    @Test func removabilityIsAskedOfTheResolvedBundleAndItsFolder() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: aliasOfInstalled,
            discoveredCopies: [installed],
            canonicalize: world([aliasOfInstalled: installed, installed: installed]),
            isWritable: writable([installed, applications])
        )
        #expect(decision == .proceed)
    }

    /// Identity stays the first question. A build that cannot vouch for itself is refused as that,
    /// wherever it happens to be installed.
    @Test func identityIsDecidedBeforeRemovability() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: debugID,
            currentBundleURL: installedForAllUsers,
            discoveredCopies: [],
            canonicalize: world([installedForAllUsers: installedForAllUsers]),
            isWritable: writable([])
        )
        #expect(decision == .identityUnverified)
    }

    /// Removability is decided before the copies are counted, because it settles the question on
    /// its own: a bundle this user cannot move cannot be uninstalled from here whether or not it is
    /// alone, and the way out it is given — Finder, or brew — touches nothing the copies share. The
    /// duplicate advice would only send the user round a second time to reach the same answer.
    @Test func anUnremovableBundleIsReportedBeforeAnyDuplicates() {
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installedForAllUsers,
            discoveredCopies: [installedForAllUsers, localBuild],
            canonicalize: world([installedForAllUsers: installedForAllUsers, localBuild: localBuild]),
            isWritable: writable([installedForAllUsers, localBuild])
        )
        #expect(decision == .bundleNotRemovable(installedForAllUsers))
    }

    // MARK: - What a blocked decision is allowed to do

    /// Everything the flow does is behind one of three injected effects or is a direct call
    /// ordered after the gate, so a blocked run is proved two ways: the injected effects are
    /// never invoked, and the two uninjected ones — the configured cleanup paths and the
    /// defaults domains — are still there afterwards.
    ///
    /// Run for every blocking decision, not only the one it was written for. The gate is a single
    /// `!= .proceed`, and the not-removable case is the one whose whole bug was the teardown
    /// running in front of a Trash move that could not work — so it is asserted here, not assumed.
    ///
    /// `bundleID` is a per-run fake. `leftoverPaths` builds real `~/Library` paths from it, and a
    /// real fleet id would aim this test's `removeItem` calls at the preferences of an app
    /// actually installed on the machine running it.
    @MainActor @Test(arguments: [
        UninstallPreflight.duplicateCopies([installed, localBuild]),
        .bundleNotRemovable(installedForAllUsers),
        .identityUnverified,
    ])
    func aBlockedPreflightReportsAndTouchesNothing(_ decision: UninstallPreflight) throws {
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
        var loginItemWrites: [Bool] = []

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
            preflight: { decision },
            reportBlocked: { reported = $0 },
            setLoginItemEnabled: { loginItemWrites.append($0) }
        )

        #expect(reported == decision)
        // The first destructive step of all, and the one that is not undone by reinstalling:
        // proving the gate precedes *this* is what proves it precedes the teardown rather than
        // merely the injected tail of it.
        #expect(loginItemWrites.isEmpty, "the login item must not be disabled")
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
        var loginItemWrites: [Bool] = []

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
            reportBlocked: { reported = $0 },
            setLoginItemEnabled: { loginItemWrites.append($0) }
        )

        #expect(reported == nil, "nothing to report when the gate opens")
        #expect(loginItemWrites == [false], "and the login item is disabled exactly once")
        #expect(recycled)
        #expect(!fileManager.fileExists(atPath: supportFile.path))
        #expect(defaults.string(forKey: "canary") == nil)
    }
}

/// The production discovery and canonicalization behind ``DragonUninstaller/preflight(_:)``.
///
/// The suite above decides correctly over an injected world. These tests are about whether the
/// real inputs describe the real world, which is where the first version was wrong: it asked
/// LaunchServices alone, and LaunchServices did not know about an independently built copy under
/// `.build` even while that copy was running.
@Suite struct UninstallDiscoveryTests {
    // MARK: - Both directories are consulted

    /// The case that motivated adding `NSRunningApplication`: registered comes back empty, the
    /// app is running anyway, and the copy must still be found.
    @Test func aRunningCopyIsFoundWhenLaunchServicesHasNoRecordOfIt() {
        let copies = DragonUninstaller.discoverBundleCopies(
            withIdentifier: releaseID,
            registered: { _ in [] },
            running: { _ in [localBuild] }
        )
        #expect(copies == [localBuild])
    }

    /// And end to end: a running-only duplicate reaches the decision and blocks it. Finding the
    /// copy would be pointless if it did not change the answer.
    @Test func aRunningOnlyDuplicateBlocksTheUninstall() {
        let discovered = DragonUninstaller.discoverBundleCopies(
            withIdentifier: releaseID,
            registered: { _ in [] },
            running: { _ in [localBuild] }
        )
        let decision = DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: installed,
            discoveredCopies: discovered,
            canonicalize: world([installed: installed, localBuild: localBuild]),
            isWritable: everythingWritable
        )
        #expect(decision == .duplicateCopies([installed, localBuild]))
    }

    @Test func bothSourcesContribute() {
        let copies = DragonUninstaller.discoverBundleCopies(
            withIdentifier: releaseID,
            registered: { _ in [installed] },
            running: { _ in [localBuild] }
        )
        #expect(Set(copies) == Set([installed, localBuild]))
    }

    // MARK: - Real canonicalization, against the real filesystem

    /// A scratch directory standing in for an installed bundle, plus whatever the test points at
    /// it. `.app` on purpose: nothing here special-cases the extension, but the fixtures should
    /// look like what production sees.
    private func withScratch(_ body: (URL, URL) throws -> Void) throws {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory
            .appending(path: "dk-canon-\(UUID().uuidString)")
        let bundle = scratch.appending(path: "Dragon Sample App.app")
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }
        try body(scratch, bundle)
    }

    @Test func aRealSymlinkResolvesToItsTarget() throws {
        try withScratch { scratch, bundle in
            let link = scratch.appending(path: "Link To App.app")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)

            let resolvedBundle = try #require(DragonUninstaller.canonicalBundleURL(bundle))
            let resolvedLink = try #require(DragonUninstaller.canonicalBundleURL(link))
            #expect(resolvedLink == resolvedBundle, "a symlink is not a second copy")
        }
    }

    /// A Finder alias is a regular file whose contents are a bookmark, not a symlink, so
    /// `resolvingSymlinksInPath()` does not follow one. Without the explicit alias resolution an
    /// alias sitting next to the app would have counted as a second copy and blocked a
    /// legitimate uninstall — which is why the claim is tested rather than asserted in a comment.
    @Test func aFinderAliasResolvesToItsTarget() throws {
        try withScratch { scratch, bundle in
            let alias = scratch.appending(path: "Alias To App.app")
            let bookmark = try bundle.bookmarkData(
                options: .suitableForBookmarkFile,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            try URL.writeBookmarkData(bookmark, to: alias)

            let resolvedBundle = try #require(DragonUninstaller.canonicalBundleURL(bundle))
            let resolvedAlias = try #require(DragonUninstaller.canonicalBundleURL(alias))
            #expect(resolvedAlias == resolvedBundle, "an alias is not a second copy")
        }
    }

    /// A symlink in a *parent* directory, not on the bundle itself. `/var` → `/private/var` is
    /// this shape and every temporary directory on macOS sits under it, so the counting has to
    /// fold both spellings together or every scratch-built copy would look like two.
    @Test func aSymlinkedParentDirectoryResolvesToTheSameBundle() throws {
        try withScratch { scratch, bundle in
            let realParent = scratch.appending(path: "real")
            let movedBundle = realParent.appending(path: "Dragon Sample App.app")
            try FileManager.default.createDirectory(at: movedBundle, withIntermediateDirectories: true)

            let linkedParent = scratch.appending(path: "linked")
            try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: realParent)
            let viaLinkedParent = linkedParent.appending(path: "Dragon Sample App.app")

            let direct = try #require(DragonUninstaller.canonicalBundleURL(movedBundle))
            let indirect = try #require(DragonUninstaller.canonicalBundleURL(viaLinkedParent))
            #expect(indirect == direct)
            _ = bundle
        }
    }

    /// An alias whose target is gone is a dead application record and must resolve to nothing.
    ///
    /// The first version of the helper could not tell the two failure shapes apart. It did
    /// `(try? URL(resolvingAliasFileAt:)) ?? url`, so a *stale* alias — resolution fails, the
    /// alias file itself still exists — fell back to the alias file, passed the existence check,
    /// and counted as a live copy. One forgotten alias left behind in a folder would then have
    /// blocked a legitimate single-copy uninstall for good, which is the opposite of the failure
    /// this whole gate exists to prevent.
    @Test func anAliasWhoseTargetIsGoneResolvesToNothing() throws {
        try withScratch { scratch, bundle in
            let alias = scratch.appending(path: "Alias To App.app")
            let bookmark = try bundle.bookmarkData(
                options: .suitableForBookmarkFile,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            try URL.writeBookmarkData(bookmark, to: alias)

            // The target goes; the alias file stays. That gap is the whole bug.
            try FileManager.default.removeItem(at: bundle)
            #expect(FileManager.default.fileExists(atPath: alias.path), "the alias file itself remains")

            #expect(DragonUninstaller.canonicalBundleURL(alias) == nil)
        }
    }

    @Test func aPathThatDoesNotExistResolvesToNothing() throws {
        try withScratch { scratch, _ in
            let missing = scratch.appending(path: "Never Existed.app")
            #expect(DragonUninstaller.canonicalBundleURL(missing) == nil)
        }
    }

    /// `..` and a doubled separator name the same bundle, and both must fold onto the one path
    /// the counting is done over.
    @Test func unstandardizedSpellingsFoldOntoOnePath() throws {
        try withScratch { scratch, bundle in
            let awkward = URL(
                fileURLWithPath: scratch.path + "/./Dragon Sample App.app",
                isDirectory: true
            )
            let viaParent = URL(
                fileURLWithPath: bundle.path + "/../Dragon Sample App.app",
                isDirectory: true
            )

            let canonical = try #require(DragonUninstaller.canonicalBundleURL(bundle))
            #expect(DragonUninstaller.canonicalBundleURL(awkward) == canonical)
            #expect(DragonUninstaller.canonicalBundleURL(viaParent) == canonical)
        }
    }

    /// The dedup that matters: three spellings of one bundle are one copy, so the uninstall runs.
    @Test func severalSpellingsOfOneRealBundleDoNotBlock() throws {
        try withScratch { scratch, bundle in
            let link = scratch.appending(path: "Link To App.app")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bundle)
            let awkward = URL(
                fileURLWithPath: scratch.path + "/./Dragon Sample App.app",
                isDirectory: true
            )

            let decision = DragonUninstaller.preflight(
                configBundleID: releaseID,
                actualBundleID: releaseID,
                currentBundleURL: bundle,
                discoveredCopies: [link, awkward, bundle],
                canonicalize: DragonUninstaller.canonicalBundleURL,
                isWritable: DragonUninstaller.isWritableByThisUser
            )
            #expect(decision == .proceed)
        }
    }

    /// And the converse, through production canonicalization rather than a fixture map: two
    /// genuinely separate bundles block.
    @Test func twoRealBundlesBlock() throws {
        try withScratch { scratch, bundle in
            let second = scratch.appending(path: "Copies/Dragon Sample App.app")
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

            let decision = DragonUninstaller.preflight(
                configBundleID: releaseID,
                actualBundleID: releaseID,
                currentBundleURL: bundle,
                discoveredCopies: [second],
                canonicalize: DragonUninstaller.canonicalBundleURL,
                isWritable: DragonUninstaller.isWritableByThisUser
            )
            guard case .duplicateCopies(let urls) = decision else {
                Issue.record("expected a block, got \(decision)")
                return
            }
            #expect(urls.count == 2)
        }
    }
}

/// The production writability test behind the removability half of the preflight, against real
/// directories rather than a fixture map.
///
/// Disabled as root, which permission bits do not bind: every lock below would be ignored and the
/// refusals would read as failures. `swift test` runs as an ordinary user locally and on CI.
@Suite(.enabled(if: geteuid() != 0, "root is not bound by permission bits"))
struct UninstallRemovabilityTests {
    /// A scratch folder whose contents the test may lock. ``removeScratch(_:)`` restores write
    /// access to all of it first, because a 555 directory cannot be emptied and the folder would
    /// otherwise outlive the test.
    private func makeScratch() throws -> URL {
        let scratch = FileManager.default.temporaryDirectory
            .appending(path: "dk-removable-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return scratch
    }

    private func removeScratch(_ scratch: URL) {
        let fileManager = FileManager.default
        let contents = fileManager.enumerator(at: scratch, includingPropertiesForKeys: nil)?
            .allObjects as? [URL] ?? []
        for url in [scratch] + contents {
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try? fileManager.removeItem(at: scratch)
    }

    private func makeBundle(in folder: URL) throws -> URL {
        let bundle = folder.appending(path: "Dragon Sample App.app")
        try FileManager.default.createDirectory(
            at: bundle.appending(path: "Contents"), withIntermediateDirectories: true
        )
        return bundle
    }

    private func lock(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path)
    }

    /// Everything production, nothing injected: the decision a real uninstall of `bundle` gets.
    private func productionDecision(for bundle: URL) -> UninstallPreflight {
        DragonUninstaller.preflight(
            configBundleID: releaseID,
            actualBundleID: releaseID,
            currentBundleURL: bundle,
            discoveredCopies: [bundle],
            canonicalize: DragonUninstaller.canonicalBundleURL,
            isWritable: DragonUninstaller.isWritableByThisUser
        )
    }

    /// The all-users shape: a folder this user cannot write.
    @Test func aBundleInAFolderThisUserCannotWriteIsRefused() throws {
        let scratch = try makeScratch()
        defer { removeScratch(scratch) }
        let folder = scratch.appending(path: "Input Methods")
        let bundle = try makeBundle(in: folder)
        try lock(folder)

        let resolved = try #require(DragonUninstaller.canonicalBundleURL(bundle))
        #expect(productionDecision(for: bundle) == .bundleNotRemovable(resolved))
    }

    /// The Mac App Store and .pkg shape: a bundle this user cannot write, in a folder they can.
    @Test func aBundleThisUserCannotWriteIsRefusedEvenInAWritableFolder() throws {
        let scratch = try makeScratch()
        defer { removeScratch(scratch) }
        let bundle = try makeBundle(in: scratch)
        try lock(bundle)

        let resolved = try #require(DragonUninstaller.canonicalBundleURL(bundle))
        #expect(productionDecision(for: bundle) == .bundleNotRemovable(resolved))
    }

    /// The ordinary shape — a bundle the user owns, in a folder they can write — still proceeds.
    @Test func aBundleThisUserCanMoveProceeds() throws {
        let scratch = try makeScratch()
        defer { removeScratch(scratch) }
        let bundle = try makeBundle(in: scratch)
        #expect(productionDecision(for: bundle) == .proceed)
    }

    /// The premise behind both refusals, pinned against the call the uninstaller actually makes so
    /// it is re-checked rather than remembered. `NSWorkspace.recycle` asks for no administrator
    /// password: in either shape it fails with a permission error and leaves the bundle where it is.
    /// If a future macOS starts prompting, or starts moving such a bundle, these refusals are
    /// turning away uninstalls that would have worked, and this test is what says so.
    @MainActor @Test(arguments: ["folder", "bundle"])
    func theTrashMoveReallyFailsInBothShapes(_ locked: String) async throws {
        let scratch = try makeScratch()
        defer { removeScratch(scratch) }
        let folder = scratch.appending(path: "Installed")
        let bundle = try makeBundle(in: folder)
        try lock(locked == "folder" ? folder : bundle)

        let error: (domain: String, code: Int)? = await withCheckedContinuation { done in
            NSWorkspace.shared.recycle([bundle]) { _, error in
                done.resume(returning: error.map { (($0 as NSError).domain, ($0 as NSError).code) })
            }
        }
        #expect(error?.domain == NSCocoaErrorDomain)
        #expect(error?.code == NSFileWriteNoPermissionError)
        #expect(FileManager.default.fileExists(atPath: bundle.path), "the bundle did not move")
    }
}

/// How the blocked-duplicates alert renders its list.
@Suite struct UninstallBlockedAlertTests {
    @Test func displayedPathsAbbreviateTheHomeDirectory() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let inHome = URL(fileURLWithPath: home + "/git/app/.build/App.app", isDirectory: true)

        let shown = DragonUninstaller.displayPath(inHome)
        #expect(shown.hasPrefix("~/"), "got \(shown)")
        #expect(!shown.contains(home), "the account name must not be spelled out on every row")
    }

    @Test func pathsOutsideHomeAreShownWhole() {
        #expect(DragonUninstaller.displayPath(installed) == "/Applications/Dragon Sample App.app")
    }

    /// Nothing is dropped, however many there are — the accessory scrolls instead. A user told
    /// "there is another copy" cannot act on it without being told which.
    @Test func theListKeepsEveryPath() {
        let many = (0..<100).map {
            URL(fileURLWithPath: "/Volumes/Disk/c\($0)/App.app", isDirectory: true)
        }
        let lines = DragonUninstaller.duplicateCopyList(many).split(separator: "\n")
        #expect(lines.count == 100)
        #expect(lines.first == "/Volumes/Disk/c0/App.app")
        #expect(lines.last == "/Volumes/Disk/c99/App.app")
    }

    /// The bound is the point. An unbounded NSAlert measured 1640pt for 42 paths and 3496pt for
    /// 100 — taller than the display, buttons off screen, unusable exactly when it matters.
    @Test func theListHeightIsBoundedNoMatterHowManyCopies() {
        let two = DragonUninstaller.duplicateCopyListHeight(lineCount: 2)
        let fortyTwo = DragonUninstaller.duplicateCopyListHeight(lineCount: 42)
        let hundred = DragonUninstaller.duplicateCopyListHeight(lineCount: 100)

        #expect(two < fortyTwo, "a short list should not get a mostly-empty box")
        #expect(fortyTwo == hundred, "past the bound the height stops growing")
        #expect(hundred <= 150)
        // Comfortably inside any display, with room left for the alert's own text and buttons.
        #expect(hundred < 400)
    }

    /// Zero is not a case the alert reaches — `.duplicateCopies` is only produced with at least
    /// two — but the height must still be a sane box rather than nothing.
    @Test func anEmptyListStillHasAUsableHeight() {
        #expect(DragonUninstaller.duplicateCopyListHeight(lineCount: 0) >= 34)
    }
}

/// The assembled accessory, not just the numbers behind it.
@Suite struct UninstallBlockedAccessoryTests {
    @MainActor @Test func aHundredCopiesStillProduceABoundedSelectableScrollingList() throws {
        let many = (0..<100).map {
            URL(fileURLWithPath: "/Volumes/Disk/copy\($0)/App.app", isDirectory: true)
        }
        let accessory = DragonUninstaller.duplicateCopyAccessory(many)

        // The alert grows to fit its accessory, so this frame is what keeps it on screen.
        #expect(accessory.frame.height <= 150)
        #expect(accessory.hasVerticalScroller, "the overflow has to be reachable")

        let textView = try #require(accessory.documentView as? NSTextView)
        #expect(textView.isSelectable, "the actionable step is moving one of these; let it be copied")
        #expect(!textView.isEditable)
        // Bounded presentation, not a truncated list: every path is still in there.
        #expect(textView.string.split(separator: "\n").count == 100)
        #expect(textView.string.contains("/Volumes/Disk/copy99/App.app"))
    }

    /// Two copies is the ordinary case and must not render as a mostly-empty box.
    @MainActor @Test func theOrdinaryTwoCopyCaseIsCompact() {
        let accessory = DragonUninstaller.duplicateCopyAccessory([installed, localBuild])
        #expect(accessory.frame.height < 150)
    }
}

/// The format contract of the blocked-duplicates message, in every shipped locale.
///
/// The message took two arguments until the path list moved into a scrollable accessory; the
/// trailing `%2$@` was then removed from all seven files. Nothing committed protected the new
/// one-argument shape, and the failure it guards against is silent in the worst way: `String`
/// formatting with a specifier that has no matching argument does not throw, it renders garbage
/// or drops the text, and only in the locale that still carries the stale specifier — so it
/// would ship to exactly the users least able to report it.
@Suite struct BlockedDuplicatesFormatTests {
    private static let key = "DragonKit.uninstall.blockedDuplicatesMessage"
    private static let languages = DragonLanguage.selectable.compactMap(\.localeCode)

    /// Same loading path as `LocalizationTests.allLanguagesDefineTheSameKeys`, so this reads the
    /// shipped `.strings` rather than whatever the test host's language happens to be.
    @MainActor private func message(_ language: String) throws -> String {
        let bundle = try #require(
            LocalizationManager.lprojBundle(language, in: .module),
            "missing \(language).lproj"
        )
        let url = try #require(bundle.url(forResource: "DragonKit", withExtension: "strings"))
        let dict = try #require(NSDictionary(contentsOf: url) as? [String: String])
        return try #require(dict[Self.key], "\(language) is missing \(Self.key)")
    }

    /// The one shape this message is allowed to have: a single positional object argument.
    private static let permitted = ["%1$@"]

    /// Every printf conversion directive in `format`, in the order they appear, with `%%`
    /// escapes consumed rather than reported.
    ///
    /// A scanner rather than a set of `contains` checks, because the checks this replaced were a
    /// deny-list: they rejected `%2$@` and a bare `%@` and silently accepted everything else, so
    /// `%2$d` passed. Enumerating what *is* there and comparing against the permitted multiset
    /// cannot have that hole — anything unlisted fails by default.
    ///
    /// A malformed trailing `%` is reported as `"%"` rather than skipped, so it fails the
    /// contract instead of looking like a string with no directives at all.
    static func conversionDirectives(in format: String) -> [String] {
        let characters = Array(format)
        var directives: [String] = []
        var index = 0

        while index < characters.count {
            guard characters[index] == "%" else {
                index += 1
                continue
            }
            var cursor = index + 1
            guard cursor < characters.count else {
                directives.append("%")
                break
            }
            // `%%` is a literal percent, not a directive.
            if characters[cursor] == "%" {
                index = cursor + 1
                continue
            }
            // Argument position, only when the digits are actually followed by `$` — otherwise
            // they are a field width and the width loop below consumes them.
            var lookahead = cursor
            while lookahead < characters.count, characters[lookahead].isNumber { lookahead += 1 }
            if lookahead > cursor, lookahead < characters.count, characters[lookahead] == "$" {
                cursor = lookahead + 1
            }
            while cursor < characters.count, "-+ #0'".contains(characters[cursor]) { cursor += 1 }
            while cursor < characters.count, characters[cursor].isNumber { cursor += 1 }
            if cursor < characters.count, characters[cursor] == "." {
                cursor += 1
                while cursor < characters.count, characters[cursor].isNumber { cursor += 1 }
            }
            while cursor < characters.count, "hlLqjzt".contains(characters[cursor]) { cursor += 1 }

            guard cursor < characters.count else {
                directives.append(String(characters[index...]))
                break
            }
            directives.append(String(characters[index...cursor]))
            index = cursor + 1
        }

        return directives
    }

    @MainActor @Test func everyLocaleDeclaresExactlyTheOnePermittedDirective() throws {
        for language in Self.languages {
            let found = Self.conversionDirectives(in: try message(language)).sorted()
            #expect(
                found == Self.permitted,
                "\(language): directives were \(found), expected exactly \(Self.permitted)"
            )
        }
    }

    @MainActor @Test func everyLocaleRendersCleanlyWithOneAppName() throws {
        let appName = "Dragon Sample App"
        for language in Self.languages {
            let format = try message(language)

            // Validated *before* formatting, and with `#require` so a violation stops this test
            // rather than continuing. `String(format:)` with a directive that has no matching
            // argument reads whatever is next in the argument list and can crash Foundation, so
            // this test must never hand it a string it has not first checked — it cannot rely on
            // the contract test above having run, since the two may execute concurrently.
            let found = Self.conversionDirectives(in: format).sorted()
            try #require(found == Self.permitted, "\(language): refusing to format \(found)")

            let rendered = String(format: format, appName)
            #expect(rendered.contains(appName), "\(language): the app name did not land")
            #expect(!rendered.isEmpty)

            // Checked as literal text, NOT by re-scanning. Rendered output is plain text, not a
            // format string, and `conversionDirectives` is a printf parser: given the perfectly
            // legitimate source `100%% certain, %1$@` it renders `100% certain, …`, in which the
            // parser then reads `% c` — space flag, `c` conversion — as a directive and fails a
            // string that is entirely correct. Feeding output back through an input parser is the
            // bug; looking for the specifier's own spelling is what this ever meant to check.
            for specifier in ["%1$@", "%2$@", "%@"] {
                #expect(
                    !rendered.contains(specifier),
                    "\(language): \(specifier) was not consumed by formatting"
                )
            }
        }
    }

    // MARK: - The scanner itself

    /// The deny-list this replaced passed a mutation that inserted `%2$d`. These are the cases it
    /// missed, asserted directly against the scanner so the contract above cannot regress into
    /// another list of things someone happened to think of.
    @Test func theScannerReportsEveryUnintendedDirective() {
        let scan = BlockedDuplicatesFormatTests.conversionDirectives(in:)

        #expect(scan("Nothing was removed. %1$@ then %2$d") == ["%1$@", "%2$d"])
        #expect(scan("%3$s") == ["%3$s"])
        #expect(scan("%p") == ["%p"])
        #expect(scan("%2$@") == ["%2$@"])
        #expect(scan("%@ and %@") == ["%@", "%@"], "a repeated bare directive is two directives")
        #expect(scan("%1$@") == ["%1$@"])
        #expect(scan("%-8.3f") == ["%-8.3f"], "flags, width and precision belong to one directive")
        #expect(scan("%lld") == ["%lld"], "so do length modifiers")
        #expect(scan("nothing here at all").isEmpty)
    }

    /// `%%` is a literal percent and must not be mistaken for a directive — otherwise a
    /// translation that legitimately writes "100%%" could never satisfy the contract.
    @Test func escapedPercentsAreLiteralsNotDirectives() {
        let scan = BlockedDuplicatesFormatTests.conversionDirectives(in:)

        #expect(scan("100%% certain").isEmpty)
        #expect(scan("100%% certain, %1$@") == ["%1$@"])
        #expect(scan("%%%1$@") == ["%1$@"], "an escape immediately before a directive")
        #expect(scan("%%%%") .isEmpty, "two escapes, no directives")
        #expect(scan("trailing %") == ["%"], "a lone trailing % is malformed, not absent")
    }

    /// `%%` end to end: accepted by the contract, and rendered as one literal percent.
    ///
    /// The scanner's `%%` support was previously only half true. It correctly declined to report
    /// `%%` as a directive, so a translation containing `100%%` passed the contract — and then the
    /// render test re-scanned the *output* and choked on it, so the support did not actually work
    /// end to end. Both halves are asserted here.
    @Test func anEscapedPercentIsAcceptedAndRendersAsOneLiteralPercent() {
        let format = "100%% certain, %1$@"

        #expect(
            BlockedDuplicatesFormatTests.conversionDirectives(in: format).sorted()
                == BlockedDuplicatesFormatTests.permitted,
            "an escaped percent must not count against the one-directive contract"
        )
        #expect(String(format: format, "Dragon Sample App") == "100% certain, Dragon Sample App")
    }

    /// Why rendered output is never fed back through the scanner, pinned so nobody reintroduces
    /// it: in plain text a literal percent followed by a space and a letter is indistinguishable
    /// from a directive to any printf parser, and this one duly reads `% c`.
    @Test func renderedTextMustNotBeReparsedAsAFormatString() {
        let rendered = String(format: "100%% certain, %1$@", "Dragon Sample App")

        #expect(rendered == "100% certain, Dragon Sample App")
        #expect(
            BlockedDuplicatesFormatTests.conversionDirectives(in: rendered) == ["% c"],
            "this is exactly the false positive that makes re-scanning output wrong"
        )
    }

    /// The mutation the reviewer used, asserted as a permanent guard: a stray directive fails the
    /// contract even though it is neither `%2$@` nor a bare `%@`, which is exactly what the
    /// previous check let through.
    @Test func aStrayDirectiveFailsTheContract() {
        let mutated = "Nothing was removed. More than one copy of %1$@ is installed. %2$d"
        let found = BlockedDuplicatesFormatTests.conversionDirectives(in: mutated).sorted()

        #expect(found == ["%1$@", "%2$d"])
        #expect(found != BlockedDuplicatesFormatTests.permitted, "the contract must reject this")
    }
}

/// The not-removable refusal, in every shipped locale: its format contract, and how it is put
/// together.
///
/// The Homebrew route is its own key, appended only when the configuration names a cask, rather than
/// a second copy of the whole message: the paragraph is the part that varies, and two near-identical
/// messages in seven languages is fourteen strings waiting to drift apart.
@Suite struct BlockedNotRemovableFormatTests {
    private static let languages = DragonLanguage.selectable.compactMap(\.localeCode)
    private static let titleKey = "DragonKit.uninstall.blockedNotRemovableTitle"
    private static let messageKey = "DragonKit.uninstall.blockedNotRemovableMessage"
    private static let homebrewKey = "DragonKit.uninstall.blockedNotRemovableHomebrew"

    /// Each key and the exact multiset of directives it may carry — an allow-list, for the reason
    /// ``BlockedDuplicatesFormatTests`` gives: anything unlisted fails by default.
    private static let contract: [String: [String]] = [
        titleKey: [],
        messageKey: ["%1$@", "%2$@"],
        homebrewKey: ["%1$@"],
    ]

    /// Same loading path as ``BlockedDuplicatesFormatTests``, so this reads the shipped `.strings`
    /// rather than whatever the test host's language happens to be.
    @MainActor private func string(_ key: String, _ language: String) throws -> String {
        let bundle = try #require(
            LocalizationManager.lprojBundle(language, in: .module),
            "missing \(language).lproj"
        )
        let url = try #require(bundle.url(forResource: "DragonKit", withExtension: "strings"))
        let dict = try #require(NSDictionary(contentsOf: url) as? [String: String])
        return try #require(dict[key], "\(language) is missing \(key)")
    }

    private static func directives(_ format: String) -> [String] {
        BlockedDuplicatesFormatTests.conversionDirectives(in: format).sorted()
    }

    @MainActor @Test func everyLocaleCarriesExactlyThePermittedDirectives() throws {
        for language in Self.languages {
            for (key, permitted) in Self.contract {
                let found = Self.directives(try string(key, language))
                #expect(found == permitted, "\(language) \(key): directives were \(found), expected \(permitted)")
            }
        }
    }

    @MainActor @Test func everyLocaleRendersTheAppAndWhereItIsInstalled() throws {
        let appName = "Dragon Sample App"
        let location = "/Library/Input Methods/Dragon Sample App.app"
        for language in Self.languages {
            let format = try string(Self.messageKey, language)
            // Validated before formatting, and never assumed from the contract test above, which
            // may run concurrently: a directive with no matching argument reads past the end.
            try #require(Self.directives(format) == ["%1$@", "%2$@"], "\(language): refusing to format")

            let rendered = String(format: format, appName, location)
            #expect(rendered.contains(appName), "\(language): the app name did not land")
            #expect(rendered.contains(location), "\(language): the location did not land")
            for specifier in ["%1$@", "%2$@", "%@"] {
                #expect(!rendered.contains(specifier), "\(language): \(specifier) was not consumed")
            }
        }
    }

    /// The command is the one part of the paragraph that must not be translated: it is typed into
    /// Terminal as it stands.
    @MainActor @Test func everyLocaleKeepsTheHomebrewCommandVerbatim() throws {
        for language in Self.languages {
            let format = try string(Self.homebrewKey, language)
            try #require(Self.directives(format) == ["%1$@"], "\(language): refusing to format")

            let rendered = String(format: format, "dragon-sample-app")
            #expect(
                rendered.contains("brew uninstall --cask dragon-sample-app"),
                "\(language): the command did not survive translation verbatim"
            )
            #expect(!rendered.contains("%"), "\(language): a specifier was not consumed")
        }
    }

    /// The brew route is offered only when the configuration names a cask. A debug build never
    /// does: ``UninstallConfig/caskToken(_:ifBundleIs:actual:)`` withholds the token from it,
    /// because `brew uninstall --cask` would delete the installed release rather than the build
    /// that is asking — so this refusal cannot tell a debug build to do that either.
    @MainActor @Test func theHomebrewRouteIsOfferedOnlyWithACask() {
        let location = DragonUninstaller.displayPath(installedForAllUsers)

        let withCask = DragonUninstaller.notRemovableMessage(
            appName: "Dragon Sample App", bundle: installedForAllUsers, homebrewCask: "dragon-sample-app"
        )
        #expect(withCask.contains(location))
        #expect(withCask.contains("brew uninstall --cask dragon-sample-app"))

        for cask in [nil, ""] as [String?] {
            let without = DragonUninstaller.notRemovableMessage(
                appName: "Dragon Sample App", bundle: installedForAllUsers, homebrewCask: cask
            )
            #expect(without.contains(location))
            #expect(!without.contains("brew"), "no cask, no brew route (cask: \(String(describing: cask)))")
        }
    }
}
