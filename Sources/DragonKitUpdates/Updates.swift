import DragonKit
import Foundation
import Sparkle
import SwiftUI

/// Thin wrapper around Sparkle's `SPUStandardUpdaterController`. The controller is created
/// lazily on first use — never at launch — because Sparkle touches the app bundle/XPC
/// services on init, which an ad-hoc dev build may not embed; deferring keeps launch safe.
/// Ported from ice-2's `UpdatesController`, extended to expose the settings the pane binds.
@MainActor
public final class DragonUpdater: ObservableObject {
    private var controller: SPUStandardUpdaterController?

    public init() {}

    private var updater: SPUUpdater? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        if controller == nil {
            controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        }
        return controller?.updater
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
