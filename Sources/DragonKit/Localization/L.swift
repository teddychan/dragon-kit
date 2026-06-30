import Foundation

/// Resolve a localized string for `key`: DragonKit's module bundle first, then the
/// host app's `Localizable.strings`, else the key itself. Lets each module ship its
/// own strings while letting the app override any key.
public func L(_ key: String, table: String = "DragonKit") -> String {
    let sentinel = "\u{0}"
    let fromModule = Bundle.module.localizedString(forKey: key, value: sentinel, table: table)
    if fromModule != sentinel { return fromModule }
    let fromApp = Bundle.main.localizedString(forKey: key, value: sentinel, table: nil)
    if fromApp != sentinel { return fromApp }
    return key
}
