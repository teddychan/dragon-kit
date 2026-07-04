import Testing
import Foundation
@testable import DragonKit

@Suite struct DragonSettingsStoreTests {
    struct Demo: Codable, Equatable, Sendable {
        var a = 0
        var b = "x"
    }

    @Test func returnsDefaultWhenEmptyThenRoundTrips() {
        let suite = "test.dragonkit.store.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let store = DragonSettingsStore(suiteName: suite, defaultValue: Demo())
        #expect(store.load() == Demo())

        store.save(Demo(a: 42, b: "hello"))
        #expect(store.load() == Demo(a: 42, b: "hello"))
    }
}

@Suite struct DragonBackupTests {
    private func makeSuite() -> String { "test.dragonkit.backup.\(UUID().uuidString)" }

    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "dragonkit-backup-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    @Test func restoreReplacesRatherThanMerges() {
        let suite = makeSuite()
        let defaults = UserDefaults.standard
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.setPersistentDomain(["keep": 1, "drop": 2], forName: suite)
        let payload = DragonBackup.makePayload(suiteName: suite, appVersion: "1.0", createdDate: Date())

        // Mutate after the snapshot: change a value, add a new key.
        defaults.setPersistentDomain(["keep": 99, "new": 3], forName: suite)
        DragonBackup.apply(payload, suiteName: suite)

        let restored = defaults.persistentDomain(forName: suite) ?? [:]
        #expect(restored["keep"] as? Int == 1)
        #expect(restored["drop"] as? Int == 2)
        #expect(restored["new"] == nil) // replace, not merge
    }

    @Test func serializeRoundTripsMetadata() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = DragonBackup.makePayload(suiteName: "x", appVersion: "2.3", createdDate: date)
        let data = try DragonBackup.serialize(payload)
        let back = try DragonBackup.deserialize(data)
        #expect(DragonBackup.appVersion(of: back) == "2.3")
        #expect(DragonBackup.createdDate(of: back) == date)
    }

    @Test func rejectsNewerSchema() throws {
        let data = try DragonBackup.serialize(["schemaVersion": DragonBackup.schemaVersion + 1])
        #expect(throws: DragonBackup.BackupError.self) {
            _ = try DragonBackup.deserialize(data)
        }
    }

    @Test func writeListAndPruneKeepsNewest() throws {
        let suite = makeSuite()
        let folder = tempFolder()
        let defaults = UserDefaults.standard
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.setPersistentDomain(["v": 1], forName: suite)

        for i in 0..<12 {
            let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(i))
            try DragonBackup.writeBackup(suiteName: suite, appName: "T", to: folder, appVersion: "1", date: date)
        }
        #expect(DragonBackup.listBackups(in: folder).count == 12)

        DragonBackup.prune(in: folder, keeping: 10)
        #expect(DragonBackup.listBackups(in: folder).count == 10)
    }
}

@Suite struct DragonPermissionTests {
    @MainActor @Test func reflectsCheckAndRequestability() {
        var granted = false
        let p = DragonPermission(id: "t", title: "Test", check: { granted }, request: nil)
        #expect(p.isGranted == false)
        #expect(p.canRequest == false)

        granted = true
        #expect(p.isGranted == true)

        let q = DragonPermission(id: "u", title: "U", check: { true }, request: {})
        #expect(q.canRequest == true)
    }

    @MainActor @Test func accessibilityFactoryIsConfigured() {
        let p = DragonPermission.accessibility()
        #expect(p.id == "accessibility")
        #expect(p.isRequired == true)
        #expect(p.canRequest == true)
    }
}

@Suite struct DragonUninstallerTests {
    @MainActor @Test func leftoverPathsCoverBundleAndSuites() {
        let library = URL(fileURLWithPath: "/Users/x/Library", isDirectory: true)
        let paths = DragonUninstaller.leftoverPaths(
            bundleID: "com.acme.app",
            suiteNames: ["com.acme.app.settings"],
            library: library
        ).map(\.path)

        #expect(paths.contains { $0.hasSuffix("Preferences/com.acme.app.plist") })
        // The settings-suite plist must be targeted too (regression: it was previously missed).
        #expect(paths.contains { $0.hasSuffix("Preferences/com.acme.app.settings.plist") })
        #expect(paths.contains { $0.hasSuffix("Saved Application State/com.acme.app.savedState") })
    }

    @MainActor @Test func cleanupPathsIncludeOptionalDataOnlyWhenChosen() {
        let support = URL(fileURLWithPath: "/Users/x/Library/Application Support/Acme", isDirectory: true)
        let caches = URL(fileURLWithPath: "/Users/x/Library/Caches/com.acme.app", isDirectory: true)
        let config = UninstallConfig(
            appName: "Acme",
            bundleID: "com.acme.app",
            checklistItems: ["x"],
            optionalDataToggle: (label: "Also delete data", paths: [support]),
            extraCleanupPaths: [caches]
        )

        #expect(DragonUninstaller.cleanupPaths(config: config, deleteOptionalData: false) == [caches])
        #expect(DragonUninstaller.cleanupPaths(config: config, deleteOptionalData: true) == [caches, support])
    }

    @MainActor @Test func configDefaultsToNoExtraCleanup() {
        let config = UninstallConfig(appName: "Acme", checklistItems: ["x"])
        #expect(config.optionalDataToggle == nil)
        #expect(config.extraCleanupPaths.isEmpty)
        // With nothing configured, even the opt-in deletes nothing extra.
        #expect(DragonUninstaller.cleanupPaths(config: config, deleteOptionalData: true).isEmpty)
    }
}
