import Foundation
import Testing
@testable import DragonKitUpdates

/// Thin on purpose: this is the struct whose values went missing when `DragonUpdater` passed
/// `nil` for Sparkle's user-driver delegate. ice-2 lost its gentle reminders and its own
/// "update available" notification, and its notification subsystem quietly became dead code —
/// so the defaults and the round-trip are worth pinning.
@Suite struct DragonUpdaterConfigTests {
    @Test func defaultsAreOffAndUnhooked() {
        let config = DragonUpdaterConfig()
        #expect(config.usesGentleScheduledReminders == false)
        #expect(config.onUpdateFoundInBackground == nil)
    }

    @MainActor
    @Test func storesBothValues() {
        let box = FiredFlag()
        let config = DragonUpdaterConfig(
            usesGentleScheduledReminders: true,
            onUpdateFoundInBackground: { box.fired = true }
        )
        #expect(config.usesGentleScheduledReminders == true)

        config.onUpdateFoundInBackground?()
        #expect(box.fired, "the handler that survived must be the one that was supplied")
    }

    @MainActor
    @Test func valuesSurviveMutationAfterInit() {
        // `DragonUpdater` reads the config at Sparkle-init time, not at `init`, so a config
        // built and then adjusted must still carry both values.
        var config = DragonUpdaterConfig()
        let box = FiredFlag()
        config.usesGentleScheduledReminders = true
        config.onUpdateFoundInBackground = { box.fired = true }

        #expect(config.usesGentleScheduledReminders == true)
        config.onUpdateFoundInBackground?()
        #expect(box.fired)
    }
}

/// `onUpdateFoundInBackground` is `@MainActor @Sendable`, so it can't capture a local `var` —
/// a main-actor reference type is the simplest thing it can write through.
@MainActor
private final class FiredFlag {
    var fired = false
}
