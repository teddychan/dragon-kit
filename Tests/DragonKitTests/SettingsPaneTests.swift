import Testing
import SwiftUI
@testable import DragonKit

private struct FakePane: SettingsPane {
    let id: String
    let title: LocalizedStringKey
    let systemImage: String
    var paneBody: some View { Text(verbatim: id) }
}

@MainActor
@Suite struct SettingsPaneTests {
    @Test func anySettingsPanePreservesIdentity() {
        let pane = FakePane(id: "general", title: "General", systemImage: "gearshape")
        let erased = AnySettingsPane(pane)
        #expect(erased.id == "general")
        #expect(erased.systemImage == "gearshape")
    }

    @Test func arrayPreservesOrder() {
        let panes = [
            AnySettingsPane(FakePane(id: "a", title: "A", systemImage: "1.circle")),
            AnySettingsPane(FakePane(id: "b", title: "B", systemImage: "2.circle")),
        ]
        #expect(panes.map(\.id) == ["a", "b"])
    }
}
