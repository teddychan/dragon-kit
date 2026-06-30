import Foundation
import DragonKit

enum AboutConfig {
    static var content: AboutContent {
        AboutContent(
            appName: "Dragon App",
            versionString: "0.1.0",
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
