import Foundation

/// Locates DragonKit's own resource bundle (its `.lproj` localized strings).
///
/// SwiftPM's synthesized `Bundle.module` `fatalError`s when it can't locate the
/// resource bundle, and in a packaged, code-signed `.app` its candidate paths (the
/// executable's directory / `Bundle.main.bundleURL` / the build dir) miss
/// `Contents/Resources`, which is the only place a `.app` can hold the bundle without
/// breaking its code signature. So `L(_:)` traps at launch the moment it needs a
/// DragonKit string.
///
/// Resolve `Contents/Resources` explicitly first (mirroring how a host app resolves its
/// own SwiftPM resource bundle), then fall back to `.module` for `swift build` / `swift
/// test`, where no `.app` exists and `.module` resolves via the build path.
enum DragonKitResources {
    static let bundle: Bundle = {
        let bundleName = "DragonKit_DragonKit.bundle"
        final class Anchor {}
        let candidates = [
            Bundle.main.resourceURL,              // packaged .app: Contents/Resources
            Bundle(for: Anchor.self).resourceURL, // built as a framework/loadable bundle
            Bundle(for: Anchor.self).bundleURL,   // next to the DragonKit binary
        ]
        for base in candidates {
            if let url = base?.appendingPathComponent(bundleName),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .module
    }()
}
