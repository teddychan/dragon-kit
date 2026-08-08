import Testing
import Foundation
@testable import DragonKit

/// The About pane's canon: which rows exist, in what order, with which SF Symbols.
///
/// Five apps once shipped five visibly different About panes from this one kit, because
/// ``AboutContent`` took free-form `links`/`credits` arrays and the app chose every title, symbol
/// and row. The arrays are gone; these tests pin what replaced them.
///
/// Row *titles* are asserted against their localization keys rather than English text: which key
/// fills which slot is the canon, while the translations are ``LocalizationTests``' job — and
/// hardcoding English here would fail on a machine whose system language isn't English.
@MainActor
@Suite struct AboutCanonTests {
    static func content(
        originalProjectURL: URL? = nil,
        licensesURL: URL? = nil,
        originalWork: OriginalWork? = nil,
        attributions: [Attribution] = []
    ) -> AboutContent {
        AboutContent(
            appName: "Spectacle 2",
            versionString: "v2.4.1 (756)",
            copyright: "© 2026 Teddy Chan",
            websiteURL: URL(string: "https://www.dragonapp.com/spectacle-2/")!,
            supportURL: URL(string: "https://github.com/teddychan/spectacle-2/issues")!,
            license: "MIT",
            appIcon: nil,
            originalProjectURL: originalProjectURL,
            licensesURL: licensesURL,
            originalWork: originalWork,
            attributions: attributions
        )
    }

    @Test func linkRowsAreCanonical() {
        let rows = Self.content(
            originalProjectURL: URL(string: "https://github.com/eczarny/spectacle")!,
            licensesURL: URL(string: "https://www.dragonapp.com/spectacle-2/licenses")!
        ).linkRows

        #expect(rows.map(\.systemImage) == ["globe", "lifepreserver", "heart", "doc.text"])
        #expect(rows.map(\.title) == [
            L("DragonKit.about.website"),
            L("DragonKit.about.support"),
            L("DragonKit.about.original"),
            L("DragonKit.about.licenses"),
        ])
    }

    /// Omitting an optional slot must shorten the list, never reorder or retitle what remains —
    /// the sample app has no upstream project and no bundled third-party code.
    @Test func optionalLinkSlotsCollapseInOrder() {
        let rows = Self.content().linkRows
        #expect(rows.map(\.systemImage) == ["globe", "lifepreserver"])

        let withLicensesOnly = Self.content(
            licensesURL: URL(string: "https://www.dragonapp.com/spectacle-2/licenses")!
        ).linkRows
        #expect(withLicensesOnly.map(\.systemImage) == ["globe", "lifepreserver", "doc.text"])
    }

    @Test func creditRowsAreCanonical() {
        let rows = Self.content(
            originalWork: OriginalWork(name: "Spectacle", author: "Eric Czarny")
        ).creditRows

        #expect(rows.map(\.label) == [
            L("DragonKit.about.createdBy"),
            L("DragonKit.about.basedOn"),
            L("DragonKit.about.builtWith"),
            L("DragonKit.about.license"),
        ])
        #expect(rows[0].value == "Teddy Chan")
        #expect(rows[1].value == "Spectacle by Eric Czarny")
        #expect(rows[3].value == "MIT")
    }

    /// The row that says which kit a binary actually compiled against. An app supplies no part
    /// of it, so it cannot be omitted, moved, or made to state a version of its own.
    @Test func builtWithReportsKitVersionAndCannotBeOmitted() {
        let rows = Self.content().creditRows
        let builtWith = rows.first { $0.label == L("DragonKit.about.builtWith") }
        #expect(builtWith?.value == "DragonKit v\(DragonKitVersion.current)")
        #expect(builtWith?.value.hasPrefix("DragonKit v") == true)
    }

    /// App-specific attributions append after the canon rows and never interleave with them —
    /// yahoo-keykey-2 credits a language model, a Cangjie table and a Han-conversion library.
    @Test func attributionsRenderLastInOrder() {
        let rows = Self.content(attributions: [
            Attribution(name: "McBopomofo", license: "MIT"),
            Attribution(name: "ibus-table-chinese", license: "GPL-3.0"),
            Attribution(name: "OpenCC", license: "Apache-2.0"),
        ]).creditRows

        #expect(rows.count == 6)
        #expect(rows.suffix(3).map(\.label) == ["McBopomofo", "ibus-table-chinese", "OpenCC"])
        #expect(rows.suffix(3).map(\.value) == ["MIT", "GPL-3.0", "Apache-2.0"])
        // The canon rows are still the canon rows, in order, ahead of them. No `originalWork`
        // here, so the Based on slot collapses and Built with sits at index 1.
        #expect(rows[0].label == L("DragonKit.about.createdBy"))
        #expect(rows[1].label == L("DragonKit.about.builtWith"))
        #expect(rows[2].label == L("DragonKit.about.license"))
    }

    /// Attributions are name → licence. clipmenu-2 wrote `Sparkle → MIT` while the sample app
    /// wrote `Update framework → Sparkle (MIT)` — same type, two shapes, within a day of 3.0.0.
    /// The label is the thing's own name and the value its licence, in that order.
    @Test func attributionsAreNameThenLicense() {
        let rows = Self.content(attributions: [
            Attribution(name: "Sparkle", license: "MIT"),
            Attribution(name: "OpenCC", license: "Apache-2.0"),
        ]).creditRows
        #expect(rows.suffix(2).map(\.label) == ["Sparkle", "OpenCC"])
        #expect(rows.suffix(2).map(\.value) == ["MIT", "Apache-2.0"])
    }

    /// The deprecated `component:source:` spelling stays only because removing a public member
    /// would force a major tag and a hand bump in four apps. It must keep producing the identical
    /// row — a deprecation that quietly changed the output would be worse than the rename.
    @available(*, deprecated)
    @Test func deprecatedInitProducesTheSameRow() {
        let old = Attribution(component: "Sparkle", source: "MIT")
        let new = Attribution(name: "Sparkle", license: "MIT")
        #expect(old == new)
        #expect(old.component == new.name)
        #expect(old.source == new.license)
    }

    /// Two attributions may legitimately share a component name, and `ForEach` ids must be
    /// unique — keying rows on `label` once collapsed such a pair into one row and silently
    /// dropped the rest. ``AboutPane`` keys on position, which only works while this type keeps
    /// every row it was given, in order.
    @Test func duplicateAttributionLabelsAreBothKeptInOrder() {
        let rows = Self.content(attributions: [
            Attribution(name: "OpenCC", license: "MIT"),
            Attribution(name: "OpenCC", license: "Apache-2.0"),
        ]).creditRows
        #expect(rows.suffix(2).map(\.value) == ["MIT", "Apache-2.0"])
    }
}

