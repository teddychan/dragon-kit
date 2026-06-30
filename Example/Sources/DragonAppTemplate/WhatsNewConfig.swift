import Foundation
import DragonKit

enum WhatsNewConfig {
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v0.1.0",
            date: "2026-07-01",
            summary: "The first DragonKit release: a shared settings shell with About and "
                + "What's New panes, plus a reusable menu-bar app template.",
            sections: [
                ChangeSection(kind: .added, entries: [
                    "Settings shell with a sidebar and host-owned selection.",
                    "About and What's New panes driven by app-supplied content.",
                    "A reusable settings window controller for menu-bar apps.",
                ]),
                ChangeSection(kind: .improved, entries: [
                    "Design primitives reproduce the canonical grouped-form look.",
                ]),
            ]
        )
    }
}
