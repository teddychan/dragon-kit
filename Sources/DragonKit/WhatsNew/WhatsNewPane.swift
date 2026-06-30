import SwiftUI

/// The shared "What's New" view: title, "version · date", an optional summary, then
/// grouped change sections (Added / Changed / Fixed …) with bulleted entries.
public struct WhatsNewPane: View {
    private let content: WhatsNewContent

    public init(content: WhatsNewContent) {
        self.content = content
    }

    public var body: some View {
        DragonForm {
            DragonSection {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("DragonKit.whatsNew.title"))
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("\(content.version) · \(content.date)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if !content.summary.isEmpty {
                        Text(content.summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            ForEach(content.sections) { section in
                DragonSection(LocalizedStringKey(section.kind.label)) {
                    ForEach(section.entries, id: \.self) { entry in
                        Label {
                            Text(entry).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: section.kind.systemImage)
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
    }
}

/// Drop-in What's New pane for the settings shell.
public struct WhatsNewSettingsPane: SettingsPane {
    public let id = "whatsnew"
    public let title: LocalizedStringKey = "What's New"
    public let systemImage = "sparkles"
    private let content: WhatsNewContent

    public init(content: WhatsNewContent) {
        self.content = content
    }

    public var paneBody: some View { WhatsNewPane(content: content) }
}
