import SwiftUI
import DragonKit

/// The app's General pane — real, persisted settings bound to ``SettingsModel``. The demo
/// toggle exists so Backup & Restore has app-specific data to save and bring back.
struct GeneralPane: SettingsPane {
    let id = "general"
    let title: LocalizedStringKey = "General"
    let systemImage = "gearshape"
    let model: SettingsModel

    var paneBody: some View { GeneralPaneView(model: model) }
}

private struct GeneralPaneView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        DragonForm {
            DragonSection("Startup") {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                    .dragonAnnotation("Start DragonKit Sample automatically when you log in.")
            }
            DragonSection("Menu Bar") {
                Toggle("Show in menu bar", isOn: $model.showInMenuBar)
                    .dragonAnnotation("Hide the menu-bar icon. If it's hidden at launch, Settings opens automatically so you can turn it back on.")
            }
            DragonSection("Demo") {
                Toggle("Play sound on action", isOn: $model.playSound)
                    .dragonAnnotation("A sample app-specific setting — included so Backup & Restore has real data to save.")
            }
        }
    }
}
