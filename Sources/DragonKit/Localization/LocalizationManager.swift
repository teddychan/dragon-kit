import Foundation
import SwiftUI

/// The languages DragonKit ships strings for, plus `.system` (follow the OS). `rawValue` is
/// the `.lproj` code, so it maps directly to a bundle localization.
public enum DragonLanguage: String, CaseIterable, Sendable, Identifiable {
    case system
    case en
    case es
    case fr
    case ja
    case ko
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    public var id: String { rawValue }

    /// The `.lproj` code to resolve strings from, or `nil` for `.system` (use the OS order).
    public var localeCode: String? { self == .system ? nil : rawValue }

    /// The pickable languages (everything except `.system`).
    public static var selectable: [DragonLanguage] { allCases.filter { $0 != .system } }

    /// Endonym shown in the picker — each language named in itself, so it reads correctly no
    /// matter which language is active. (`.system` is localized separately.)
    @MainActor public var displayName: String {
        switch self {
        case .system: return L("DragonKit.language.system")
        case .en: return "English"
        case .es: return "Español"
        case .fr: return "Français"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        }
    }
}

public extension Notification.Name {
    /// Posted (with the new ``DragonLanguage`` as `object`) when the selected language changes,
    /// so non-SwiftUI surfaces (e.g. an AppKit menu bar) can rebuild themselves live.
    static let dragonLanguageChanged = Notification.Name("DragonKit.languageChanged")
}

/// Owns the app's selected language at runtime and resolves the matching `.lproj` bundles, so
/// ``L(_:table:)`` can return strings for the current choice — and the UI can switch language
/// without a restart. Shared singleton; the selection persists across launches.
@MainActor
public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    private let defaultsKey = "DragonKit.language"
    private var bundleCache: [String: Bundle] = [:]

    /// The current selection. Defaults to `.system`.
    @Published public private(set) var language: DragonLanguage

    /// Bundle holding the app's own `Localizable.strings` (the ``L(_:)`` fallback). Defaults to
    /// `.main`; apps that ship strings in a SwiftPM resource bundle can point this at `.module`.
    public var appStringsBundle: Bundle = .main {
        didSet { bundleCache.removeAll() }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)
        self.language = raw.flatMap(DragonLanguage.init(rawValue:)) ?? .system
    }

    /// Change the language, persist it, and notify observers (SwiftUI via `@Published`, AppKit
    /// via ``Notification/Name/dragonLanguageChanged``).
    public func setLanguage(_ newValue: DragonLanguage) {
        guard newValue != language else { return }
        bundleCache.removeAll()
        language = newValue
        if newValue == .system {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: .dragonLanguageChanged, object: newValue)
    }

    /// The `.lproj` codes to try, best first: the explicit choice, or the OS order for `.system`.
    private var preferredCodes: [String] {
        if let code = language.localeCode { return [code] }
        return Bundle.main.preferredLocalizations
    }

    /// Locale identifier for date/number formatting under the current language.
    public var localeIdentifier: String {
        language.localeCode ?? Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Resolve `base` to the `.lproj` sub-bundle for the current language, falling back to
    /// `base` itself when none of the preferred codes are available.
    func localizedBundle(for base: Bundle) -> Bundle {
        let key = "\(base.bundlePath)|\(language.rawValue)"
        if let cached = bundleCache[key] { return cached }
        var resolved = base
        for code in preferredCodes {
            if let b = Self.lprojBundle(code, in: base) {
                resolved = b
                break
            }
        }
        bundleCache[key] = resolved
        return resolved
    }

    /// Find `<code>.lproj` inside `base`, matching case-insensitively — SwiftPM lowercases
    /// region subtags (e.g. `zh-Hans` → `zh-hans`) when it copies resources into the bundle.
    static func lprojBundle(_ code: String, in base: Bundle) -> Bundle? {
        if let path = base.path(forResource: code, ofType: "lproj") { return Bundle(path: path) }
        guard let resourceURL = base.resourceURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: resourceURL, includingPropertiesForKeys: nil)
        else { return nil }
        let match = entries.first {
            $0.pathExtension == "lproj"
                && $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(code) == .orderedSame
        }
        return match.flatMap { Bundle(path: $0.path) }
    }
}
