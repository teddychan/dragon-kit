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
        // Sparkle reports "no update" both when we're genuinely on the latest version and when
        // an update exists but can't be installed here (OS too old/new, non-ARM64 Mac). Only
        // reword the former; defer to Sparkle's accurate message for the latter.
        let blockedReasons: Set<Int32> = [
            SPUNoUpdateFoundReason.systemIsTooOld.rawValue,
            SPUNoUpdateFoundReason.systemIsTooNew.rawValue,
            SPUNoUpdateFoundReason.hardwareDoesNotSupportARM64.rawValue,
        ]
        let reason = ((error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        if let reason, blockedReasons.contains(reason) {
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

/// Thin wrapper around a Sparkle `SPUUpdater`. The updater is created lazily on first use —
/// never at launch — because Sparkle touches the app bundle/XPC services on init, which an
/// ad-hoc dev build may not embed; deferring keeps launch safe. Ported from ice-2's
/// `UpdatesController`, extended to expose the settings the pane binds and to reskin the
/// "no update found" alert via ``DragonUpdaterUserDriver``.
@MainActor
public final class DragonUpdater: ObservableObject {
    private var updaterInstance: SPUUpdater?
    private var userDriver: DragonUpdaterUserDriver?

    public init() {}

    private var updater: SPUUpdater? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        if updaterInstance == nil {
            let driver = DragonUpdaterUserDriver(hostBundle: .main, delegate: nil)
            let instance = SPUUpdater(
                hostBundle: .main,
                applicationBundle: .main,
                userDriver: driver,
                delegate: nil
            )
            do {
                try instance.start()
                userDriver = driver
                updaterInstance = instance
            } catch {
                return nil
            }
        }
        return updaterInstance
    }

    /// Whether an update check can currently run.
    public var canCheckForUpdates: Bool { updater?.canCheckForUpdates ?? false }

    /// When the last update check completed, if ever.
    public var lastUpdateCheckDate: Date? { updater?.lastUpdateCheckDate }

    public var automaticallyChecksForUpdates: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set {
            updater?.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    public var automaticallyDownloadsUpdates: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set {
            updater?.automaticallyDownloadsUpdates = newValue
            objectWillChange.send()
        }
    }

    /// Check for updates now, presenting Sparkle's standard UI. Safe to call even if Sparkle
    /// can't initialize (missing bundle id) — it simply no-ops.
    public func checkForUpdates() {
        updater?.checkForUpdates()
        objectWillChange.send()
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
