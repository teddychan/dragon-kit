import Foundation

/// Resolve a localized string for `key` in the currently-selected language
/// (``LocalizationManager``): DragonKit's module bundle first, then the host app's
/// `Localizable.strings`, else the key itself. Switches language at runtime without a restart.
///
/// **The module wins.** An app's `Localizable.strings` can only supply keys DragonKit does
/// *not* define — it cannot override one that it does. That keeps shared wording identical
/// across the Dragon apps, but it also means an app needing app-specific copy for a
/// kit-owned string can't get it by redefining the key; the kit has to expose it as config
/// (as ``UninstallConfig`` does for the checklist). Apps pass their own keys through the
/// same function, which is why they resolve at all.
@MainActor
public func L(_ key: String, table: String = "DragonKit") -> String {
    let sentinel = "\u{0}"
    let manager = LocalizationManager.shared
    let moduleBundle = manager.localizedBundle(for: DragonKitResources.bundle)
    let fromModule = moduleBundle.localizedString(forKey: key, value: sentinel, table: table)
    if fromModule != sentinel { return fromModule }
    let appBundle = manager.localizedBundle(for: manager.appStringsBundle)
    let fromApp = appBundle.localizedString(forKey: key, value: sentinel, table: nil)
    if fromApp != sentinel { return fromApp }
    return key
}
