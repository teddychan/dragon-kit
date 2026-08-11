import SwiftUI

/// Drop-in language picker bound to ``LocalizationManager``. Lists "Automatic" (follow the
/// system) plus the languages the host app offers. Changing it switches language immediately.
///
/// **Why `languages` is configurable.** DragonKit ships seven locales, but an app only ships the
/// ones it has translated its *own* strings into — and the default listed all seven regardless.
/// ice-2 hit this first: PR #83 added Simplified Chinese and nothing else, so the shared picker
/// would have offered French, Japanese, Korean, Spanish and Traditional Chinese, and choosing one
/// would have translated the kit's four panes while leaving the other 234 strings in English. The
/// contributor's fix was to hand-roll a three-option picker in `GeneralSettingsPane`, which is
/// exactly the re-implementation CONFORMANCE.md forbids. Restricting the list is the config the
/// kit owed the app, in the same shape ``UninstallConfig`` uses for the uninstall checklist.
public struct LanguagePicker: View {
    @ObservedObject private var manager = LocalizationManager.shared
    private let languages: [DragonLanguage]
    private let onChange: ((DragonLanguage) -> Void)?

    /// - Parameters:
    ///   - languages: The languages this app has translated itself into. Defaults to every
    ///     language DragonKit ships, which is right for an app whose coverage matches the kit's.
    ///     `.system` is always offered and is filtered out of this list if passed.
    ///   - onChange: Run after the selection is applied and persisted, only when it actually
    ///     changed. Exists for apps whose own strings cannot switch live: SwiftUI String Catalogs
    ///     resolve against the process's preferred localizations, which are read once at launch,
    ///     so ice-2 mirrors the choice into `AppleLanguages` here and relaunches. An app using
    ///     ``L(_:)`` for its own strings needs none of that — ``dragonLocalized()`` switches it
    ///     in place — and should leave this `nil`.
    public init(
        languages: [DragonLanguage] = DragonLanguage.selectable,
        onChange: ((DragonLanguage) -> Void)? = nil
    ) {
        self.languages = languages
        self.onChange = onChange
    }

    /// The rows listed below "Automatic", factored out of ``body`` so it can be asserted without
    /// a view harness — the two rules it enforces are both invisible until they are wrong.
    ///
    /// `.system` is dropped because it is rendered separately, above the divider; an app passing
    /// it would otherwise get two "Automatic" rows. The current selection is appended when it
    /// falls outside the configured set, because narrowing that set in a later release orphans a
    /// persisted choice, and SwiftUI renders a `Picker` whose selection matches no tag as blank —
    /// leaving the user unable to see or leave the state they are in.
    static func offeredLanguages(
        configured: [DragonLanguage],
        selection: DragonLanguage
    ) -> [DragonLanguage] {
        let supported = configured.filter { $0 != .system }
        guard selection != .system, !supported.contains(selection) else { return supported }
        return supported + [selection]
    }

    public var body: some View {
        Picker(L("DragonKit.language.label"), selection: Binding(
            get: { manager.language },
            set: { newValue in
                // Guarded rather than left to `setLanguage`'s own no-op check, because SwiftUI
                // re-sends the current value on rebuild and `onChange` may relaunch the app.
                guard newValue != manager.language else { return }
                manager.setLanguage(newValue)
                onChange?(newValue)
            }
        )) {
            Text(L("DragonKit.language.system")).tag(DragonLanguage.system)
            Divider()
            ForEach(Self.offeredLanguages(configured: languages, selection: manager.language)) {
                language in
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
