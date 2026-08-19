import Foundation

/// DragonKit's own version, shown in every app's About → Built with row.
///
/// A sanctioned exception to "never hardcode a version": a statically linked SwiftPM library has
/// no `Info.plist` to read and SwiftPM injects no package version at compile time, so a source
/// constant is the only mechanism that exists. Bumped with the `vX.Y.Z` tag; the tag-push
/// workflow fails when the two disagree, which is what keeps the row honest.
public enum DragonKitVersion {
    public static let current = "4.1.1"
}

/// The one place a version becomes user-visible text.
///
/// Every surface used to format its own: About prefixed a `v`, What's New printed whatever the
/// app typed (three of five apps dropped the prefix, two hardcoded the number), and the Sparkle
/// "up to date" alert built `"v\(short)"` by hand. Route everything through here instead.
public enum DragonVersion {
    /// Exactly one leading `v`, whatever the input had. Idempotent, so it is safe to apply to a
    /// value that may already be prefixed — which is the case for apps mid-migration.
    public static func display(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = trimmed.first, first == "v" || first == "V" {
            trimmed.removeFirst()
        }
        return "v" + trimmed
    }
}

/// Helpers for building the About pane's header from the app bundle, so every Dragon app formats
/// its version and copyright identically. Read both from `Info.plist` — never hardcode either.
public enum DragonAbout {
    /// The formatted version string shown in the About pane, e.g.
    /// `v2.3.0 (23) · 2026-Jul-06 13:34:56 UTC`, or `v2.3.0 Debug (23) · …` for a local build.
    ///
    /// - `CFBundleShortVersionString` → the marketing version, `v`-prefixed by ``DragonVersion``.
    /// - `CFBundleVersion` → the build number, which every build stamps as `git rev-list --count HEAD`.
    /// - `DragonBuildChannel` → the build channel, rendered after the version; absent in a release build.
    /// - `DragonCommitDate` → the commit's own timestamp, formatted in UTC.
    ///
    /// The timestamp used to be the executable's modification date — when CI linked and signed
    /// the binary — so the two halves of the line described different things and could disagree:
    /// rebuild the same commit tomorrow and the count holds while the date moves. Both halves now
    /// describe the same commit, making the line a fingerprint of the source.
    public static func versionString(bundle: Bundle = .main) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return versionString(short: short, build: build, commitDate: commitDate(bundle: bundle),
                             channel: buildChannel(bundle: bundle))
    }

    /// Pure assembly of the version string from its parts, so the format is testable without a
    /// bundle. `commitDate` and `channel` are omitted from the output when `nil`.
    static func versionString(short: String, build: String, commitDate: Date?,
                              channel: String? = nil) -> String {
        var result = DragonVersion.display(short)
        if let channel {
            result += " \(channel)"
        }
        result += " (\(build))"
        if let date = commitDate {
            result += " · \(formattedUTC(date))"
        }
        return result
    }

    /// The build channel stamped into `Info.plist` as `DragonBuildChannel` — `Debug` for a local
    /// hands-on build, absent for a release build.
    ///
    /// This exists so the word `Debug` never enters `CFBundleShortVersionString`. clipmenu-2,
    /// ice-2 and spectacle-2 each appended ` (Debug)` to that field in their debug scripts, which
    /// made the version non-numeric and put a channel label inside the one string the release tag
    /// is asserted against — `MAC-APP-RELEASE-LIFECYCLE.md` now forbids it outright. The channel
    /// is presentation; the version stays the numeric candidate `X.Y.Z`.
    ///
    /// Returns `nil` for a missing or blank value, so an unstamped release build renders exactly
    /// what it rendered before this key existed.
    public static func buildChannel(bundle: Bundle = .main) -> String? {
        normalizedChannel(bundle.object(forInfoDictionaryKey: "DragonBuildChannel") as? String)
    }

    /// Whether this bundle was stamped as a local Debug build.
    ///
    /// The lifecycle spec requires a Debug build to disable production updating, and the
    /// `macos-debug-build` recipe notes that clearing `SUEnableAutomaticChecks` is not enough —
    /// the app must also avoid *initializing or manually invoking* its updater. Apps still make
    /// that check themselves for the routes they own (the menu item they pass, an Xcode `#if
    /// DEBUG` build the channel cannot describe), so the kit exposes the channel rather than
    /// leaving five apps to re-read the plist key five ways.
    ///
    /// `DragonUpdater` in `DragonKitUpdates` reads this too, and that is not redundant: the
    /// Updates pane is kit-owned and binds the updater directly, so it reached Sparkle past both
    /// apps that had written an app-side guard. An app's guard covers its own call sites; the
    /// kit's covers the kit's.
    public static func isDebugBuild(bundle: Bundle = .main) -> Bool {
        isDebugChannel(bundle.object(forInfoDictionaryKey: "DragonBuildChannel") as? String)
    }

    /// Whether a raw channel value means Debug, as a pure function of the string.
    ///
    /// Split out from ``isDebugBuild(bundle:)`` because that reads `Bundle.main`, which under
    /// `swift test` is the test runner and can never carry a build channel — so only the
    /// *non*-Debug answer was ever reachable from a test, and a mapping that had stopped
    /// recognising `Debug` would have looked exactly the same. Everything that turns on this
    /// predicate is a safety gate, so the gate's input deserves both directions tested.
    static func isDebugChannel(_ raw: String?) -> Bool {
        normalizedChannel(raw)?.caseInsensitiveCompare("Debug") == .orderedSame
    }

    /// Pure normalization of the raw plist value, so blank-vs-absent is testable without a bundle.
    static func normalizedChannel(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The commit the bundle was built from, as stamped into `Info.plist` by the build script
    /// (`git log -1 --format=%cI`).
    ///
    /// Committer date rather than author date: it matches what `git log` shows and what actually
    /// sits on the branch, where an author date survives rebases and would point at the wrong
    /// moment. Returns `nil` when the key is absent, which drops the timestamp from the line
    /// entirely — deliberately no fallback to the executable's mtime, because a timestamp that
    /// quietly means something different in some builds is the drift this replaced.
    static func commitDate(bundle: Bundle) -> Date? {
        guard let raw = bundle.object(forInfoDictionaryKey: "DragonCommitDate") as? String else {
            return nil
        }
        return parseISO8601(raw)
    }

    /// Parse `2026-08-07T16:54:20+08:00`, with or without fractional seconds.
    static func parseISO8601(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }

    /// The copyright line, e.g. `© 2026 Teddy Chan`.
    ///
    /// Assembled here because the apps each wrote their own: ice-2 spelled out `Copyright © …`
    /// where the others used the symbol alone, and yahoo-keykey-2 put `倉頡／簡易 輸入法` in the
    /// slot — a description, not a copyright at all.
    ///
    /// **One holder — the app's own.** This took an `original:` pair until 4.0.0 and rendered
    /// `© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan`, which clipmenu-2 and ice-2 used and the
    /// other three apps did not, so two of five About panes carried a second copyright the rest
    /// lacked.
    ///
    /// **This is a presentation rule, and deliberately not a claim about who holds the
    /// copyright.** The first version of this comment argued that a Dragon app reimplements its
    /// upstream rather than reusing its source and so has no upstream copyright to assert. That is
    /// true of yahoo-keykey-2 — which reached the single-holder form on those grounds before the
    /// kit did — and false of both apps the change actually touched: ice-2 is a GPL-3.0 *fork* of
    /// Jordan Baird's Ice, whose §4 requires the upstream notice to travel with a derivative work,
    /// and clipmenu-2's `LICENSE` names two holders outright. Do not restore that reasoning.
    ///
    /// What survives is narrower and lineage-independent: this string fills a header row in a
    /// settings pane, and it read one way in three apps and another in two. Nothing here displaces
    /// a legal notice — `LICENSE` and the licences page are untouched, and that is where the
    /// upstream holder is named: ice-2's `LICENSE` carries Jordan Baird in the GPL's own notice
    /// template, clipmenu-2's names two holders outright. Lineage inside the pane is
    /// ``OriginalWork``'s job, twice over: the `Original project` link and the `Based on` credit.
    ///
    /// `NSHumanReadableCopyright` used to be cited here too, on ice-2's dual-holder value. All
    /// five apps now set it to `© 2026 Teddy Chan`, matching what this returns: it is an optional
    /// Apple key that no licence names — three of the five shipped without it — so it draws a line
    /// in Get Info rather than discharging §4, and a bundle whose notice disagreed with its own
    /// About pane was one app making two claims about itself. The kit neither reads nor requires
    /// the key; it is named here only so the next reader does not restore the old example.
    public static func copyright(years: String, holder: String) -> String {
        "© \(years) \(holder)"
    }

    /// Kept only to turn a stale call site into a readable compile error rather than
    /// "extra argument 'original' in call". Removing it once every app is on 4.0.0 is fine.
    @available(*, unavailable, message: "The About copyright names one holder — the app's own. An upstream author is credited by OriginalWork (the Original project link and the Based on row), and their licence text belongs on the licences page. Call copyright(years:holder:).")
    public static func copyright(
        original: (years: String, holder: String)?,
        years: String,
        holder: String
    ) -> String {
        copyright(years: years, holder: holder)
    }

    /// Format a date as `YYYY-MMM-DD HH:MM:SS UTC` (e.g. `2026-Jul-06 13:34:56 UTC`) using a
    /// fixed POSIX locale so the month abbreviation is stable regardless of the user's language.
    private static func formattedUTC(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MMM-dd HH:mm:ss"
        return "\(formatter.string(from: date)) UTC"
    }
}
