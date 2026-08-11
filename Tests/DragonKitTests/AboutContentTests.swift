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
            licensesURL: URL(string: "https://www.dragonapp.com/test-2/licenses/")!,
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
            licensesURL: URL(string: "https://www.dragonapp.com/x-2/licenses/")!,
            license: "MIT", appIcon: nil
        )
        #expect(content.originalWork == nil)
        #expect(content.originalProjectURL == nil)
        #expect(content.attributions.isEmpty)
        #expect(content.createdBy == "Teddy Chan")
    }

    /// The `Original project` link and the `Based on` credit are one value, so an app cannot ship
    /// one without the other. clipmenu-2 and ice-2 shipped the credit with no link for two
    /// releases, which is what folded the URL into ``OriginalWork``.
    @Test func originalProjectURLIsDerivedFromTheCredit() {
        let content = AboutContent(
            appName: "X", versionString: "v1", copyright: "©",
            websiteURL: URL(string: "https://www.dragonapp.com/x-2/")!,
            supportURL: URL(string: "https://github.com/teddychan/x-2/issues")!,
            licensesURL: URL(string: "https://www.dragonapp.com/x-2/licenses/")!,
            license: "MIT", appIcon: nil,
            originalWork: OriginalWork(
                name: "Spectacle",
                author: "Eric Czarny",
                url: URL(string: "https://github.com/eczarny/spectacle")!
            )
        )
        #expect(content.originalProjectURL?.absoluteString == "https://github.com/eczarny/spectacle")
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

    /// The exact shape `MAC-APP-RELEASE-LIFECYCLE.md` specifies for a local build:
    /// `vX.Y.Z Debug (<build>)`. The channel sits between the version and the build number, and
    /// the version itself stays the numeric candidate — clipmenu-2, ice-2 and spectacle-2 each
    /// used to reach this by writing ` (Debug)` into `CFBundleShortVersionString` instead.
    @Test func versionStringRendersTheChannelAfterTheVersion() {
        let result = DragonAbout.versionString(short: "2.10.1", build: "756", commitDate: nil,
                                               channel: "Debug")
        #expect(result == "v2.10.1 Debug (756)")
    }

    @Test func versionStringPlacesTheChannelBeforeTheCommitDate() {
        // 2026-07-07 13:34:56 UTC
        let date = Date(timeIntervalSince1970: 1_783_431_296)
        let result = DragonAbout.versionString(short: "2.10.1", build: "756", commitDate: date,
                                               channel: "Debug")
        #expect(result == "v2.10.1 Debug (756) · 2026-Jul-07 13:34:56 UTC")
    }

    /// A release build stamps no channel, and must render exactly what it rendered before the key
    /// existed — the whole point of making the channel additive rather than a format change.
    @Test func versionStringIsUnchangedWhenNoChannelIsStamped() {
        let result = DragonAbout.versionString(short: "2.10.1", build: "756", commitDate: nil)
        #expect(result == "v2.10.1 (756)")
    }

    /// Absent, empty and whitespace-only all mean "release build". A blank key must not render a
    /// stray trailing space between the version and the build number.
    @Test func blankChannelIsTreatedAsAbsent() {
        #expect(DragonAbout.normalizedChannel(nil) == nil)
        #expect(DragonAbout.normalizedChannel("") == nil)
        #expect(DragonAbout.normalizedChannel("   ") == nil)
        #expect(DragonAbout.normalizedChannel("  Debug  ") == "Debug")
        #expect(DragonAbout.versionString(short: "2.10.1", build: "756", commitDate: nil,
                                          channel: DragonAbout.normalizedChannel("  "))
                == "v2.10.1 (756)")
    }

    /// The safe default: a bundle with no `DragonBuildChannel` is not a Debug build. Apps gate
    /// updater initialization on this, so an inverted default would arm the production updater in
    /// every Debug build — or disarm it in every release one.
    @Test func bundleWithoutTheChannelKeyIsNotADebugBuild() {
        #expect(DragonAbout.buildChannel(bundle: .module) == nil)
        #expect(DragonAbout.isDebugBuild(bundle: .module) == false)
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
    ///
    /// One holder, and exactly one `©`. The dual-holder form clipmenu-2 and ice-2 used —
    /// `© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan` — is gone: the upstream author is
    /// credited by ``OriginalWork`` and their licence text by the licences page, and a Dragon app
    /// reimplements rather than reuses upstream source, so it has no upstream copyright to assert.
    @Test func copyrightNamesOneHolder() {
        let line = DragonAbout.copyright(years: "2026", holder: "Teddy Chan")
        #expect(line == "© 2026 Teddy Chan")
        #expect(line.filter { $0 == "©" }.count == 1)
    }
}
