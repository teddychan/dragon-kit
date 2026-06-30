import Testing
@testable import DragonKit

@Suite struct LocalizationTests {
    @Test func resolvesKeyFromModuleBundle() {
        #expect(L("DragonKit.ping") == "pong")
    }

    @Test func fallsBackToKeyWhenMissing() {
        #expect(L("DragonKit.no.such.key") == "DragonKit.no.such.key")
    }
}
