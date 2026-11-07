import Foundation
import Testing
@testable import DragonKit

@MainActor
@Suite struct BackupOperationsTests {
    @Test func existingHostsStillBackUpRestoreAndDeleteTheirSettingsSuite() async throws {
        let suite = "DragonKit.BackupOperationsTests.\(UUID().uuidString)"
        let defaults = UserDefaults.standard
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.setPersistentDomain(["language": "fr", "enabled": false], forName: suite)
        let config = BackupConfig(appName: "Host", suiteName: suite, appVersion: "1.0.0", relaunch: {})
        let operations = config.resolvedOperations
        #expect(try await operations.backUp(folder))
        #expect(try await !operations.backUp(folder))
        let entry = try #require(try await operations.listBackups(folder).first)
        #expect(entry.url.pathExtension == "dragonbackup")
        #expect(entry.title == entry.url.lastPathComponent)
        defaults.setPersistentDomain(["language": "ja", "newValue": true], forName: suite)
        try await operations.restore(entry.url, folder)
        let restored = try #require(defaults.persistentDomain(forName: suite))
        #expect(restored["language"] as? String == "fr")
        #expect(restored["enabled"] as? Bool == false)
        #expect(restored["newValue"] == nil)
        try await operations.delete(entry.url, folder)
        #expect(try await operations.listBackups(folder).isEmpty)
    }

    @Test func customSnapshotsKeepTheirFileFormatAndRestoreTheirData() async throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "existing.clipbackup")
        var current = Data("snippets and settings".utf8)
        let config = BackupConfig(
            appName: "Host", suiteName: "unused", appVersion: "1.0.0",
            operations: BackupOperations(
                listBackups: { directory in
                    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                        .map { BackupEntry(url: $0, title: "Saved snippets", detail: "3 snippets") }
                },
                backUp: { directory in
                    let url = directory.appending(path: "existing.clipbackup")
                    if (try? Data(contentsOf: url)) == current { return false }
                    try current.write(to: url, options: .atomic)
                    return true
                },
                restore: { url, _ in current = try Data(contentsOf: url) },
                delete: { url, _ in try FileManager.default.removeItem(at: url) }),
            folderPathKey: "backupFolderPath", folderBookmarkKey: "backupFolderBookmark",
            restoreConfirmationMessage: "A safety backup is saved first.",
            relaunch: {})
        let operations = config.resolvedOperations
        #expect(try await operations.backUp(folder))
        #expect(try await !operations.backUp(folder))
        let entries = try await operations.listBackups(folder)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.url.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
        #expect(entry.title == "Saved snippets")
        #expect(entry.detail == "3 snippets")
        current = Data("later edits".utf8)
        try await operations.restore(file, folder)
        #expect(current == Data("snippets and settings".utf8))
        try await operations.delete(file, folder)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(config.folderPathKey == "backupFolderPath")
        #expect(config.folderBookmarkKey == "backupFolderBookmark")
        #expect(config.restoreConfirmationMessage == "A safety backup is saved first.")
    }

    @Test func customOperationFailuresPropagateToThePane() async throws {
        enum Failure: Error { case unavailable }
        let config = BackupConfig(
            appName: "Host", suiteName: "unused", appVersion: "1.0.0",
            operations: BackupOperations(
                listBackups: { _ in throw Failure.unavailable },
                backUp: { _ in throw Failure.unavailable },
                restore: { _, _ in throw Failure.unavailable },
                delete: { _, _ in throw Failure.unavailable }),
            relaunch: {})
        let folder = FileManager.default.temporaryDirectory
        await #expect(throws: Failure.unavailable) { try await config.resolvedOperations.listBackups(folder) }
        await #expect(throws: Failure.unavailable) { try await config.resolvedOperations.backUp(folder) }
        await #expect(throws: Failure.unavailable) { try await config.resolvedOperations.restore(folder, folder) }
        await #expect(throws: Failure.unavailable) { try await config.resolvedOperations.delete(folder, folder) }
    }

    @Test func folderKeysKeepTheExistingNamesByDefault() {
        let config = BackupConfig(appName: "Host", suiteName: "host.settings", appVersion: "1.0.0", relaunch: {})
        #expect(config.folderPathKey == "DragonKit.backup.folderPath.host.settings")
        #expect(config.folderBookmarkKey == "DragonKit.backup.folderBookmark.host.settings")
    }
}
