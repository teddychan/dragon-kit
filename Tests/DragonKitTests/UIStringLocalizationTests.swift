import Testing
import Foundation

/// Flags user-visible string literals that bypass `L(_:)`.
///
/// A source scanner, and a broken checker is worse than no checker — it passes everything
/// silently. So the matching is a pure function over a source string, exercised below against
/// snippets that must and must not trip it, and only then run across the real sources.
enum UIStringScanner {
    /// Call sites that put text on screen.
    static let triggers = [
        "Text(", "Label(", "Button(", "Toggle(", "Link(", "Picker(",
        "messageText = ", "informativeText = ", "addButton(withTitle: ",
    ]

    /// Lines carrying a literal with prose in it. A literal made only of interpolations and
    /// punctuation — `"\(version) · \(date)"` — is a separator, not copy, and is allowed.
    static func offenders(in source: String) -> [String] {
        let chars = Array(source)
        var results: [String] = []
        for trigger in triggers {
            var searchStart = source.startIndex
            while let range = source.range(of: trigger, range: searchStart..<source.endIndex) {
                searchStart = range.upperBound
                var i = source.distance(from: source.startIndex, to: range.upperBound)
                while i < chars.count, chars[i] == " " || chars[i] == "\n" { i += 1 }
                guard i < chars.count, chars[i] == "\"" else { continue }
                guard let literal = literal(from: chars, quoteAt: i) else { continue }
                if containsProse(literal) {
                    results.append(literal)
                }
            }
        }
        return results
    }

    /// The contents of the string literal whose opening quote is at `index`.
    private static func literal(from chars: [Character], quoteAt index: Int) -> String? {
        var out = ""
        var i = index + 1
        while i < chars.count {
            if chars[i] == "\\" , i + 1 < chars.count, chars[i + 1] == "\"" {
                out.append("\"")
                i += 2
                continue
            }
            if chars[i] == "\"" { return out }
            if chars[i] == "\n" { return nil }
            out.append(chars[i])
            i += 1
        }
        return nil
    }

    /// Two or more consecutive letters outside any `\(…)` interpolation.
    static func containsProse(_ literal: String) -> Bool {
        let withoutInterpolations = literal.replacingOccurrences(
            of: "\\\\\\([^)]*\\)", with: "", options: .regularExpression
        )
        return withoutInterpolations.range(
            of: "[A-Za-z]{2,}", options: .regularExpression
        ) != nil
    }
}

@Suite struct UIStringLocalizationTests {
    /// The checker's own test. Without it a regex typo would silently pass every file.
    @Test func scannerFlagsProseAndIgnoresLocalizedOrPunctuationOnlyLiterals() {
        #expect(!UIStringScanner.offenders(in: ##"alert.messageText = "\(name) is up to date""##).isEmpty)
        #expect(!UIStringScanner.offenders(in: #"Text("Acknowledgements")"#).isEmpty)
        #expect(!UIStringScanner.offenders(in: #"alert.addButton(withTitle: "OK")"#).isEmpty)

        #expect(UIStringScanner.offenders(in: #"Text(L("DragonKit.pane.about"))"#).isEmpty)
        #expect(UIStringScanner.offenders(in: #"Label(row.title, systemImage: row.systemImage)"#).isEmpty)
        // Separator-only interpolation: the values are already localized.
        #expect(UIStringScanner.offenders(in: ###"Text("\(content.displayVersion) · \(content.date)")"###).isEmpty)
    }

    /// The kit ships seven languages and `L()` resolves the module bundle first, so a raw literal
    /// here is text no app can translate or override. The Sparkle "no update found" alert carried
    /// three of them — `"<App> is up to date"`, its message, and its `OK` button.
    @Test func noUnlocalizedUIStringsInKitSources() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DragonKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources")

        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            for literal in UIStringScanner.offenders(in: source) {
                offenders.append("\(url.lastPathComponent): \"\(literal)\"")
            }
        }
        #expect(offenders.isEmpty, "user-visible strings bypassing L():\n\(offenders.joined(separator: "\n"))")
    }
}
