import Testing
import Foundation
@testable import DragonKit

@MainActor
@Suite struct LocalizationTests {
    @Test func resolvesKeyFromModuleBundle() {
        #expect(L("DragonKit.ping") == "pong")
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
