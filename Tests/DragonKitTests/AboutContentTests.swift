import Testing
import Foundation
@testable import DragonKit

@Suite struct AboutContentTests {
    @Test func storesExplicitValues() {
        let content = AboutContent(
            appName: "Test App",
            versionString: "v1.2.3 (45)",
            copyright: "© 2026 Someone",
            websiteURL: URL(string: "https://www.dragonapp.com/test-2/")!,
            supportURL: URL(string: "https://github.com/teddychan/test-2/issues")!,
            license: "MIT",
            appIcon: nil
        )
        #expect(content.appName == "Test App")
        #expect(content.versionString == "v1.2.3 (45)")
        #expect(content.copyright == "© 2026 Someone")
    }

    @Test func optionalSlotsDefaultToAbsentAndCreatorDefaultsToOwner() {
        let content = AboutContent(
            appName: "X", versionString: "v1", copyright: "©",
            websiteURL: URL(string: "https://www.dragonapp.com/x-2/")!,
            supportURL: URL(string: "https://github.com/teddychan/x-2/issues")!,
            license: "MIT", appIcon: nil
        )
        #expect(content.originalProjectURL == nil)
        #expect(content.licensesURL == nil)
        #expect(content.originalWork == nil)
        #expect(content.attributions.isEmpty)
        #expect(content.createdBy == "Teddy Chan")
    }

    @Test func versionStringPrefixesVAndAppendsUTCCommitDate() {
        // 2026-07-07 13:34:56 UTC
        let date = Date(timeIntervalSince1970: 1_783_431_296)
        let result = DragonAbout.versionString(short: "2.3.0", build: "23", commitDate: date)
        #expect(result == "v2.3.0 (23) · 2026-Jul-07 13:34:56 UTC")
    }

    /// No fallback to the executable's modification date: a timestamp that quietly means the
    /// build time in some bundles and the commit time in others is exactly the drift this
    /// replaced, so an unstamped bundle simply shows no date.
    @Test func versionStringOmitsCommitDateWhenUnavailable() {
        let result = DragonAbout.versionString(short: "2.3.0", build: "23", commitDate: nil)
        #expect(result == "v2.3.0 (23)")
    }

    /// A plist value that already carries a `v` must not produce `vv2.3.0`.
    @Test func versionStringDoesNotDoublePrefix() {
        let result = DragonAbout.versionString(short: "v2.3.0", build: "23", commitDate: nil)
        #expect(result == "v2.3.0 (23)")
    }

    @Test func parsesGitCommitterDateFormat() {
        // `git log -1 --format=%cI`
        let date = DragonAbout.parseISO8601("2026-08-07T16:54:20+08:00")
        #expect(date != nil)
        #expect(DragonAbout.versionString(short: "2.4.1", build: "756", commitDate: date)
            == "v2.4.1 (756) · 2026-Aug-07 08:54:20 UTC")
    }

    @Test func rejectsAMalformedCommitDate() {
        #expect(DragonAbout.parseISO8601("not a date") == nil)
        #expect(DragonAbout.parseISO8601("") == nil)
    }

    /// ice-2 spelled out `Copyright © …` where the others used the symbol alone, and
    /// yahoo-keykey-2 put a description in the slot instead of a copyright.
    @Test func copyrightFormat() {
        #expect(DragonAbout.copyright(years: "2026", holder: "Teddy Chan")
            == "© 2026 Teddy Chan")
        #expect(DragonAbout.copyright(
            original: (years: "2008–2014", holder: "Naotaka Morimoto"),
            years: "2026",
            holder: "Teddy Chan"
        ) == "© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan")
    }
}
