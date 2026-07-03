import Foundation
import DragonKit

enum WhatsNewConfig {
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v1.0.2",
            date: "2026-07-03",
            summary: "Menu and settings refinements that keep the whole experience inside the "
                + "settings window — fewer standalone popups.",
            sections: [
                ChangeSection(kind: .added, entries: [
                    "About item in the menu-bar quick menu, opening directly to the About pane.",
                ]),
                ChangeSection(kind: .improved, entries: [
                    "Uninstall confirms inline in the settings pane instead of a separate window.",
                    "Check for Updates from the menu opens the Updates pane for context.",
                    "Dev builds stamp a real build number (git commit count), shown in About.",
                ]),
            ]
        )
    }
}
