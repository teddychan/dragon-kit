import Foundation
import DragonKit

enum WhatsNewConfig {
    /// Release notes for the What's New pane. `version` and `date` are written by hand rather
    /// than read from the bundle: this is the changelog for one specific release, and it has to
    /// stay pinned to the release it describes even after `CFBundleShortVersionString` moves on.
    /// Keep it in step with `sample-app/Info.plist` — the release workflow asserts that the
    /// `sample-vX.Y.Z` tag matches that plist version, so a stale entry *here* is the one part
    /// nothing checks for you.
    ///
    /// Every entry is a localization key resolved through ``L(_:)``; the app ships its own
    /// `Localizable.strings` in seven languages, so the pane switches with the language picker.
    /// Fixed leads because 1.3.0's headline is that settings stop being lost on upgrade.
    @MainActor
    static var content: WhatsNewContent {
        WhatsNewContent(
            version: "v1.3.1",
            date: "2026-08-07",
            summary: L("app.whatsNew.summary"),
            sections: [
                ChangeSection(kind: .fixed, entries: [
                    L("app.whatsNew.fixed1"),
                    L("app.whatsNew.fixed2"),
                    L("app.whatsNew.fixed3"),
                ]),
                ChangeSection(kind: .added, entries: [
                    L("app.whatsNew.added1"),
                ]),
                ChangeSection(kind: .changed, entries: [
                    L("app.whatsNew.changed1"),
                    L("app.whatsNew.changed2"),
                ]),
                ChangeSection(kind: .removed, entries: [
                    L("app.whatsNew.removed1"),
                ]),
                ChangeSection(kind: .improved, entries: [
                    L("app.whatsNew.improved1"),
                ]),
            ]
        )
    }
}
