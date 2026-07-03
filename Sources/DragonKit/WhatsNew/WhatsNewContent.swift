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
    public let version: String
    public let date: String
    public let summary: String
    public let sections: [ChangeSection]

    public init(version: String, date: String, summary: String = "", sections: [ChangeSection] = []) {
        self.version = version
        self.date = date
        self.summary = summary
        self.sections = sections
    }
}
