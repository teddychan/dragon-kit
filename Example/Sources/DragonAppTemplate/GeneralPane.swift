import SwiftUI
import DragonKit

/// The app's General pane — real, persisted settings bound to ``SettingsModel``. The demo
/// toggle exists so Backup & Restore has app-specific data to save and bring back.
struct GeneralPane: SettingsPane {
    let id = "general"
    let title = "app.pane.general"
    let systemImage = "gearshape"
    let model: SettingsModel

    var paneBody: some View { GeneralPaneView(model: model) }
}

private struct GeneralPaneView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        DragonForm {
            DragonSection(LocalizedStringKey(L("app.general.startup"))) {
                Toggle(L("app.general.launchAtLogin"), isOn: $model.launchAtLogin)
                    .dragonAnnotation(LocalizedStringKey(L("app.general.launchAtLoginHint")))
            }
            DragonSection(LocalizedStringKey(L("app.general.menuBar"))) {
                Toggle(L("app.general.showInMenuBar"), isOn: $model.showInMenuBar)
                    .dragonAnnotation(LocalizedStringKey(L("app.general.showInMenuBarHint")))
            }
            DragonSection(LocalizedStringKey(L("app.general.demo"))) {
                Toggle(L("app.general.playSound"), isOn: $model.playSound)
                    .dragonAnnotation(LocalizedStringKey(L("app.general.playSoundHint")))
            }
            // The shared language picker — every DragonKit app drops this in to get the
            // full 7-language switcher (live, no restart).
            DragonSection(LocalizedStringKey(L("app.general.languageSection"))) {
                LanguagePicker()
            }
        }
    }
}
