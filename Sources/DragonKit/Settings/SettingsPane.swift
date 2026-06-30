import SwiftUI

/// A registrable settings pane. Modules (or apps) conform; the settings shell renders
/// them from an ordered array. Uses `paneBody` (not `body`) so a type can be both a
/// `SettingsPane` and a `View` without collision.
public protocol SettingsPane: Identifiable where ID == String {
    var id: String { get }
    var title: LocalizedStringKey { get }
    var systemImage: String { get }
    associatedtype PaneBody: View
    @MainActor @ViewBuilder var paneBody: PaneBody { get }
}

/// Type-erased pane for storage in a homogeneous array and the shell's sidebar.
public struct AnySettingsPane: Identifiable {
    public let id: String
    public let title: LocalizedStringKey
    public let systemImage: String
    let view: AnyView

    @MainActor
    public init<P: SettingsPane>(_ pane: P) {
        self.id = pane.id
        self.title = pane.title
        self.systemImage = pane.systemImage
        self.view = AnyView(pane.paneBody)
    }
}
