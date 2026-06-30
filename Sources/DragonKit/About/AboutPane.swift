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
        ForEach(content.links) { link in
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
                Label("Acknowledgements", systemImage: "doc.text")
            }
        }
    }

    @ViewBuilder
    private var creditRows: some View {
        ForEach(content.credits, id: \.label) { credit in
            LabeledContent(credit.label) { Text(credit.value) }
        }
    }
}

/// Drop-in About pane for the settings shell.
public struct AboutSettingsPane: SettingsPane {
    public let id = "about"
    public let title: LocalizedStringKey = "About"
    public let systemImage = "info.circle"
    private let content: AboutContent

    public init(content: AboutContent) {
        self.content = content
    }

    public var paneBody: some View { AboutPane(content: content) }
}
