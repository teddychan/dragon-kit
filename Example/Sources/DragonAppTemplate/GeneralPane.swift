import SwiftUI
import DragonKit

struct GeneralPane: SettingsPane {
    let id = "general"
    let title: LocalizedStringKey = "General"
    let systemImage = "gearshape"

    var paneBody: some View {
        DragonForm {
            DragonSection("General") {
                Toggle("Launch at login", isOn: .constant(false))
                    .dragonAnnotation("Placeholder — wire this up in a real app.")
            }
        }
    }
}
