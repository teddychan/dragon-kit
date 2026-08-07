import Foundation
import Sparkle
import Testing
@testable import DragonKitUpdates

/// Guards the one thing that decides whether the "no update found" alert may be reworded to
/// "<App> is up to date". Getting this wrong is silent and user-visible: an Intel Mac or an
/// out-of-support macOS would be told it is current while an update it can't install exists.
@Suite struct NoUpdateFoundAlertTests {
    /// Shaped like the error Sparkle hands the user driver: the reason rides in `userInfo`
    /// under `SPUNoUpdateFoundReasonKey` as an `NSNumber`, not in the error code.
    private func noUpdateError(reason: SPUNoUpdateFoundReason?) -> NSError {
        var userInfo: [String: Any] = [:]
        if let reason { userInfo[SPUNoUpdateFoundReasonKey] = NSNumber(value: reason.rawValue) }
        return NSError(domain: SUSparkleErrorDomain, code: 1001, userInfo: userInfo)
    }

    @Test(arguments: [
        SPUNoUpdateFoundReason.systemIsTooOld,
        SPUNoUpdateFoundReason.systemIsTooNew,
        SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64,
    ])
    func defersToSparkleWhenAnUpdateExistsButCannotBeInstalledHere(
        reason: SPUNoUpdateFoundReason
    ) {
        #expect(NoUpdateFoundAlert.shouldDeferToSparkle(error: noUpdateError(reason: reason)))
    }

    @Test(arguments: [
        SPUNoUpdateFoundReason.unknown,
        SPUNoUpdateFoundReason.onLatestVersion,
        SPUNoUpdateFoundReason.onNewerThanLatestVersion,
    ])
    func rewordsWhenTheUserIsGenuinelyUpToDate(reason: SPUNoUpdateFoundReason) {
        #expect(!NoUpdateFoundAlert.shouldDeferToSparkle(error: noUpdateError(reason: reason)))
    }

    @Test func rewordsWhenNoReasonIsSupplied() {
        // Sparkle only started attaching a reason in 2.x; an error without one means "nothing
        // newer", so the DragonKit wording still applies.
        #expect(!NoUpdateFoundAlert.shouldDeferToSparkle(error: noUpdateError(reason: nil)))
    }

    @Test func rewordsWhenTheReasonIsNotANumber() {
        // Defensive: a malformed userInfo must not be read as "blocked" — falling back to the
        // reworded alert is the same outcome as an absent key.
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: 1001,
            userInfo: [SPUNoUpdateFoundReasonKey: "systemIsTooOld"]
        )
        #expect(!NoUpdateFoundAlert.shouldDeferToSparkle(error: error))
    }
}
