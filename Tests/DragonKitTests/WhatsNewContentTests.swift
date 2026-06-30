import Testing
import Foundation
@testable import DragonKit

@Suite struct WhatsNewContentTests {
    @Test func kindLabelsAreUppercased() {
        #expect(ChangeSection.Kind.added.label == "ADDED")
        #expect(ChangeSection.Kind.fixed.label == "FIXED")
    }

    @Test func everyKindHasASymbol() {
        for kind in ChangeSection.Kind.allCases {
            #expect(!kind.systemImage.isEmpty)
        }
    }

    @Test func storesSectionsAndSummary() {
        let content = WhatsNewContent(
            version: "1.0.0", date: "2026-07-01", summary: "First release.",
            sections: [ChangeSection(kind: .added, entries: ["A", "B"])])
        #expect(content.version == "1.0.0")
        #expect(content.summary == "First release.")
        #expect(content.sections.first?.kind == .added)
        #expect(content.sections.first?.entries == ["A", "B"])
    }

    @Test func defaultsAreEmpty() {
        let content = WhatsNewContent(version: "1.0", date: "2026")
        #expect(content.summary.isEmpty)
        #expect(content.sections.isEmpty)
    }
}
