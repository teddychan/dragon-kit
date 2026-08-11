import Testing
import Foundation
@testable import DragonKit

@MainActor
@Suite struct LocalizationTests {
    /// Proves `L()` reads the module bundle instead of falling through to returning the key.
    /// Deliberately asserted against a *real shipping* key: this used to use a `DragonKit.ping`
    /// = `pong` fixture, which — because key parity forces every key into every locale — shipped
    /// to users of all five Dragon apps in seven languages. Don't reintroduce a fixture key.
    /// `DragonKit.ok` works because its value differs from the key in all seven `.lproj` files,
    /// so a broken resolver returning the key can't pass.
    @Test func resolvesKeyFromModuleBundle() {
        #expect(L("DragonKit.ok") == "OK")
    }

    @Test func fallsBackToKeyWhenMissing() {
        #expect(L("DragonKit.no.such.key") == "DragonKit.no.such.key")
    }

    /// Every shipped language must define exactly the same keys as English — catches a
    /// translation added to one locale but forgotten in another.
    @Test func allLanguagesDefineTheSameKeys() throws {
        let languages = ["en", "es", "fr", "ja", "ko", "zh-Hans", "zh-Hant"]

        func keys(_ language: String) throws -> Set<String> {
            let bundle = try #require(
                LocalizationManager.lprojBundle(language, in: .module),
                "missing \(language).lproj"
            )
            let url = try #require(bundle.url(forResource: "DragonKit", withExtension: "strings"))
            let dict = try #require(NSDictionary(contentsOf: url) as? [String: String])
            return Set(dict.keys)
        }

        let english = try keys("en")
        #expect(!english.isEmpty)
        for language in languages {
            #expect(try keys(language) == english, "\(language) key set differs from en")
        }
    }
}

/// Pins the option list ``LanguagePicker`` builds. The picker became configurable so an app can
/// offer only the languages it has translated *itself* into: ice-2 shipped Simplified Chinese
/// alone, and a picker listing all seven would have switched the kit's four panes while leaving
/// the app's own 234 strings in English. Before that, the only way to get a correct list was to
/// hand-roll the picker — which is what ice-2 PR #83 originally did, and what CONFORMANCE.md
/// forbids.
@MainActor
@Suite struct LanguagePickerOptionTests {
    /// The default has to stay every shipped language, or adding the parameter would silently
    /// shrink the picker in the four apps that pass nothing.
    @Test func defaultsToEveryShippedLanguage() {
        let offered = LanguagePicker.offeredLanguages(
            configured: DragonLanguage.selectable, selection: .system
        )
        #expect(offered == DragonLanguage.selectable)
        #expect(offered.count == 7)
    }

    @Test func listsOnlyTheLanguagesTheAppConfigured() {
        #expect(
            LanguagePicker.offeredLanguages(configured: [.en, .zhHans], selection: .system)
                == [.en, .zhHans]
        )
    }

    /// "Automatic" is rendered above the divider, so an app passing `.system` through would get
    /// two of it.
    @Test func dropsSystemBecauseItIsRenderedSeparately() {
        #expect(
            LanguagePicker.offeredLanguages(configured: [.system, .en, .zhHans], selection: .en)
                == [.en, .zhHans]
        )
    }

    /// A selection inside the configured set must not be duplicated by the orphan rule below.
    @Test func doesNotDuplicateASelectionItAlreadyOffers() {
        #expect(
            LanguagePicker.offeredLanguages(configured: [.en, .zhHans], selection: .zhHans)
                == [.en, .zhHans]
        )
    }

    /// The selection persists in `UserDefaults`, so narrowing the configured set strands whatever
    /// was already chosen. SwiftUI draws a `Picker` whose selection matches no tag as blank, which
    /// would leave the user looking at an empty control with no way out — so the orphan is listed.
    @Test func keepsAnOrphanedSelectionVisibleSoItCanBeChanged() {
        #expect(
            LanguagePicker.offeredLanguages(configured: [.en, .zhHans], selection: .fr)
                == [.en, .zhHans, .fr]
        )
    }
}
