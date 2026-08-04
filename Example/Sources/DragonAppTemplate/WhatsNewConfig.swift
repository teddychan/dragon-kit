import Foundation
import DragonKit

enum WhatsNewConfig {
    @MainActor
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v1.2.0",
            date: "2026-08-04",
            summary: L("app.whatsNew.summary"),
            sections: [
                ChangeSection(kind: .removed, entries: [
                    L("app.whatsNew.removed1"),
                ]),
                ChangeSection(kind: .changed, entries: [
                    L("app.whatsNew.changed1"),
                ]),
            ]
        )
    }
}
