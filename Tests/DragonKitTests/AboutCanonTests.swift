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
    static let spectacle = OriginalWork(
        name: "Spectacle",
        author: "Eric Czarny",
        url: URL(string: "https://github.com/eczarny/spectacle")!
    )

    static func content(
        originalWork: OriginalWork? = nil,
        attributions: [Attribution] = []
    ) -> AboutContent {
        AboutContent(
            appName: "Spectacle 2",
            versionString: "v2.4.1 (756)",
            copyright: "© 2026 Teddy Chan",
            websiteURL: URL(string: "https://www.dragonapp.com/spectacle-2/")!,
            supportURL: URL(string: "https://github.com/teddychan/spectacle-2/issues")!,
            licensesURL: URL(string: "https://www.dragonapp.com/spectacle-2/licenses/")!,
            license: "MIT",
            appIcon: nil,
            originalWork: originalWork,
            attributions: attributions
        )
    }

    @Test func linkRowsAreCanonical() {
        let rows = Self.content(originalWork: Self.spectacle).linkRows

        #expect(rows.map(\.systemImage) == ["globe", "lifepreserver", "heart", "doc.text"])
        #expect(rows.map(\.title) == [
            L("DragonKit.about.website"),
            L("DragonKit.about.support"),
            L("DragonKit.about.original"),
            L("DragonKit.about.licenses"),
        ])
    }

    /// `Original project` is the only optional link slot left, and omitting it must shorten the
    /// list without reordering or retitling what remains — the sample app reimplements nothing.
    ///
    /// The licences row is *not* optional as of 4.0.0. It was, and spectacle-2 and the sample app
    /// both omitted it while listing bundled components in Credits.
    @Test func onlyTheOriginalProjectSlotCollapses() {
        let rows = Self.content().linkRows
        #expect(rows.map(\.systemImage) == ["globe", "lifepreserver", "doc.text"])
        #expect(rows.map(\.title) == [
            L("DragonKit.about.website"),
            L("DragonKit.about.support"),
            L("DragonKit.about.licenses"),
        ])
    }

    /// The upstream project fills two rows from one value, so a pane can never credit it in
    /// Credits and fail to link it in Links — the exact state clipmenu-2 and ice-2 shipped.
    @Test func theOriginalProjectRowAndCreditTravelTogether() {
        let content = Self.content(originalWork: Self.spectacle)
        let link = content.linkRows.first { $0.systemImage == "heart" }
        let credit = content.creditRows.first { $0.label == L("DragonKit.about.basedOn") }
        #expect(link?.url == Self.spectacle.url)
        #expect(link?.detail == "eczarny/spectacle")
        #expect(credit?.value == "Spectacle by Eric Czarny")

        let without = Self.content()
        #expect(!without.linkRows.contains { $0.systemImage == "heart" })
        #expect(!without.creditRows.contains { $0.label == L("DragonKit.about.basedOn") })
    }

    @Test func creditRowsAreCanonical() {
        let rows = Self.content(originalWork: Self.spectacle).creditRows

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
    ///
    /// These are that app's **real** attributions, so the licences here must match its
    /// `docs/THIRD-PARTY-NOTICES.md` — a fixture in the reference repo is exactly what someone
    /// migrating an app copies. This row said `GPL-3.0` and was wrong in a way that mattered:
    /// GPL-3.0 covers the `ibus-table-chinese` repository's packaging, while the bundled data is
    /// the Cangjie-5 *table*, whose own header declares "Freely redistributable without
    /// restriction". Asserting GPL-3.0 in an MIT app's About pane states something that app's
    /// notices explicitly argue is untrue. Do not "tidy" this into an SPDX identifier the source
    /// does not claim — and quote the header in full: the first correction here wrote "Freely
    /// redistributable", which contradicted the very comment above it and shortened a licence
    /// grant while claiming to be quoting one.
    @Test func attributionsRenderLastInOrder() {
        let rows = Self.content(attributions: [
            Attribution(name: "McBopomofo", license: "MIT"),
            Attribution(name: "ibus-table-chinese", license: "Freely redistributable without restriction"),
            Attribution(name: "OpenCC", license: "Apache-2.0"),
        ]).creditRows

        #expect(rows.count == 6)
        #expect(rows.suffix(3).map(\.label) == ["McBopomofo", "ibus-table-chinese", "OpenCC"])
        #expect(rows.suffix(3).map(\.value) == ["MIT", "Freely redistributable without restriction", "Apache-2.0"])
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
                licensesURL: URL(string: "https://www.dragonapp.com/clipmenu-2/licenses/")!,
                license: "MIT", appIcon: nil
            ).websiteMatchesSupportRepo
        }
        let issues = "https://github.com/teddychan/clipmenu-2/issues"
        #expect(check(website: "https://www.dragonapp.com/clipmenu-2/", support: issues))
        #expect(!check(website: "https://www.dragonapp.com/clipmenu/", support: issues))
        #expect(!check(website: "https://www.dragonapp.com", support: issues))
        // Both hosts, which is what this compared nothing of: the path alone decided it, so any
        // site serving `/clipmenu-2/` agreed with the support row, and `hasSuffix("github.com")`
        // accepted `notgithub.com` and handed back an owner and a repo to agree with.
        #expect(!check(website: "https://evil-example.com/clipmenu-2/", support: issues))
        #expect(!check(website: "https://www.dragonapp.com/clipmenu-2/",
                       support: "https://notgithub.com/teddychan/clipmenu-2/issues"))
        // The boundary cuts the other way too, or four shipping apps would start failing: `www.`
        // is a subdomain, and the bare domain is the site itself.
        #expect(check(website: "https://dragonapp.com/clipmenu-2/", support: issues))
        #expect(check(website: "https://www.dragonapp.com/clipmenu-2/",
                      support: "https://www.github.com/teddychan/clipmenu-2/issues"))
    }

    /// `AboutLinkDetail` renders the row's trailing text from the same host test, so a lookalike
    /// host must not read as a GitHub link there either — it falls back to `host/path`.
    @Test func lookalikeHostsAreNotGitHub() {
        #expect(AboutLinkDetail.repository(
            of: URL(string: "https://notgithub.com/teddychan/ice-2/issues")!
        ) == nil)
        #expect(AboutLinkDetail.detail(
            for: URL(string: "https://notgithub.com/teddychan/ice-2/issues")!
        ) == "notgithub.com/teddychan/ice-2/issues")
        #expect(AboutLinkDetail.repository(
            of: URL(string: "https://www.github.com/teddychan/ice-2/issues")!
        ) == "ice-2")
        #expect(!AboutLinkDetail.isDragonAppSite(URL(string: "https://notdragonapp.com/ice-2/")!))
        #expect(AboutLinkDetail.isDragonAppSite(URL(string: "https://dragonapp.com/ice-2/")!))
    }
}
