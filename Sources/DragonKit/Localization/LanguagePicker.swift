import SwiftUI

/// Drop-in language picker bound to ``LocalizationManager``. Lists "Automatic" (follow the
/// system) plus every language DragonKit ships. Changing it switches language immediately.
public struct LanguagePicker: View {
    @ObservedObject private var manager = LocalizationManager.shared

    public init() {}

    public var body: some View {
        Picker(L("DragonKit.language.label"), selection: Binding(
            get: { manager.language },
            set: { manager.setLanguage($0) }
        )) {
            Text(L("DragonKit.language.system")).tag(DragonLanguage.system)
            Divider()
            ForEach(DragonLanguage.selectable) { language in
                Text(language.displayName).tag(language)
            }
        }
    }
}

/// Rebuilds its content whenever ``LocalizationManager`` changes language, so every ``L(_:)``
/// re-resolves and the UI switches language without a restart. Also sets `\.locale` so dates
/// and numbers format for the chosen language.
public struct DragonLocalizedModifier: ViewModifier {
    @ObservedObject private var manager = LocalizationManager.shared

    public init() {}

    public func body(content: Content) -> some View {
        content
            .environment(\.locale, Locale(identifier: manager.localeIdentifier))
            .id(manager.language)
    }
}

public extension View {
    /// Make this view tree switch language live with ``LocalizationManager``. Apply once at the
    /// root of a settings window (host-supplied content that reads ``L(_:)`` updates too, as
    /// long as it is rebuilt here).
    func dragonLocalized() -> some View { modifier(DragonLocalizedModifier()) }
}
