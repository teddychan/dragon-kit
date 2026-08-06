import Foundation
import OSLog

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

    private static let logger = Logger(subsystem: "com.dragonapp.DragonKit", category: "DragonBackup")

    public enum BackupError: Error, Equatable {
        case malformed
        case unsupportedVersion(Int)
        /// The file was taken from a different UserDefaults suite than the one being restored onto.
        case suiteMismatch(expected: String, found: String)
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
    ///
    /// Invariant: the payload must carry `defaults`. ``deserialize(_:)`` now guarantees that,
    /// so nothing on the restore path can reach here without it. The guard below is the
    /// belt-and-braces for direct callers, and it no-ops instead of writing `[:]`: the old
    /// `?? [:]` turned any payload missing the key into a *wipe* of the suite, which is the
    /// opposite of what the user asked for when they hit Restore.
    public static func apply(
        _ payload: [String: Any],
        suiteName: String,
        defaults: UserDefaults = .standard
    ) {
        guard let stored = payload[PayloadKey.defaults] as? [String: Any] else {
            logger.error("Refusing to apply a payload with no \"defaults\" — it would erase the suite.")
            return
        }
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

    /// Parse a backup file's data and validate that it is actually a backup: both
    /// `schemaVersion` and `defaults` must be present and of the right type.
    ///
    /// `schemaVersion` deliberately has no `?? 0` fallback any more. With it, *any* valid
    /// property list passed validation — including one carrying neither key — and `apply`
    /// then replaced the suite with the missing `defaults`, i.e. erased it. The user asked to
    /// restore their settings, got them wiped, and the pane's `relaunch()` fired as though the
    /// restore had succeeded because nothing threw.
    public static func deserialize(_ data: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let payload = object as? [String: Any] else {
            throw BackupError.malformed
        }
        guard let version = payload[PayloadKey.schemaVersion] as? Int else {
            throw BackupError.malformed
        }
        // Version before contents: a file from a future schema gets the specific error, since we
        // can't judge the shape of its `defaults` anyway.
        guard version <= schemaVersion else {
            throw BackupError.unsupportedVersion(version)
        }
        guard payload[PayloadKey.defaults] is [String: Any] else {
            throw BackupError.malformed
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

    /// The outcome of ``writeBackupIfChanged(suiteName:appName:to:defaults:appVersion:date:)``.
    public enum BackupOutcome: Sendable, Equatable {
        /// A new backup was written at this URL.
        case written(URL)
        /// Nothing changed since this existing backup, so no file was written.
        case unchanged(URL)
    }

    /// The newest backup in `folder` whose stored defaults already match `suiteName`'s current
    /// contents, or `nil` when the suite has changed (or no backup exists yet).
    ///
    /// Only the metadata-free `defaults` payload is compared: `createdDate` and `appVersion`
    /// differ on every write, so comparing whole payloads would report "changed" every time and
    /// defeat the check entirely. Only the single newest file is inspected — an older matching
    /// backup is not the one the user would be told about, and reading the whole folder to find
    /// it would cost a full re-read on every "Back up now".
    public static func newestMatchingBackup(
        suiteName: String,
        defaults: UserDefaults = .standard,
        in folder: URL
    ) -> URL? {
        guard let newest = listBackups(in: folder).first,
              let data = try? Data(contentsOf: newest),
              let payload = try? deserialize(data),
              let stored = payload[PayloadKey.defaults] as? [String: Any]
        else { return nil }
        let current = defaults.persistentDomain(forName: suiteName) ?? [:]
        // `[String: Any]` has no `==`; NSDictionary's comparison handles the plist value types
        // (Data/Date/NSNumber) that a defaults domain is actually made of.
        return NSDictionary(dictionary: stored).isEqual(to: current) ? newest : nil
    }

    /// Write a backup only if the suite differs from the newest existing backup.
    ///
    /// Backing up by hand when nothing has changed produced a duplicate file, and ten of those
    /// pushed the last genuinely different snapshot out of the retention window. Callers report
    /// ``BackupOutcome/unchanged(_:)`` to the user rather than silently doing nothing.
    /// ``writeBackup(suiteName:appName:to:defaults:appVersion:date:)`` stays unconditional for
    /// callers that want a file no matter what.
    @discardableResult
    public static func writeBackupIfChanged(
        suiteName: String,
        appName: String,
        to folder: URL,
        defaults: UserDefaults = .standard,
        appVersion: String,
        date: Date
    ) throws -> BackupOutcome {
        if let match = newestMatchingBackup(suiteName: suiteName, defaults: defaults, in: folder) {
            return .unchanged(match)
        }
        return .written(
            try writeBackup(
                suiteName: suiteName,
                appName: appName,
                to: folder,
                defaults: defaults,
                appVersion: appVersion,
                date: date
            )
        )
    }

    /// Restore the backup at `url` onto `suiteName`. Throws on a malformed or too-new file, or
    /// on one taken from a different suite; the caller is responsible for relaunching afterwards.
    public static func restore(
        from url: URL,
        suiteName: String,
        defaults: UserDefaults = .standard
    ) throws {
        let data = try Data(contentsOf: url)
        let payload = try deserialize(data)
        // `apply` is a replace, so restoring one app's file onto another app's suite doesn't
        // merge — it erases the target. A payload that records no suite at all can't be proven
        // to mismatch, so it still goes through; only a recorded name that disagrees is refused.
        if let recorded = payload[PayloadKey.suiteName] as? String, recorded != suiteName {
            throw BackupError.suiteMismatch(expected: suiteName, found: recorded)
        }
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
