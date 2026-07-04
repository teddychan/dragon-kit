import Foundation
import DragonKit

enum WhatsNewConfig {
    @MainActor
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v1.2.0",
            date: "2026-07-04",
            summary: L("app.whatsNew.summary"),
            sections: [
                ChangeSection(kind: .added, entries: [
                    L("app.whatsNew.added1"),
                    L("app.whatsNew.added2"),
                ]),
                ChangeSection(kind: .improved, entries: [
                    L("app.whatsNew.improved1"),
                ]),
            ]
        )
    }
}
