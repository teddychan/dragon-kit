import Foundation
import DragonKit

enum AboutConfig {
    /// The single source of truth for the app version: the bundle's Info.plist. Never
    /// hardcode it — bump `CFBundleShortVersionString` / `CFBundleVersion` and About,
    /// backups, and update checks all read the same value.
    static var versionString: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    @MainActor
    static var content: AboutContent {
        AboutContent(
            appName: "DragonKit Sample",
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
