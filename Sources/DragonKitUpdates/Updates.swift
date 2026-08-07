import AppKit
import DragonKit
import Foundation
import Sparkle
import SwiftUI

/// Sparkle's standard user driver with one change: the "no update found" alert is reworded to
/// `<App> is up to date` / `v<version> is currently the newest version available.`, matching
/// DragonKit's About wording. Sparkle's own copy for this alert lives in the Sparkle framework
/// bundle and can't be overridden from the app, so we replace just this one alert and forward
/// everything else to `SPUStandardUserDriver`.
private final class DragonUpdaterUserDriver: SPUStandardUserDriver {
    override func showUpdateNotFoundWithError(_ error: any Error) async {
        if NoUpdateFoundAlert.shouldDeferToSparkle(error: error) {
            await super.showUpdateNotFoundWithError(error)
            return
        }

        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        let alert = NSAlert()
        alert.messageText = "\(appName) is up to date"
        alert.informativeText = "v\(short) is currently the newest version available."
        alert.addButton(withTitle: "OK")
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        alert.runModal()
    }
}

/// The one decision inside ``DragonUpdaterUserDriver/showUpdateNotFoundWithError(_:)`` that is
/// pure logic, split out so it can be tested — the override itself needs a live Sparkle session,
/// and this module (the one that broke ice-2 twice) otherwise had no test at all.
enum NoUpdateFoundAlert {
    /// Whether Sparkle's own "no update" message must be shown unchanged.
    ///
    /// Sparkle reports "no update" both when we're genuinely on the latest version and when an
    /// update exists but can't be installed here (OS too old/new, non-ARM64 Mac). Only the
    /// former may be reworded to "<App> is up to date"; saying that for the latter would be a
    /// lie, so those defer to Sparkle's accurate message.
    static func shouldDeferToSparkle(error: any Error) -> Bool {
        let blockedReasons: Set<Int32> = [
            SPUNoUpdateFoundReason.systemIsTooOld.rawValue,
            SPUNoUpdateFoundReason.systemIsTooNew.rawValue,
            SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64.rawValue,
        ]
        let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        guard let reason else { return false }
        return blockedReasons.contains(reason)
    }
}

/// How an app wants scheduled (non-user-initiated) update checks to behave.
///
/// Both settings live on Sparkle's *user driver* delegate, which ``DragonUpdater`` used to pass
/// as `nil` — so an app adopting the kit silently lost them. ice-2 hit exactly that when it
/// migrated off its own Sparkle wiring: its gentle reminders and its own "update available"
/// notification both stopped, and the notification subsystem became dead code.
public struct DragonUpdaterConfig: Sendable {
    /// Opt into Sparkle's non-intrusive reminders for scheduled checks, instead of a modal
    /// window arriving unprompted.
    public var usesGentleScheduledReminders: Bool

    /// Called when a *scheduled* check finds an update the user didn't ask for, so the app can
    /// post its own notification. Sparkle still shows its standard window and activates the
    /// app, so no update is ever lost by ignoring this.
    public var onUpdateFoundInBackground: (@MainActor @Sendable () -> Void)?

    public init(
        usesGentleScheduledReminders: Bool = false,
        onUpdateFoundInBackground: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.usesGentleScheduledReminders = usesGentleScheduledReminders
        self.onUpdateFoundInBackground = onUpdateFoundInBackground
    }
}

/// Bridges ``DragonUpdaterConfig`` onto Sparkle's `SPUStandardUserDriverDelegate`, which is an
/// `@objc` protocol and so needs an `NSObject` subclass.
private final class DragonUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    // Stored as separate values rather than holding the config: Sparkle calls these methods
    // from a non-isolated context, so reaching through `self` inside `assumeIsolated` would be
    // a data race. A `@Sendable` closure copied into a local is safe to hop with.
    private let gentleReminders: Bool
    private let onUpdateFoundInBackground: (@MainActor @Sendable () -> Void)?

    init(config: DragonUpdaterConfig) {
        self.gentleReminders = config.usesGentleScheduledReminders
        self.onUpdateFoundInBackground = config.onUpdateFoundInBackground
        super.init()
    }

    var supportsGentleScheduledUpdateReminders: Bool { gentleReminders }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // Only for checks the user didn't initiate — a user who just clicked "Check for
        // Updates…" is already looking at the result and doesn't need a notification.
        guard !state.userInitiated else { return }
        guard let handler = onUpdateFoundInBackground else { return }
        // Sparkle calls this on the main thread; assert that rather than hopping, so the
        // notification fires before its window appears.
        MainActor.assumeIsolated { handler() }
    }
}

