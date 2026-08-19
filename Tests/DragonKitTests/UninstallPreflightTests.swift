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
            canonicalize: world([:])
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
            preflight: { .duplicateCopies([installed, localBuild]) },
            reportBlocked: { reported = $0 },
            setLoginItemEnabled: { loginItemWrites.append($0) }
        )

        #expect(reported == .duplicateCopies([installed, localBuild]))
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
            canonicalize: world([installed: installed, localBuild: localBuild])
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
                canonicalize: DragonUninstaller.canonicalBundleURL
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
                canonicalize: DragonUninstaller.canonicalBundleURL
            )
            guard case .duplicateCopies(let urls) = decision else {
                Issue.record("expected a block, got \(decision)")
                return
            }
            #expect(urls.count == 2)
        }
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
