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

    /// Only values live here. Every row title, SF Symbol and ordering in the About pane is
    /// DragonKit's — see ``AboutContent``, which took free-form `links`/`credits` arrays until
    /// five apps used them to ship five visibly different panes.
    @MainActor
    static var content: AboutContent {
        AboutContent(
            appName: "Dragon Sample App",
            versionString: versionString,
            copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),
            // Sanctioned exception to the `dragonapp.com/{app-name}-{major}` rule: the sample app
            // is the kit's reference app and has no marketing page of its own, so it points at
            // the studio hub. Every shipping app must address its own canonical page, which
            // `AboutContent.websiteMatchesSupportRepo` checks against the support row's repo.
            websiteURL: URL(string: "https://www.dragonapp.com")!,
            supportURL: URL(string: "https://github.com/teddychan/dragon-kit/issues")!,
            license: "MIT",
            attributions: [
                // The app bundles Sparkle.framework by way of DragonKitUpdates.
                Attribution(component: L("app.about.updateFramework"), source: "Sparkle (MIT)"),
            ]
        )
    }
}