/// Thin wrapper around a Sparkle `SPUUpdater`. The updater is created lazily on first use —
/// never at launch — because Sparkle touches the app bundle/XPC services on init, which an
/// ad-hoc dev build may not embed; deferring keeps launch safe. Ported from ice-2's
/// `UpdatesController`, extended to expose the settings the pane binds and to reskin the
/// "no update found" alert via ``DragonUpdaterUserDriver``.
@MainActor
public final class DragonUpdater: ObservableObject {
    private var updaterInstance: SPUUpdater?
    private var userDriver: DragonUpdaterUserDriver?
    private let config: DragonUpdaterConfig
    /// Retained for the updater's lifetime — Sparkle holds the delegate weakly.
    private var driverDelegate: DragonUserDriverDelegate?
    /// Retained so the KVO registration lives as long as the updater does; releasing it
    /// invalidates the observation.
    private var lastCheckObservation: NSKeyValueObservation?

    public init(config: DragonUpdaterConfig = DragonUpdaterConfig()) {
        self.config = config
    }

    /// Force Sparkle to initialize and begin its scheduled-check timer. Without this the
    /// updater only wakes on first property access, so an app that never reads one would never
    /// schedule a background check — apps previously had to poke `canCheckForUpdates` to get
    /// the same effect. Safe and idempotent; no-ops when Sparkle can't initialize.
    public func start() {
        _ = updater
    }

    private var updater: SPUUpdater? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        if updaterInstance == nil {
            let delegate = DragonUserDriverDelegate(config: config)
            let driver = DragonUpdaterUserDriver(hostBundle: .main, delegate: delegate)
            let instance = SPUUpdater(
                hostBundle: .main,
                applicationBundle: .main,
                userDriver: driver,
                delegate: nil
            )
            do {
                try instance.start()
                userDriver = driver
                driverDelegate = delegate
                updaterInstance = instance
                observeLastUpdateCheckDate(of: instance)
            } catch {
                return nil
            }
        }
        return updaterInstance
    }

    /// Republish when Sparkle stamps `lastUpdateCheckDate`, which it does *after* a check
    /// finishes — the pane's "Last checked: …" used to keep showing the previous value, because
    /// the only `objectWillChange` fired synchronously when the check *started*.
    /// `SPUUpdater` posts manual KVO notifications for this property (`willChangeValueForKey` in
    /// its `updateLastUpdateCheckDate`), so `.prior` gives us a real "will change" edge.
    private func observeLastUpdateCheckDate(of instance: SPUUpdater) {
        lastCheckObservation = instance
            .observe(\.lastUpdateCheckDate, options: [.prior]) { [weak self] _, change in
                guard change.isPrior else { return }
                // Sparkle stamps this on the main thread (SPUUpdater is main-thread-only by
                // contract), so assert the isolation rather than hopping and publishing late.
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
    }

    /// Whether an update check can currently run.
    public var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? false }

    /// When the last update check completed, if ever.
    public var lastUpdateCheckDate: Date? { updater?.lastUpdateCheckDate }

    public var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set {
            // Before the mutation, not after: the contract is "will change", so a subscriber
            // that reads the value on notification must still see the old one.
            objectWillChange.send()
            updater?.automaticallyChecksForUpdates = newValue
        }
    }

    public var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            updater?.automaticallyDownloadsUpdates = newValue
        }
    }

    /// Check for updates now, presenting Sparkle's standard UI. Safe to call even if Sparkle
    /// can't initialize (missing bundle id) — it simply no-ops.
    public func checkForUpdates() {
        // Before the call: it flips `canCheckForUpdates` synchronously, which disables the
        // pane's button. The refresh once the check *finishes* comes from the KVO observation.
        objectWillChange.send()
        updater?.checkForUpdates()
    }
}

/// Updates pane: auto-check / auto-download toggles, a "Check for Updates…" button, and the
/// last-checked time. Ported from ice-2's `UpdatesSettingsPane`.
public struct UpdatesSettingsPane: SettingsPane {
    public let id = "updates"
    public let title = "DragonKit.pane.updates"
    public let systemImage = "arrow.down.circle"
    private let updater: DragonUpdater

    public init(updater: DragonUpdater) { self.updater = updater }

    public var paneBody: some View { UpdatesPaneView(updater: updater) }
}

private struct UpdatesPaneView: View {
    @ObservedObject var updater: DragonUpdater

    var body: some View {
        DragonForm {
            DragonSection {
                Toggle(L("DragonKit.updates.autoCheck"), isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                Toggle(L("DragonKit.updates.autoDownload"), isOn: Binding(
                    get: { updater.automaticallyDownloadsUpdates },
                    set: { updater.automaticallyDownloadsUpdates = $0 }
                ))
            }
            DragonSection {
                LabeledContent {
                    Button(L("DragonKit.updates.checkNow")) { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("DragonKit.updates.checkNowTitle"))
                        Text(lastCheckedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var lastCheckedText: String {
        let prefix = L("DragonKit.updates.lastChecked")
        if let date = updater.lastUpdateCheckDate {
            return "\(prefix): \(date.formatted(date: .abbreviated, time: .standard))"
        }
        return "\(prefix): \(L("DragonKit.updates.never"))"
    }
}
