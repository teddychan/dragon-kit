import Testing
import Foundation
@testable import DragonKit

// Regression tests for the two ways DragonKit used to destroy settings without saying so:
// a settings blob that no longer strictly decodes, and a backup file that no longer parses.
// Both failures were swallowed and both ended with the user's real values gone.

@Suite struct SettingsStoreMigrationTests {
    /// The sample app's settings as shipped.
    private struct SettingsV1: Codable, Equatable, Sendable {
        var launchAtLogin = false
        var showInMenuBar = true
    }

    /// The same settings one release later, with a single field added — the whole incident.
    private struct SettingsV2: Codable, Equatable, Sendable {
        var launchAtLogin = false
        var showInMenuBar = true
        var playSound = false
    }

    private struct NestedV1: Codable, Equatable, Sendable {
        struct Window: Codable, Equatable, Sendable {
            var pinned = false
        }
        var window = Window()
        var theme = "dark"
    }

    private struct NestedV2: Codable, Equatable, Sendable {
        struct Window: Codable, Equatable, Sendable {
            var pinned = false
            var opacity = 0.5
        }
        var window = Window()
        var theme = "dark"
        var badgeCount = 0
    }

    private func makeSuite() -> String { "test.dragonkit.migrate.\(UUID().uuidString)" }

    @Test func addingAFieldKeepsTheUsersStoredSettings() throws {
        let suite = makeSuite()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))

        // The user, on the shipped version, turns launch-at-login on and the menu bar off.
        let v1 = DragonSettingsStore(suiteName: suite, defaultValue: SettingsV1())
        v1.save(SettingsV1(launchAtLogin: true, showInMenuBar: false))

        // The update adds `playSound`. Strict decoding of the stored blob throws
        // keyNotFound("playSound") — synthesized Decodable ignores property defaults — and that
        // throw is what used to be swallowed into a full reset.
        let stored = try #require(defaults.data(forKey: "settings.v1"))
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SettingsV2.self, from: stored)
        }

        let loaded = DragonSettingsStore(suiteName: suite, defaultValue: SettingsV2()).load()
        #expect(loaded.launchAtLogin == true)   // the user's choice survives the upgrade
        #expect(loaded.showInMenuBar == false)  // …and so does this one
        #expect(loaded.playSound == false)      // the new field takes its default
    }

    @Test func addingAFieldInsideANestedStructAlsoKeepsTheStoredValues() {
        let suite = makeSuite()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let v1 = DragonSettingsStore(suiteName: suite, defaultValue: NestedV1())
        v1.save(NestedV1(window: .init(pinned: true), theme: "light"))

        // `opacity` is added one level down: a shallow merge would keep the old `window` object
        // wholesale and still fail to decode.
        let loaded = DragonSettingsStore(suiteName: suite, defaultValue: NestedV2()).load()
        #expect(loaded.window.pinned == true)
        #expect(loaded.window.opacity == 0.5)
        #expect(loaded.theme == "light")
        #expect(loaded.badgeCount == 0)
    }

    @Test func undecodableBlobFallsBackToDefaultsAndPreservesTheRawBytes() throws {
        let suite = makeSuite()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))

        let garbage = Data("this was never JSON".utf8)
        defaults.set(garbage, forKey: "settings.v1")

        let store = DragonSettingsStore(suiteName: suite, defaultValue: SettingsV2())
        #expect(store.load() == SettingsV2())
        #expect(defaults.data(forKey: "settings.v1.unreadable") == garbage)

        // A later corrupt write must not clobber the copy that is actually worth rescuing.
        defaults.set(Data("still not JSON".utf8), forKey: "settings.v1")
        _ = store.load()
        #expect(defaults.data(forKey: "settings.v1.unreadable") == garbage)
    }

    @Test func aRealTypeChangeIsPreservedRatherThanMigrated() throws {
        let suite = makeSuite()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))

        // Valid JSON, right key, wrong type: merging it over the defaults still won't decode.
        // That is the line between "a field was added" and "the shape changed".
        let blob = Data(#"{"launchAtLogin":"yes","showInMenuBar":true}"#.utf8)
        defaults.set(blob, forKey: "settings.v1")

        let store = DragonSettingsStore(suiteName: suite, defaultValue: SettingsV2())
        #expect(store.load() == SettingsV2())
        #expect(defaults.data(forKey: "settings.v1.unreadable") == blob)
    }
}

