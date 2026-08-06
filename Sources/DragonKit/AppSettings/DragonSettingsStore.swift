import Foundation
import OSLog

/// Logging for ``DragonSettingsStore``. Lives outside the generic type because a generic
/// struct cannot hold a static stored property, and the `Logger` should be built once rather
/// than on every error path.
private enum SettingsStoreLog {
    static let logger = Logger(subsystem: "com.dragonapp.DragonKit", category: "DragonSettingsStore")
}

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

    /// Where a blob that could not be decoded *or* migrated is parked so the reset is
    /// recoverable by hand. It sits in the settings suite, so ``DragonBackup`` carries the
    /// rescue copy into backups alongside the settings it belongs to.
    private var unreadableKey: String { "\(key).unreadable" }

    /// The stored value — migrated forward when the app's settings type has gained fields
    /// since the blob was written — or `defaultValue` when nothing readable is stored.
    ///
    /// The strict decode on its own was silent data loss. Swift's synthesized `Decodable`
    /// does **not** fall back to a property's default for a missing key: decoding
    /// `{"launchAtLogin":true,"showInMenuBar":false}` into a struct that has since gained
    /// `var playSound = false` throws `keyNotFound("playSound")`. `try?` swallowed that,
    /// `load()` returned `defaultValue`, and the app's model then wrote those defaults back
    /// over the user's real settings on the first `didSet`. So adding one field to a settings
    /// struct — the single most ordinary change an app makes, and exactly the shape of the
    /// sample app's `SampleSettings` — reset every preference on upgrade with no error and no
    /// recovery, and because ``DragonBackup`` snapshots this same suite the next backup
    /// captured the reset values too.
    public func load() -> Value {
        let defaults = self.defaults
        guard let data = defaults.data(forKey: key) else { return defaultValue }
        if let decoded = try? JSONDecoder().decode(Value.self, from: data) { return decoded }
        if let migrated = Self.migrate(data, onto: defaultValue) { return migrated }

        // A genuine type change or a corrupt blob: neither shape can be reconciled, so the
        // reset is unavoidable — but the bytes are not thrown away. Only the first such blob
        // is kept; a later corrupt write must not clobber the copy worth rescuing.
        if defaults.object(forKey: unreadableKey) == nil {
            defaults.set(data, forKey: unreadableKey)
        }
        SettingsStoreLog.logger.error(
            """
            Settings under "\(self.key, privacy: .public)" could not be decoded or migrated; \
            returning defaults. Raw bytes preserved under "\(self.unreadableKey, privacy: .public)".
            """
        )
        return defaultValue
    }

    /// Encode and persist `value`.
    public func save(_ value: Value) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            // Was a bare `try?` + `return`: an encode failure dropped the write with no trace,
            // so the app believed it had saved and the next `load()` handed back stale values.
            // The value itself is never logged — these are the user's settings.
            SettingsStoreLog.logger.error(
                """
                Encoding settings for "\(self.key, privacy: .public)" failed, write dropped: \
                \(error.localizedDescription, privacy: .public)
                """
            )
        }
    }

    /// Reconcile an older blob with the current shape: JSON-merge the stored object *over* the
    /// JSON encoding of `defaultValue`, then decode the result. Keys present in the stored blob
    /// win; keys the app has added since take their default — the semantics apps already assume
    /// their property initializers give them. Returns `nil` when the blob isn't a JSON object
    /// (including when `Value` doesn't encode to one) or when the merge still doesn't decode,
    /// which is the signature of a real type change rather than an added field.
    private static func migrate(_ data: Data, onto defaultValue: Value) -> Value? {
        guard let storedObject = try? JSONSerialization.jsonObject(with: data),
              let stored = storedObject as? [String: Any],
              let defaultData = try? JSONEncoder().encode(defaultValue),
              let defaultObject = try? JSONSerialization.jsonObject(with: defaultData),
              let base = defaultObject as? [String: Any]
        else { return nil }

        let merged = deepMerging(base, with: stored)
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: mergedData)
    }

    /// Overlay `overlay` onto `base`, recursing into nested objects — an app whose settings
    /// contain a nested struct hits the missing-key bug one level down, and a shallow merge
    /// would replace the whole nested object with the older one and lose its new fields.
    /// Arrays and scalars are replaced wholesale: a stored array is the user's list, not a
    /// patch to merge element-wise.
    private static func deepMerging(_ base: [String: Any], with overlay: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in overlay {
            if let nestedOverlay = value as? [String: Any],
               let nestedBase = result[key] as? [String: Any] {
                result[key] = deepMerging(nestedBase, with: nestedOverlay)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