/// Link detail text is derived from the URL, never typed beside it.
@Suite struct AboutLinkDetailTests {
    @Test func gitHubURLsBecomeOwnerSlashRepo() {
        #expect(AboutLinkDetail.detail(
            for: URL(string: "https://github.com/teddychan/ice-2/issues")!
        ) == "teddychan/ice-2")
        #expect(AboutLinkDetail.detail(
            for: URL(string: "https://github.com/eczarny/spectacle")!
        ) == "eczarny/spectacle")
    }

    /// yahoo-keykey-2 typed `www.dragonapp.com/keykey` where every other app omitted the `www.`.
    @Test func websiteURLsDropSchemeWWWAndTrailingSlash() {
        #expect(AboutLinkDetail.detail(
            for: URL(string: "https://www.dragonapp.com/yahoo-keykey-2/")!
        ) == "dragonapp.com/yahoo-keykey-2")
        #expect(AboutLinkDetail.detail(
            for: URL(string: "https://dragonapp.com/ice-2")!
        ) == "dragonapp.com/ice-2")
        #expect(AboutLinkDetail.detail(
            for: URL(string: "https://www.dragonapp.com")!
        ) == "dragonapp.com")
    }

    /// The site's canonical URLs are `{app-name}-{major}`, which is also the GitHub repo name.
    /// clipmenu-2 and yahoo-keykey-2 linked `<meta refresh>` stubs (`/clipmenu/`, `/keykey/`) and
    /// spectacle-2 linked the bare hub — three of five apps wrong, all catchable from the pair.
    @Test func websiteMustAddressTheCanonicalRepoPage() {
        func check(website: String, support: String) -> Bool {
            AboutContent(
                appName: "X", versionString: "v1", copyright: "©",
                websiteURL: URL(string: website)!,
                supportURL: URL(string: support)!,
                license: "MIT", appIcon: nil
            ).websiteMatchesSupportRepo
        }
        let issues = "https://github.com/teddychan/clipmenu-2/issues"
        #expect(check(website: "https://www.dragonapp.com/clipmenu-2/", support: issues))
        #expect(!check(website: "https://www.dragonapp.com/clipmenu/", support: issues))
        #expect(!check(website: "https://www.dragonapp.com", support: issues))
    }
}
