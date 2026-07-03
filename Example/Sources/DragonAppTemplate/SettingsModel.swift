import Foundation
import DragonKit

/// The sample app's persisted settings. A plain `Codable` value — the shape is the app's,
/// not DragonKit's. Because it lives in a named UserDefaults suite via ``DragonSettingsStore``,
/// Backup & Restore can snapshot and restore it wholesale.
struct SampleSettings: Codable, Sendable, Equatable {
    var launchAtLogin = false
    var showInMenuBar = true
    var playSound = false
}

extension Notification.Name {
    /// Posted (with a `Bool` object) when "Show in menu bar" changes, so the AppDelegate can
    /// show/hide the status item.
    static let sampleShowInMenuBarChanged = Notification.Name("sampleShowInMenuBarChanged")
}

/// Observable bridge between the settings UI and persistence. Each setter persists via the
/// store and applies its side effect (login item registration, menu-bar visibility).
@MainActor
@Observable
final class SettingsModel {
    /// A dedicated suite (distinct from the app's bundle-id domain) so a backup captures only
    /// app settings — not the backup pane's own preferences.
    static let suiteName = (Bundle.main.bundleIdentifier ?? "com.dragonapp.dragonkit-sample") + ".settings"

    private let store: DragonSettingsStore<SampleSettings>
    private var settings: SampleSettings {
        didSet { store.save(settings) }
    }

    init() {
        let store = DragonSettingsStore(suiteName: Self.suiteName, defaultValue: SampleSettings())
        self.store = store
        self.settings = store.load()
        // Reconcile the OS login-item state with the persisted preference on launch.
        LoginItem.setEnabled(settings.launchAtLogin)
    }

    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set {
            settings.launchAtLogin = newValue
            LoginItem.setEnabled(newValue)
        }
    }

    var showInMenuBar: Bool {
        get { settings.showInMenuBar }
        set {
            settings.showInMenuBar = newValue
            NotificationCenter.default.post(name: .sampleShowInMenuBarChanged, object: newValue)
        }
    }

    var playSound: Bool {
        get { settings.playSound }
        set { settings.playSound = newValue }
    }
}
