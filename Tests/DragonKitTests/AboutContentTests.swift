import Testing
import Foundation
@testable import DragonKit

@Suite struct AboutContentTests {
    @Test func storesExplicitValues() {
        let content = AboutContent(
            appName: "Test App",
            versionString: "1.2.3 (45)",
            copyright: "© 2026 Someone"
        )
        #expect(content.appName == "Test App")
        #expect(content.versionString == "1.2.3 (45)")
        #expect(content.copyright == "© 2026 Someone")
    }

    @Test func defaultsAreEmptyOrNil() {
        let content = AboutContent(appName: "X", versionString: "1.0", copyright: "©")
        #expect(content.links.isEmpty)
        #expect(content.credits.isEmpty)
        #expect(content.acknowledgementsURL == nil)
    }

    @Test func linkStoresFields() {
        let url = URL(string: "https://example.com")!
        let link = AboutLink(title: "Website", detail: "example.com", systemImage: "globe", url: url)
        #expect(link.title == "Website")
        #expect(link.url == url)
    }
}
