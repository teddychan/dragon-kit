import Foundation

/// Helpers for building the About pane's content from the app bundle, so every Dragon app
/// formats its version identically. Read the version from Info.plist and the build time from
/// the executable — never hardcode either.
public enum DragonAbout {
    /// The formatted version string shown in the About pane, e.g.
    /// `v2.3.0 (23) · 2026-Jul-06 13:34:56 UTC`.
    ///
    /// - `CFBundleShortVersionString` → the `v`-prefixed marketing version.
    /// - `CFBundleVersion` → the build number in parentheses.
    /// - The executable's modification date → the build/sign time, formatted in UTC. Omitted
    ///   if it can't be read (so the string is still valid).
    public static func versionString(bundle: Bundle = .main) -> String {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return versionString(short: short, build: build, buildDate: buildDate(bundle: bundle))
    }

    /// Pure assembly of the version string from its parts, so the format is testable without a
    /// bundle. `buildDate` is omitted from the output when `nil`.
    static func versionString(short: String, build: String, buildDate: Date?) -> String {
        var result = "v\(short) (\(build))"
        if let date = buildDate {
            result += " · \(formattedUTC(date))"
        }
        return result
    }

    /// The app executable's modification date — the moment it was built/signed.
    private static func buildDate(bundle: Bundle) -> Date? {
        guard let executable = bundle.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executable.path)
        else { return nil }
        return attributes[.modificationDate] as? Date
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
