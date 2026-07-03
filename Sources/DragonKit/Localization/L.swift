import Foundation

/// Resolve a localized string for `key` in the currently-selected language
/// (``LocalizationManager``): DragonKit's module bundle first, then the host app's
/// `Localizable.strings`, else the key itself. Lets each module ship its own strings while
/// letting the app override any key — and switch language at runtime without a restart.
@MainActor
public func L(_ key: String, table: String = "DragonKit") -> String {
    let sentinel = "\u{0}"
    let manager = LocalizationManager.shared
    let moduleBundle = manager.localizedBundle(for: .module)
    let fromModule = moduleBundle.localizedString(forKey: key, value: sentinel, table: table)
    if fromModule != sentinel { return fromModule }
    let appBundle = manager.localizedBundle(for: manager.appStringsBundle)
    let fromApp = appBundle.localizedString(forKey: key, value: sentinel, table: nil)
    if fromApp != sentinel { return fromApp }
    return key
}
