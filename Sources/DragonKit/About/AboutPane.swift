import SwiftUI

/// The shared About view, reproducing ice-2's About pane: centered icon, name, version,
/// copyright; a links section; and a credits section.
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
            if !content.links.isEmpty || content.acknowledgementsURL != nil {
                DragonSection {
                    linkRows
                }
            }
            if !content.credits.isEmpty {
                DragonSection {
                    creditRows
                }
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
        // Keyed on position, not on `AboutLink.id`: that id is a fresh `UUID()` per instance, and
        // apps hand us content rebuilt from scratch each time — sample-app's
        // `AboutConfig.content` is a computed `static var`, and the settings root rebuilds its
        // panes on every language change. Keying on `id` therefore handed SwiftUI all-new
        // identities on each rebuild, so it tore down and recreated every link row instead of
        // updating it.
        //
        // Position rather than `url`, which was the first fix here: `url` is stable across a
        // rebuild but not guaranteed *unique*, so two links to the same destination would
        // collapse into one row — the identical bug being fixed for `creditRows` one section
        // down. Position is both stable and unique, and it gives the whole pane one identity
        // rule. These rows are stateless, so nothing depends on identity following a reorder.
        ForEach(Array(content.links.enumerated()), id: \.offset) { _, link in
            LabeledContent {
                Link(link.detail, destination: link.url)
            } label: {
                Label(link.title, systemImage: link.systemImage)
            }
        }
        if let ack = content.acknowledgementsURL {
            Button {
                NSWorkspace.shared.open(ack)
            } label: {
                Label(L("DragonKit.acknowledgements"), systemImage: "doc.text")
            }
        }
    }

    @ViewBuilder
    private var creditRows: some View {
        // Keyed on position, not on `label`: labels legitimately repeat — "License: MIT" beside
        // "License: Apache-2.0", or two "Built with" lines — and `ForEach` requires unique ids,
        // so a label key silently collapsed such a pair into one row and dropped the rest.
        // `credits` is a fixed, ordered, app-supplied list, so its index is a sound identity.
        ForEach(Array(content.credits.enumerated()), id: \.offset) { _, credit in
            LabeledContent(credit.label) { Text(credit.value) }
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
