import SwiftUI

/// A `NavigationSplitView` settings window driven by an ordered list of panes — the
/// data-driven generalization of ice-2's `SettingsView`. The host owns `selection`, so it
/// can persist the choice (e.g. `@AppStorage`) and open directly to a specific pane.
public struct SettingsShell: View {
    private let appName: String
    private let panes: [AnySettingsPane]
    @Binding private var selection: String?

    public init(appName: String, panes: [AnySettingsPane], selection: Binding<String?>) {
        self.appName = appName
        self.panes = panes
        self._selection = selection
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach(panes) { pane in
                        Label {
                            Text(L(pane.title))
                        } icon: {
                            Image(systemName: pane.systemImage)
                        }
                        .tag(pane.id as String?)
                    }
                } header: {
                    Text(appName)
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .padding(.bottom, 8)
                }
                .collapsible(false)
            }
            .navigationSplitViewColumnWidth(220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            if let selection, let pane = panes.first(where: { $0.id == selection }) {
                pane.view
            } else {
                Text(L("DragonKit.selectSetting"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Convenience that owns its own selection `@State` and renders `SettingsShell` — for the
/// simple case (the basic template) where the host doesn't need to persist or redirect.
public struct ManagedSettingsShell: View {
    private let appName: String
    private let panes: [AnySettingsPane]
    @State private var selection: String?

    public init(appName: String, panes: [AnySettingsPane], initialSelection: String? = nil) {
        self.appName = appName
        self.panes = panes
        _selection = State(initialValue: initialSelection ?? panes.first?.id)
    }

    public var body: some View {
        SettingsShell(appName: appName, panes: panes, selection: $selection)
    }
}
