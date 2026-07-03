import Foundation

/// Folder-based backup & restore of an app's settings. Generalized from ice-2's
/// `SettingsBackup`: instead of a fixed key enum it snapshots a whole UserDefaults *suite*
/// (persistent domain), so any app that keeps its settings in a named suite (see
/// ``DragonSettingsStore``) gets backup/restore for free. Every function is pure /
/// injectable — it takes the suite name, folder URL, and date — so it runs without the app.
public enum DragonBackup {
    /// Bumped only if the on-disk format changes incompatibly.
    public static let schemaVersion = 1
    /// File extension for backup files.
    public static let fileExtension = "dragonbackup"
    /// The newest backups to retain by default.
    public static let defaultRetentionLimit = 10

    public enum BackupError: Error, Equatable {
        case malformed
        case unsupportedVersion(Int)
    }

    private enum PayloadKey {
        static let schemaVersion = "schemaVersion"
        static let appVersion = "appVersion"
        static let createdDate = "createdDate"
        static let suiteName = "suiteName"
        static let defaults = "defaults"
    }

    // MARK: - Snapshot / apply (pure)

    /// Build a backup payload from the current contents of `suiteName`'s persistent domain.
    public static func makePayload(
        suiteName: String,
        defaults: UserDefaults = .standard,
        appVersion: String,
        createdDate: Date
    ) -> [String: Any] {
        let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
        return [
            PayloadKey.schemaVersion: schemaVersion,
            PayloadKey.appVersion: appVersion,
            PayloadKey.createdDate: createdDate,
            PayloadKey.suiteName: suiteName,
            PayloadKey.defaults: domain,
        ]
    }

    /// Replace the suite's contents with the payload's stored values — a replace, not a
    /// merge — so a restore reproduces the backup exactly. Other defaults domains are
    /// untouched.
    public static func apply(
        _ payload: [String: Any],
        suiteName: String,
        defaults: UserDefaults = .standard
    ) {
        let stored = payload[PayloadKey.defaults] as? [String: Any] ?? [:]
        defaults.setPersistentDomain(stored, forName: suiteName)
    }

    /// The date a payload was created, if present.
    public static func createdDate(of payload: [String: Any]) -> Date? {
        payload[PayloadKey.createdDate] as? Date
    }

    /// The app version recorded in a payload, if present.
    public static func appVersion(of payload: [String: Any]) -> String? {
        payload[PayloadKey.appVersion] as? String
    }

    // MARK: - Serialize (pure)

    public static func serialize(_ payload: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
    }

    /// Parse a backup file's data and validate its schema version.
    public static func deserialize(_ data: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let payload = object as? [String: Any] else {
            throw BackupError.malformed
        }
        let version = payload[PayloadKey.schemaVersion] as? Int ?? 0
        guard version <= schemaVersion else {
            throw BackupError.unsupportedVersion(version)
        }
        return payload
    }

    // MARK: - Files & retention

    /// Default backup folder when the user hasn't chosen one: `~/Documents/<App> Backups`.
    public static func defaultFolder(
        appName: String,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appending(path: "Documents/\(appName) Backups", directoryHint: .isDirectory)
    }

    /// A lexically-sortable timestamp, e.g. "2026-07-03-014500".
    public static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    /// Backup filename for a date, e.g. "MyApp-Settings-2026-07-03-014500.dragonbackup".
    public static func fileName(appName: String, for date: Date) -> String {
        "\(appName)-Settings-\(timestamp(date)).\(fileExtension)"
    }

    /// Write a backup of `suiteName` into `folder` (created if needed); returns the file URL.
    @discardableResult
    public static func writeBackup(
        suiteName: String,
        appName: String,
        to folder: URL,
        defaults: UserDefaults = .standard,
        appVersion: String,
        date: Date
    ) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let payload = makePayload(suiteName: suiteName, defaults: defaults, appVersion: appVersion, createdDate: date)
        let data = try serialize(payload)
        let url = folder.appending(path: fileName(appName: appName, for: date))
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Restore the backup at `url` onto `suiteName`. Throws on a malformed or too-new file;
    /// the caller is responsible for relaunching afterwards.
    public static func restore(
        from url: URL,
        suiteName: String,
        defaults: UserDefaults = .standard
    ) throws {
        let data = try Data(contentsOf: url)
        let payload = try deserialize(data)
        apply(payload, suiteName: suiteName, defaults: defaults)
    }

    /// Existing backup files in `folder`, newest first (filenames sort chronologically).
    public static func listBackups(in folder: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Delete the oldest backups beyond `max`, keeping the newest `max`.
    public static func prune(in folder: URL, keeping max: Int) {
        let all = listBackups(in: folder)
        guard all.count > max else { return }
        for url in all[max...] {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
