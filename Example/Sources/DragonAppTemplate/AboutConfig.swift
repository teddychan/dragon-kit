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

    static var content: AboutContent {
        AboutContent(
            appName: "DragonKit Sample",
            versionString: versionString,
            copyright: "© 2026 Teddy Chan",
            links: [
                AboutLink(
                    title: "Website",
                    detail: "dragonapp.com",
                    systemImage: "globe",
                    url: URL(string: "https://www.dragonapp.com")!
                ),
                AboutLink(
                    title: "Source",
                    detail: "teddychan/dragon-kit",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    url: URL(string: "https://github.com/teddychan/dragon-kit")!
                ),
            ],
            credits: [
                (label: "Built with", value: "DragonKit"),
                (label: "License", value: "MIT"),
            ]
        )
    }
}
