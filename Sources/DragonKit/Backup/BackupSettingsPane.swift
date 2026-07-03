import AppKit
import SwiftUI

/// App-supplied configuration for the Backup & Restore pane.
public struct BackupConfig {
    public let appName: String
    /// The UserDefaults suite that holds the app's settings (see ``DragonSettingsStore``).
    public let suiteName: String
    public let appVersion: String
    /// Called after a successful restore so the app can relaunch to pick up the new values.
    public let relaunch: () -> Void

    public init(appName: String, suiteName: String, appVersion: String, relaunch: @escaping () -> Void) {
        self.appName = appName
        self.suiteName = suiteName
        self.appVersion = appVersion
        self.relaunch = relaunch
    }
}

/// Backup & Restore pane: choose a folder, back up now, and restore/delete existing
/// backups. Uses ``DragonBackup`` for all logic. The pane's own preferences (chosen folder,
/// auto-backup flag) live in `standard` defaults — never the backed-up suite — so a backup
/// never captures backup settings.
public struct BackupSettingsPane: SettingsPane {
    public let id = "backup"
    public let title: LocalizedStringKey = "Backup & Restore"
    public let systemImage = "arrow.clockwise.circle"
    private let config: BackupConfig

    public init(config: BackupConfig) { self.config = config }

    public var paneBody: some View { BackupPaneView(config: config) }
}

private struct BackupPaneView: View {
    let config: BackupConfig
    @AppStorage private var folderPath: String
    @AppStorage private var autoBackup: Bool
    @State private var backups: [URL] = []
    @State private var restoreTarget: URL?
    @State private var errorMessage: String?

    init(config: BackupConfig) {
        self.config = config
        _folderPath = AppStorage(wrappedValue: "", "DragonKit.backup.folderPath.\(config.suiteName)")
        _autoBackup = AppStorage(wrappedValue: true, "DragonKit.backup.auto.\(config.suiteName)")
    }

    private var folder: URL {
        folderPath.isEmpty
            ? DragonBackup.defaultFolder(appName: config.appName)
            : URL(fileURLWithPath: folderPath, isDirectory: true)
    }

    var body: some View {
        DragonForm {
            DragonSection(LocalizedStringKey("DragonKit.backup.folderSection")) {
                LabeledContent {
                    Button(L("DragonKit.backup.choose")) { chooseFolder() }
                } label: {
                    Text(folder.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Toggle(L("DragonKit.backup.autoOnQuit"), isOn: $autoBackup)
                    .dragonAnnotation(LocalizedStringKey("DragonKit.backup.autoOnQuitHint"))
            }

            DragonSection(LocalizedStringKey("DragonKit.backup.backupsSection")) {
                HStack {
                    Button(L("DragonKit.backup.now")) { backUpNow() }
                    Button(L("DragonKit.backup.reveal")) { revealFolder() }
                }
                if backups.isEmpty {
                    Text(L("DragonKit.backup.none")).foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.self) { url in
                        LabeledContent {
                            Button(L("DragonKit.backup.restore")) { restoreTarget = url }
                            Button(role: .destructive) { delete(url) } label: {
                                Image(systemName: "trash")
                            }
                        } label: {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .task { refresh() }
        .alert(
            L("DragonKit.backup.restoreConfirmTitle"),
            isPresented: Binding(get: { restoreTarget != nil }, set: { if !$0 { restoreTarget = nil } })
        ) {
            Button(L("DragonKit.backup.restore"), role: .destructive) { performRestore() }
            Button(L("DragonKit.cancel"), role: .cancel) { restoreTarget = nil }
        } message: {
            Text(L("DragonKit.backup.restoreConfirmMessage"))
        }
        .alert(
            L("DragonKit.backup.errorTitle"),
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button(L("DragonKit.ok"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func refresh() {
        backups = DragonBackup.listBackups(in: folder)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("DragonKit.backup.choose")
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path(percentEncoded: false)
            refresh()
        }
    }

    private func revealFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    private func backUpNow() {
        do {
            try DragonBackup.writeBackup(
                suiteName: config.suiteName,
                appName: config.appName,
                to: folder,
                appVersion: config.appVersion,
                date: Date()
            )
            DragonBackup.prune(in: folder, keeping: DragonBackup.defaultRetentionLimit)
            refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        refresh()
    }

    private func performRestore() {
        guard let url = restoreTarget else { return }
        restoreTarget = nil
        do {
            try DragonBackup.restore(from: url, suiteName: config.suiteName)
            config.relaunch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
