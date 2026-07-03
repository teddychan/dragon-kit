import Foundation

/// Persists an app-defined `Codable` settings value as JSON under one key in a named
/// UserDefaults suite. Generalized from ice-2's `SettingsStore`: the value type is
/// supplied by the app, so each app stores its own settings shape while sharing the same
/// persistence path — and the same suite is what ``DragonBackup`` snapshots.
public struct DragonSettingsStore<Value: Codable & Sendable>: Sendable {
    private let suiteName: String
    private let key: String
    private let defaultValue: Value

    public init(suiteName: String, defaultValue: Value, key: String = "settings.v1") {
        self.suiteName = suiteName
        self.defaultValue = defaultValue
        self.key = key
    }

    private var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// The stored value, or `defaultValue` when nothing valid is stored yet.
    public func load() -> Value {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Value.self, from: data)
        else { return defaultValue }
        return decoded
    }

    /// Encode and persist `value` (silently no-ops if encoding fails).
    public func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
