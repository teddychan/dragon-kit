import SwiftUI

/// The shared About view: centered icon, name, version and copyright; a links section; and a
/// Credits section.
///
/// This view renders and decides nothing else. Row titles, SF Symbols, ordering and detail text
/// are assembled by ``AboutContent/linkRows`` and ``AboutContent/creditRows`` as plain data —
/// which is also what makes the canon testable, since SwiftUI itself is not.
public struct AboutPane: View {
    private let content: AboutContent

    public init(content: AboutContent) {
        self.content = content
    }

    public var body: some View {
        DragonForm {
            DragonSection {
                header
            }
            DragonSection {
                linkRows
            }
            DragonSection(LocalizedStringKey(L("DragonKit.about.credits"))) {
                creditRows
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 6) {
            if let icon = content.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    // Purely decorative: the app name is the next element down as real text, so
                    // letting VoiceOver announce the icon as well only adds a stop that repeats
                    // what the following line already says.
                    .accessibilityHidden(true)
            }
            Text(content.appName)
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text(content.versionString)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(content.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var linkRows: some View {
        // Keyed on position. `AboutLinkRow.id` is stable across rebuilds, but two rows may
        // legitimately share a destination, and a `url` key silently collapsed such a pair into
        // one row — the identical bug that hit credits when they were keyed on `label`. The rows
        // are a fixed, ordered, kit-built list, so position is both stable and unique, and it
        // gives the whole pane one identity rule.
        ForEach(Array(content.linkRows.enumerated()), id: \.offset) { _, row in
            LabeledContent {
                Link(row.detail, destination: row.url)
            } label: {
                Label(row.title, systemImage: row.systemImage)
            }
        }
    }

    @ViewBuilder
    private var creditRows: some View {
        // Position again, and for the original reason: labels legitimately repeat — two
        // attributions can share a component name — and `ForEach` ids must be unique, so a label
        // key dropped every row after the first duplicate.
        ForEach(Array(content.creditRows.enumerated()), id: \.offset) { _, row in
            LabeledContent(row.label) { Text(row.value) }
        }
    }
}

/// Drop-in About pane for the settings shell.
public struct AboutSettingsPane: SettingsPane {
    public let id = "about"
    public let title = "DragonKit.pane.about"
    public let systemImage = "info.circle"
    private let content: AboutContent

    public init(content: AboutContent) {
        self.content = content
    }

    public var paneBody: some View { AboutPane(content: content) }
}
