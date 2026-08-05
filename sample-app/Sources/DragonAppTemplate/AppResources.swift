import Foundation

/// Locates the app's own SwiftPM resource bundle (its `.lproj` localized strings).
///
/// SwiftPM's synthesized `Bundle.module` only looks for the bundle directly inside
/// `Bundle.main.bundleURL` (the `.app` root) or the original build directory. In a
/// packaged, code-signed `.app` the bundle lives in `Contents/Resources` — the only
/// place a `.app` can hold it without breaking its code signature — which `.module`
/// misses, so it `fatalError`s at launch. (This mirrors `DragonKitResources` in the kit.)
///
/// Resolve `Contents/Resources` explicitly first, then fall back to `.module` for
/// `swift build` / `swift test`, where no `.app` exists and `.module` resolves via the
/// build path.
enum AppResources {
    static let stringsBundle: Bundle = {
        let bundleName = "DragonAppTemplate_DragonAppTemplate.bundle"
        final class Anchor {}
        let candidates = [
            Bundle.main.resourceURL,              // packaged .app: Contents/Resources
            Bundle(for: Anchor.self).resourceURL, // built as a framework/loadable bundle
            Bundle(for: Anchor.self).bundleURL,   // next to the app binary
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
