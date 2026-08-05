import Foundation
import DragonKit

enum AboutConfig {
    /// The single source of truth for the app version: the bundle's Info.plist, formatted by
    /// DragonKit as `v2.3.0 (23) · 2026-Jul-06 13:34:56 UTC`. Never hardcode it — bump
    /// `CFBundleShortVersionString` / `CFBundleVersion` and About, backups, and update checks
    /// all read the same value.
    static var versionString: String {
        DragonAbout.versionString()
    }

    @MainActor
    static var content: AboutContent {
        AboutContent(
            appName: "Dragon Sample App",
            versionString: versionString,
            copyright: "© 2026 Teddy Chan",
            links: [
                AboutLink(
                    title: L("app.about.website"),
                    detail: "dragonapp.com",
                    systemImage: "globe",
                    url: URL(string: "https://www.dragonapp.com")!
                ),
                AboutLink(
                    title: L("app.about.source"),
                    detail: "teddychan/dragon-kit",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: URL(string: "https://github.com/teddychan/dragon-kit")!
                ),
            ],
            credits: [
                (label: L("app.about.builtWith"), value: "DragonKit"),
                (label: L("app.about.license"), value: "MIT"),
            ]
        )
    }
}
