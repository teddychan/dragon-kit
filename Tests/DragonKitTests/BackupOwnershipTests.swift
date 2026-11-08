import Foundation
import Testing
import DragonKit

private final class BackupMemoryDefaults: UserDefaults, @unchecked Sendable {
    private var domains: [String: [String: Any]] = [:]

    override func persistentDomain(forName name: String) -> [String: Any]? { domains[name] }
    override func setPersistentDomain(_ domain: [String: Any], forName name: String) { domains[name] = domain }
}

@Suite struct BackupOwnershipTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: "DragonBackupOwnership-\(UUID().uuidString)")
    }

    @Test func anotherSuitesSnapshotDoesNotSuppressThisSuitesBackup() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = BackupMemoryDefaults()
        defaults.setPersistentDomain(["value": 1], forName: "first")
        defaults.setPersistentDomain(["value": 1], forName: "second")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try DragonBackup.writeBackup(
            suiteName: "first", appName: "First", to: directory, defaults: defaults,
            appVersion: "1", date: date)
        let outcome = try DragonBackup.writeBackupIfChanged(
            suiteName: "second", appName: "Second", to: directory, defaults: defaults,
            appVersion: "1", date: date.addingTimeInterval(1))
        guard case .written(let second) = outcome else {
            Issue.record("A different suite must get its own restorable snapshot, got \(outcome)")
            return
        }
        defaults.setPersistentDomain(["value": 2], forName: "second")
        try DragonBackup.restore(from: second, suiteName: "second", defaults: defaults)
        #expect(defaults.persistentDomain(forName: "second")?["value"] as? Int == 1)
    }

    @Test func legacyRetentionRefusesToGuessOwnershipInASharedFolder() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = BackupMemoryDefaults()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try DragonBackup.writeBackup(
            suiteName: "first", appName: "First", to: directory, defaults: defaults,
            appVersion: "1", date: date)
        let second = try DragonBackup.writeBackup(
            suiteName: "second", appName: "Second", to: directory, defaults: defaults,
            appVersion: "1", date: date.addingTimeInterval(1))
        let legacyPrune: (URL, Int) -> Void = DragonBackup.prune(in:keeping:)
        legacyPrune(directory, 1)
        #expect(FileManager.default.fileExists(atPath: first.path))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func legacySnapshotsRemainVisibleAndRestorableWithoutBeingOwned() throws {
        let directory = folder()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = BackupMemoryDefaults()
        defaults.setPersistentDomain(["value": 1], forName: "target")
        let legacy = directory.appending(path: "legacy.dragonbackup")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let payload: [String: Any] = ["schemaVersion": 1, "createdDate": date, "defaults": ["value": 1]]
        let original = try DragonBackup.serialize(payload)
        try original.write(to: legacy)
        let legacyList: (URL) -> [URL] = DragonBackup.listBackups(in:)
        #expect(legacyList(directory).map(\.lastPathComponent) == ["legacy.dragonbackup"])
        #expect(DragonBackup.listBackups(in: directory, suiteName: "target").map(\.lastPathComponent) == ["legacy.dragonbackup"])
        #expect(DragonBackup.newestMatchingBackup(suiteName: "target", defaults: defaults, in: directory) == nil)
        _ = try DragonBackup.writeBackupIfChanged(
            suiteName: "target", appName: "Target", to: directory, defaults: defaults,
            appVersion: "1", date: date.addingTimeInterval(1))
        DragonBackup.prune(in: directory, keeping: 0, suiteName: "target")
        #expect(try Data(contentsOf: legacy) == original)
        defaults.setPersistentDomain(["value": 2], forName: "target")
        try DragonBackup.restore(from: legacy, suiteName: "target", defaults: defaults)
        #expect(defaults.persistentDomain(forName: "target")?["value"] as? Int == 1)
    }

    @Test func retentionPreservesUndatedOwnedSnapshotsAndOrdersByPayloadDate() throws {
        let directory = folder()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = BackupMemoryDefaults()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let older = try DragonBackup.writeBackup(
            suiteName: "target", appName: "Z Previous Name", to: directory,
            defaults: defaults, appVersion: "1", date: date)
        let newer = try DragonBackup.writeBackup(
            suiteName: "target", appName: "A New Name", to: directory,
            defaults: defaults, appVersion: "1", date: date.addingTimeInterval(1))
        let undated = directory.appending(path: "undated.dragonbackup")
        try DragonBackup.serialize(["schemaVersion": 1, "suiteName": "target", "defaults": [String: String]()]).write(to: undated)
        #expect(DragonBackup.listBackups(in: directory, suiteName: "target").first?.lastPathComponent == newer.lastPathComponent)
        DragonBackup.prune(in: directory, keeping: 1, suiteName: "target")
        #expect(!FileManager.default.fileExists(atPath: older.path))
        #expect(FileManager.default.fileExists(atPath: newer.path))
        #expect(FileManager.default.fileExists(atPath: undated.path))
    }

    @Test func changedSnapshotsWithinOneSecondRemainIndependentlyRestorable() throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = BackupMemoryDefaults()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.setPersistentDomain(["value": 1], forName: "target")
        let first = try DragonBackup.writeBackup(
            suiteName: "target", appName: "Target", to: directory, defaults: defaults,
            appVersion: "1", date: date)
        defaults.setPersistentDomain(["value": 2], forName: "target")
        let outcome = try DragonBackup.writeBackupIfChanged(
            suiteName: "target", appName: "Target", to: directory, defaults: defaults,
            appVersion: "1", date: date.addingTimeInterval(0.2))
        guard case .written(let second) = outcome else {
            Issue.record("A changed snapshot must be written")
            return
        }
        #expect(first != second)
        #expect(DragonBackup.listBackups(in: directory, suiteName: "target").count == 2)
        try DragonBackup.restore(from: first, suiteName: "target", defaults: defaults)
        #expect(defaults.persistentDomain(forName: "target")?["value"] as? Int == 1)
        try DragonBackup.restore(from: second, suiteName: "target", defaults: defaults)
        #expect(defaults.persistentDomain(forName: "target")?["value"] as? Int == 2)
    }

    @Test func concurrentWritesDoNotReplaceAnExistingSnapshot() async throws {
        let directory = folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let urls = try await withThrowingTaskGroup(of: URL.self) { group in
            for index in 0..<8 {
                group.addTask {
                    let defaults = BackupMemoryDefaults()
                    defaults.setPersistentDomain(["value": index], forName: "target")
                    return try DragonBackup.writeBackup(
                        suiteName: "target", appName: "Target", to: directory,
                        defaults: defaults, appVersion: "1", date: date)
                }
            }
            var result: [URL] = []
            for try await url in group { result.append(url) }
            return result
        }
        #expect(Set(urls).count == 8)
        let values = try urls.map { url in
            let payload = try DragonBackup.deserialize(Data(contentsOf: url))
            return (payload["defaults"] as? [String: Int])?["value"]
        }
        #expect(Set(values.compactMap { $0 }) == Set(0..<8))
    }
}
