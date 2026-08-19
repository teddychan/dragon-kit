import Foundation
import Testing
@testable import DragonKitUpdates

/// A Debug build must never reach Sparkle at all.
///
/// The bug these pin: all five hosts' debug scripts delete `SUFeedURL` and claimed that stopped
/// `SPUUpdater.start()`, leaving the Updates pane inert. It never did — `startUpdater:` passes
/// `requireFeedURL:NO`, and has since Sparkle 2.0.0 — so the pane's button stayed live and
/// pressing it raised Sparkle's raw developer error instead of doing nothing visible.
///
/// Only the disallowed side is testable here. The allowed side would construct a real
/// `SPUUpdater` against the test runner's bundle, which is not an app and cannot start one.
@Suite struct DragonUpdaterDebugBuildTests {
    @MainActor
    @Test func disallowedBuildNeverExposesAnUpdater() {
        let updater = DragonUpdater(config: DragonUpdaterConfig(), updatingIsAllowed: false)

        #expect(updater.updatingIsAvailable == false, "the pane disables its whole form on this")
        #expect(updater.canCheckForUpdates == false, "the button is disabled on this")
        #expect(updater.lastUpdateCheckDate == nil)
        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(updater.automaticallyDownloadsUpdates == false)
    }

    @MainActor
    @Test func disallowedBuildIgnoresEveryRouteIntoSparkle() {
        let updater = DragonUpdater(config: DragonUpdaterConfig(), updatingIsAllowed: false)

        // `start()` is the launch-time route and `checkForUpdates()` the menu-item route; both
        // must no-op rather than trap, since an app calls them without knowing the channel.
        updater.start()
        updater.checkForUpdates()
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true

        #expect(updater.updatingIsAvailable == false)
        #expect(
            updater.automaticallyChecksForUpdates == false,
            "a write with no updater behind it must not appear to have taken"
        )
        #expect(updater.automaticallyDownloadsUpdates == false)
        #expect(updater.lastUpdateCheckDate == nil, "no check ran, so nothing stamped a date")
    }
}

/// The production expression that decides the gate, which the suite above steps over.
///
/// Those tests inject `updatingIsAllowed` directly. That proves the downstream guard and nothing
/// about how the value is chosen — so deleting or flipping the `!` in the public initializer,
/// shipping Sparkle to every Debug build or killing updates in every release, would have kept
/// every one of them green.
@Suite struct DragonUpdaterPolicyTests {
    @Test func aDebugBuildIsNotAllowedToUpdate() {
        #expect(DragonUpdater.updatingIsAllowed(inDebugBuild: true) == false)
    }

    @Test func anythingElseIsAllowedToUpdate() {
        #expect(DragonUpdater.updatingIsAllowed(inDebugBuild: false) == true)
    }
}
