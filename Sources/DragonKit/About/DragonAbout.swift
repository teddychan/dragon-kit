import Foundation

/// DragonKit's own version, shown in every app's About → Built with row.
///
/// A sanctioned exception to "never hardcode a version": a statically linked SwiftPM library has
/// no `Info.plist` to read and SwiftPM injects no package version at compile time, so a source
/// constant is the only mechanism that exists. Bumped with the `vX.Y.Z` tag; the tag-push
/// workflow fails when the two disagree, which is what keeps the row honest.
public enum DragonKitVersion {
    public static let current = "3.0.1"
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
    /// `v2.3.0 (23) · 2026-Jul-06 13:34:56 UTC`.
    ///
    /// - `CFBundleShortVersionString` → the marketing version, `v`-prefixed by ``DragonVersion``.
    /// - `CFBundleVersion` → the build number, which every build stamps as `git rev-list --count HEAD`.
    /// - `DragonCommitDate` → the commit's own timestamp, formatted in UTC.
    ///
    /// The timestamp used to be the executable's modification date — when CI linked and signed
    /// the binary — so the two halves of the line described different things and could disagree:
    /// rebuild the same commit tomorrow and the count holds while the date moves. Both halves now
    /// describe the same commit, making the line a fingerprint of the source.
    public static func versionString(bundle: Bundle = .main) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return versionString(short: short, build: build, commitDate: commitDate(bundle: bundle))
    }

    /// Pure assembly of the version string from its parts, so the format is testable without a
    /// bundle. `commitDate` is omitted from the output when `nil`.
    static func versionString(short: String, build: String, commitDate: Date?) -> String {
        var result = "\(DragonVersion.display(short)) (\(build))"
        if let date = commitDate {
            result += " · \(formattedUTC(date))"
        }
        return result
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

    /// The copyright line, e.g. `© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan`.
    ///
    /// Assembled here because the apps each wrote their own: ice-2 spelled out `Copyright © …`
    /// where the others used the symbol alone, and yahoo-keykey-2 put `倉頡／簡易 輸入法` in the
    /// slot — a description, not a copyright at all.
    public static func copyright(
        original: (years: String, holder: String)? = nil,
        years: String,
        holder: String
    ) -> String {
        let current = "© \(years) \(holder)"
        guard let original else { return current }
        return "© \(original.years) \(original.holder) · \(current)"
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
