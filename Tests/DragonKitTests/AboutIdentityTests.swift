import Testing
import Foundation
import DragonKit

/// Guards the two identities `AboutPane` keys its `ForEach`es on. The rendering itself isn't
/// unit-testable without standing up SwiftUI, so these pin the properties of the *data* that
/// make those keys correct — and fail loudly if either property is taken away.
@Suite struct AboutIdentityTests {
    /// `AboutPane` used to key credits on `\.label`. `ForEach` ids must be unique, so two credits
    /// sharing a label rendered as a single row and the rest were silently dropped. The pane now
    /// keys on position; that only works while the content type keeps every credit it was given,
    /// in order — deduping here would put the bug back one layer down.
    @Test func duplicateCreditLabelsAreBothKeptInOrder() {
        let content = AboutContent(
            appName: "X",
            versionString: "1.0",
            copyright: "©",
            credits: [
                (label: "License", value: "MIT"),
                (label: "License", value: "Apache-2.0"),
            ]
        )
        #expect(content.credits.count == 2)
        #expect(content.credits.map(\.value) == ["MIT", "Apache-2.0"])
    }

    /// Why `AboutPane` keys links on `\.url` rather than `AboutLink.id`: `id` is a fresh `UUID()`
    /// per instance, so an app whose content is a computed property (sample-app's
    /// `AboutConfig.content` is a `static var`) hands SwiftUI brand-new identities on every
    /// rebuild — the settings root rebuilds its panes on each language change — and every row is
    /// torn down and recreated instead of updated. `url` is equal across those rebuilds.
    ///
    /// If `id` ever becomes stable, `AboutPane` moves with it; this test is the tripwire.
    @Test func linkURLIsStableAcrossRebuildsWhileIDIsNot() {
        func websiteLink() -> AboutLink {
            AboutLink(
                title: "Website",
                detail: "example.com",
                systemImage: "globe",
                url: URL(string: "https://example.com")!
            )
        }
        let firstBuild = websiteLink()
        let secondBuild = websiteLink()
        #expect(firstBuild.url == secondBuild.url)
        #expect(firstBuild.id != secondBuild.id)
    }

    // The other half of the `\.url` key — that no two rows share a URL — is a precondition on
    // app-supplied content, not a property of any kit type, so there is nothing here to assert
    // that wouldn't just be re-testing `URL`'s `Equatable`. It is noted in `AboutPane` instead.
}
