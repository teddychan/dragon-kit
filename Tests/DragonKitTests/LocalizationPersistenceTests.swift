import Foundation
import Combine
import Testing
@testable import DragonKit

@MainActor
@Suite struct LocalizationPersistenceTests {
    @Test func restoredLanguageRefreshesExistingLocalizedContentWithoutChangingTheSnapshot() throws {
        let suite = "DragonKit.LocalizationPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let manager = LocalizationManager(defaults: defaults)
        manager.setLanguage(.fr)
        defaults.set("saved", forKey: "fixture")
        let backup = try DragonBackup.writeBackup(
            suiteName: suite, appName: "Fixture", to: folder, defaults: defaults,
            appVersion: "1.0.0", date: Date())
        manager.setLanguage(.en)
        #expect(manager.localizedBundle(for: .module)
            .localizedString(forKey: "DragonKit.cancel", value: nil, table: "DragonKit") == "Cancel")

        try DragonBackup.restore(from: backup, suiteName: suite, defaults: defaults)
        let restored = try #require(defaults.persistentDomain(forName: suite))
        #expect(manager.language == .en)
        manager.reloadFromPersistence()

        #expect(manager.language == .fr)
        #expect(manager.localizedBundle(for: .module)
            .localizedString(forKey: "DragonKit.cancel", value: nil, table: "DragonKit") == "Annuler")
        let afterReload = try #require(defaults.persistentDomain(forName: suite))
        #expect(NSDictionary(dictionary: restored).isEqual(to: afterReload))
    }

    @Test(arguments: [DragonLanguage.en, .system])
    func anExplicitSelectionPersistsEvenWhenTheCachedSelectionAlreadyMatches(_ selection: DragonLanguage) throws {
        let suite = "DragonKit.LocalizationPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = LocalizationManager(defaults: defaults)
        manager.setLanguage(selection)
        let otherWriter = LocalizationManager(defaults: defaults)
        otherWriter.setLanguage(.fr)

        manager.setLanguage(selection)

        #expect(LocalizationManager(defaults: defaults).language == selection)
    }

    @Test(arguments: [String?](arrayLiteral: nil, "unknown-language"))
    func absentAndUnknownRestoredSelectionsFollowTheSystemWithoutNormalizingStorage(_ raw: String?) throws {
        let suite = "DragonKit.LocalizationPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = LocalizationManager(defaults: defaults)
        manager.setLanguage(.en)
        let languageKey = try #require(defaults.persistentDomain(forName: suite)?.keys.first)
        var restored: [String: Any] = ["fixture": "saved"]
        if let raw { restored[languageKey] = raw }
        defaults.setPersistentDomain(restored, forName: suite)

        manager.reloadFromPersistence()

        #expect(manager.language == .system)
        let afterReload = try #require(defaults.persistentDomain(forName: suite))
        #expect(NSDictionary(dictionary: restored).isEqual(to: afterReload))
    }

    @Test func reloadPublishesTheEffectiveChangeOnceAndLeavesPersistenceUntouched() throws {
        let suite = "DragonKit.LocalizationPersistenceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = LocalizationManager(defaults: defaults)
        manager.setLanguage(.en)
        LocalizationManager(defaults: defaults).setLanguage(.fr)
        let restored = try #require(defaults.persistentDomain(forName: suite))
        var published: [DragonLanguage] = []
        var notifications: [DragonLanguage] = []
        let publishedSubscription = manager.$language.dropFirst().sink { published.append($0) }
        let notificationSubscription = NotificationCenter.default.publisher(for: .dragonLanguageChanged)
            .sink { notification in
                if let language = notification.object as? DragonLanguage { notifications.append(language) }
            }
        defer {
            publishedSubscription.cancel()
            notificationSubscription.cancel()
        }

        manager.reloadFromPersistence()
        manager.reloadFromPersistence()

        #expect(published == [.fr])
        #expect(notifications == [.fr])
        let afterReload = try #require(defaults.persistentDomain(forName: suite))
        #expect(NSDictionary(dictionary: restored).isEqual(to: afterReload))
    }
}