@Suite struct BackupPayloadValidationTests {
    private func makeSuite() -> String { "test.dragonkit.restore.\(UUID().uuidString)" }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "dragonkit-restore-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func deserializeRejectsAPayloadWithNoSchemaVersion() throws {
        // A perfectly valid property list that is not a backup. It used to default to version 0
        // and sail through.
        let data = try DragonBackup.serialize(["defaults": ["a": 1]])
        #expect(throws: DragonBackup.BackupError.malformed) {
            _ = try DragonBackup.deserialize(data)
        }
    }

    @Test func deserializeRejectsAPayloadWithNoDefaults() throws {
        let data = try DragonBackup.serialize(["schemaVersion": DragonBackup.schemaVersion])
        #expect(throws: DragonBackup.BackupError.malformed) {
            _ = try DragonBackup.deserialize(data)
        }
    }

    @Test func failedRestoreLeavesTheTargetSuiteUntouched() throws {
        let suite = makeSuite()
        let folder = tempFolder()
        let defaults = UserDefaults.standard
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.setPersistentDomain(["keep": 1, "also": "yes"], forName: suite)

        // The exact shape that used to wipe the suite: a readable plist carrying neither key,
        // so validation passed and `apply` replaced the domain with `[:]`.
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "not-a-backup.dragonbackup")
        try DragonBackup.serialize(["unrelated": 1]).write(to: url)

        #expect(throws: DragonBackup.BackupError.malformed) {
            try DragonBackup.restore(from: url, suiteName: suite)
        }
        let after = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(after["keep"] as? Int == 1)
        #expect(after["also"] as? String == "yes")
    }

    @Test func restoreRejectsABackupTakenFromADifferentSuite() throws {
        let source = makeSuite()
        let target = makeSuite()
        let folder = tempFolder()
        let defaults = UserDefaults.standard
        defer {
            defaults.removePersistentDomain(forName: source)
            defaults.removePersistentDomain(forName: target)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.setPersistentDomain(["from": "source"], forName: source)
        defaults.setPersistentDomain(["from": "target"], forName: target)

        let url = try DragonBackup.writeBackup(
            suiteName: source,
            appName: "T",
            to: folder,
            appVersion: "1",
            date: Date(timeIntervalSince1970: 1_700_000_000)
        )

        #expect(throws: DragonBackup.BackupError.suiteMismatch(expected: target, found: source)) {
            try DragonBackup.restore(from: url, suiteName: target)
        }
        // …and, again, nothing was overwritten on the way to the error.
        #expect(defaults.persistentDomain(forName: target)?["from"] as? String == "target")
    }
}

@Suite struct BackupChangeDetectionTests {
    private func makeSuite() -> String { "test.dragonkit.changed.\(UUID().uuidString)" }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "dragonkit-changed-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func newestMatchingBackupIsNilWhenTheFolderHasNoBackups() {
        let suite = makeSuite()
        let folder = tempFolder()
        let defaults = UserDefaults.standard
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.setPersistentDomain(["v": 1], forName: suite)

        #expect(DragonBackup.newestMatchingBackup(suiteName: suite, in: folder) == nil)
    }

    @Test func backingUpTwiceWithNothingChangedWritesOnlyOneFile() throws {
        let suite = makeSuite()
        let folder = tempFolder()
        let defaults = UserDefaults.standard
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.setPersistentDomain(["v": 1, "name": "before"], forName: suite)

        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let first = try DragonBackup.writeBackupIfChanged(
            suiteName: suite, appName: "T", to: folder, appVersion: "1", date: start
        )
        guard case .written(let firstURL) = first else {
            Issue.record("the first manual backup must be written, got \(first)")
            return
        }
        #expect(firstURL.lastPathComponent == DragonBackup.fileName(appName: "T", for: start))

        // Later date *and* a different app version: metadata always differs between two backups,
        // so only the stored defaults may drive the decision.
        let second = try DragonBackup.writeBackupIfChanged(
            suiteName: suite, appName: "T", to: folder, appVersion: "2",
            date: start.addingTimeInterval(60)
        )
        // `.unchanged` carries the file `listBackups` found, and FileManager hands those back with
        // symlinks resolved (/var → /private/var), so compare filenames rather than whole URLs.
        guard case .unchanged(let matched) = second else {
            Issue.record("an unchanged suite must not write a second backup, got \(second)")
            return
        }
        #expect(matched.lastPathComponent == firstURL.lastPathComponent)
        #expect(DragonBackup.listBackups(in: folder).count == 1)

        // Mutate the suite and the same call writes again.
        defaults.setPersistentDomain(["v": 1, "name": "after"], forName: suite)
        let later = start.addingTimeInterval(120)
        let third = try DragonBackup.writeBackupIfChanged(
            suiteName: suite, appName: "T", to: folder, appVersion: "2", date: later
        )
        guard case .written(let thirdURL) = third else {
            Issue.record("a mutated suite must write a fresh backup, got \(third)")
            return
        }
        #expect(thirdURL.lastPathComponent == DragonBackup.fileName(appName: "T", for: later))
        #expect(DragonBackup.listBackups(in: folder).count == 2)
    }
}
