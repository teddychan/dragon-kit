import Foundation

/// One category of changes within a release (Added / Changed / Fixed / …).
public struct ChangeSection: Identifiable {
    public enum Kind: String, CaseIterable, Sendable {
        case added, changed, fixed, removed, improved, security

        /// Uppercased section header, e.g. "ADDED".
        public var label: String { rawValue.uppercased() }

        /// Localization key for the section header, resolved via ``L(_:)``.
        public var localizationKey: String { "DragonKit.whatsNew.kind.\(rawValue)" }

        /// SF Symbol shown beside each entry in this section.
        public var systemImage: String {
            switch self {
            case .added: "plus.circle"
            case .changed: "slider.horizontal.3"
            case .fixed: "wrench.and.screwdriver"
            case .removed: "minus.circle"
            case .improved: "wand.and.stars"
            case .security: "lock.shield"
            }
        }
    }

    public let id = UUID()
    public let kind: Kind
    public let entries: [String]

    public init(kind: Kind, entries: [String]) {
        self.kind = kind
        self.entries = entries
    }
}

/// App-supplied release notes for the "What's New" pane.
public struct WhatsNewContent {
    /// Deliberately **not public**. ``WhatsNewPane`` rendered this string verbatim, so whatever
    /// an app typed is what shipped: ice-2 and spectacle-2 passed the raw plist value and lost
    /// the `v` prefix that About showed, while yahoo-keykey-2 and the sample app hardcoded a
    /// literal that would silently disagree with the bundle on the next release.
    ///
    /// Only ``displayVersion`` is public, and it is always normalized — so no un-prefixed version
    /// string is reachable from outside the module and a future pane cannot render one. That, not
    /// the tests, is what enforces the prefix.
    let version: String
    public let date: String
    public let summary: String
    public let sections: [ChangeSection]

    /// The version as shown in the UI: exactly one leading `v`.
    public var displayVersion: String { DragonVersion.display(version) }

    /// - Parameter version: defaults to the bundle's `CFBundleShortVersionString`, so apps stop
    ///   hardcoding it. Pass one only to show notes for a release other than the current build.
    public init(
        version: String? = nil,
        date: String,
        summary: String = "",
        sections: [ChangeSection] = [],
        bundle: Bundle = .main
    ) {
        self.version = version
            ?? bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0.0"
        self.date = date
        self.summary = summary
        self.sections = sections
    }
}
