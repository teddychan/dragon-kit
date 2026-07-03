import Foundation
import DragonKit

enum WhatsNewConfig {
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v0.1.0",
            date: "2026-07-03",
            summary: "The DragonKit reference app: every shared menu-bar feature wired up "
                + "end-to-end, so you can see how each module is used.",
            sections: [
                ChangeSection(kind: .added, entries: [
                    "General settings with real, persisted toggles (Launch at login, Show in menu bar).",
                    "Check for Update pane (Sparkle) and a menu shortcut.",
                    "Permissions pane with live status and Open System Settings.",
                    "Backup & Restore of the app's settings, and a self-Uninstall flow.",
                ]),
                ChangeSection(kind: .improved, entries: [
                    "Design primitives reproduce the canonical grouped-form look.",
                ]),
            ]
        )
    }
}
