import Testing
import Foundation
@testable import DragonKit

/// Every version that reaches the UI carries exactly one leading `v`.
///
/// It did not. About prefixed one, the Sparkle "up to date" alert built `"v\(short)"` by hand,
/// and What's New printed whatever the app typed — ice-2 and spectacle-2 passed the raw plist
/// value and showed none, while yahoo-keykey-2 and the sample app hardcoded a literal that would
/// disagree with the bundle on the next release.
@Suite struct VersionDisplayTests {
    @Test func displayNormalizesAndIsIdempotent() {
        #expect(DragonVersion.display("2.4.1") == "v2.4.1")
        #expect(DragonVersion.display("v2.4.1") == "v2.4.1")
        #expect(DragonVersion.display("V2.4.1") == "v2.4.1")
        #expect(DragonVersion.display("  2.4.1  ") == "v2.4.1")
        // Applying it twice is what makes it safe on a value that may already be prefixed.
        #expect(DragonVersion.display(DragonVersion.display("2.4.1")) == "v2.4.1")
    }

    /// Fed un-prefixed input, every surface that renders a version must still show the `v`.
    ///
    /// The guarantee is structural rather than tested: ``WhatsNewContent/version`` is not public,
    /// so no un-prefixed string is reachable from outside the module and a future pane cannot
    /// render one. This pins the formatting the type change already forces.
    @Test func everyVersionSurfaceIsPrefixed() {
        let surfaces: [String] = [
            WhatsNewContent(version: "2.4.1", date: "2026-08-07").displayVersion,
            DragonAbout.versionString(short: "2.4.1", build: "756", commitDate: nil),
            DragonVersion.display("2.4.1"),
        ]
        for rendered in surfaces {
            #expect(rendered.hasPrefix("v"), "un-prefixed version surfaced: \(rendered)")
            #expect(!rendered.hasPrefix("vv"))
        }
    }

    /// yahoo-keykey-2 hardcoded `"2.10.0"` and the sample app `"v1.3.1"`, both of which break the
    /// repo's own rule that a version is read from `Info.plist` and never typed.
    @Test func whatsNewVersionDefaultsToTheBundle() {
        let bundle = Bundle(for: BundleAnchor.self)
        let content = WhatsNewContent(date: "2026-08-07", bundle: bundle)
        let expected = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(content.version == (expected ?? "1.0.0"))
        #expect(content.displayVersion == DragonVersion.display(content.version))
    }

    @Test func kitVersionIsWellFormedSemver() {
        let parts = DragonKitVersion.current.split(separator: ".")
        #expect(parts.count == 3)
        #expect(parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        // The constant is bare; the `v` is added at render time like every other version.
        #expect(!DragonKitVersion.current.hasPrefix("v"))
    }
}

private final class BundleAnchor {}
