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
/// backups. Uses ``DragonBackup`` for all logic. The pane's own preferences (the chosen folder's
/// path and its security-scoped bookmark) live in `standard` defaults — never the backed-up
/// suite — so a backup never captures backup settings.
public struct BackupSettingsPane: SettingsPane {
    public let id = "backup"
    public let title = "DragonKit.pane.backup"
    public let systemImage = "arrow.clockwise.circle"
    private let config: BackupConfig

    public init(config: BackupConfig) { self.config = config }

    public var paneBody: some View { BackupPaneView(config: config) }
}

/// The chosen-folder plumbing, kept out of the SwiftUI view so the bookmark round trip and the
/// precedence rules can be tested without rendering a pane (see `BackupPaneTests`).
///
/// **This is not the deferred folder-based backup shape.** CLAUDE.md defers generalizing
/// ``DragonBackup`` past a single UserDefaults suite, and README's roadmap lists "a user-picked
/// folder with a security-scoped bookmark" as part of that deferral. Nothing here reverses it:
/// ``DragonBackup`` still snapshots one suite and still knows nothing about folders-as-a-shape or
/// bookmarks. The pane already had a user-picked folder before this existed; all this does is make
/// the folder it already had survive relaunch.
enum BackupFolder {
    /// A resolved folder, plus whether the bookmark that produced it needs re-making.
    struct Resolution: Equatable {
        let url: URL
        /// True only when macOS resolved a bookmark but flagged it stale.
        let isStale: Bool
    }

    /// A security-scoped bookmark for `url`, or nil when one can't be made.
    ///
    /// The scope is held across the call because re-minting a bookmark from an already-resolved
    /// (stale) URL requires it; for a URL that carries no scope this is a no-op either way.
    static func makeBookmark(for url: URL) -> Data? {
        withSecurityScope(url) {
            try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    /// Resolve a security-scoped bookmark, or nil for data that isn't a usable one.
    ///
    /// Empty (`@AppStorage`'s default, i.e. the user never picked a folder), truncated and
    /// foreign-machine blobs all answer nil rather than throwing, because the caller's response to
    /// every one of them is the same: fall back to the next source. `URL(resolvingBookmarkData:)`
    /// throws on all three — it does not trap — so `try?` is the whole of the handling.
    static func resolve(bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        return (url, isStale)
    }

    /// Folder precedence: a resolved bookmark, else the legacy stored path, else
    /// ``DragonBackup/defaultFolder(appName:home:)``.
    ///
    /// The legacy path is still read because every install predating the bookmark has one and no
    /// bookmark: skipping it would silently drop those users back to the default folder and orphan
    /// every backup they had already made.
    static func folder(bookmark: Data, legacyPath: String, appName: String) -> Resolution {
        if let resolved = resolve(bookmark: bookmark) {
            return Resolution(url: resolved.url, isStale: resolved.isStale)
        }
        if !legacyPath.isEmpty {
            return Resolution(url: URL(fileURLWithPath: legacyPath, isDirectory: true), isStale: false)
        }
        return Resolution(url: DragonBackup.defaultFolder(appName: appName), isStale: false)
    }
}

@MainActor
private struct BackupPaneView: View {
    let config: BackupConfig
    @AppStorage private var folderPath: String
    @AppStorage private var folderBookmark: Data
    /// The folder file operations actually use — nil only until `.task` has resolved it.
    @State private var folder: URL?
    @State private var backups: [URL] = []
    @State private var restoreTarget: URL?
    @State private var notice: Notice?
    @State private var isBackingUp = false

    /// Payload for the one alert that reports both failures and the healthy "nothing changed" case.
    ///
    /// This pane already stacked two `.alert` modifiers on a single view (restore confirmation and
    /// error). SwiftUI presents one alert per view and silently drops the rest, so adding a third
    /// would have made one of the three simply never appear. Carrying the title as data collapses
    /// the two message alerts into one modifier — and stops a no-op being announced under
    /// "Backup Error", which reports a healthy result as a failure.
    private struct Notice: Equatable {
        let title: String
        let message: String
    }

    init(config: BackupConfig) {
        self.config = config
        _folderPath = AppStorage(wrappedValue: "", "DragonKit.backup.folderPath.\(config.suiteName)")
        _folderBookmark = AppStorage(wrappedValue: Data(), "DragonKit.backup.folderBookmark.\(config.suiteName)")
    }

    /// What the folder row shows. Deliberately built from the stored path rather than by resolving
    /// the bookmark: `URL(resolvingBookmarkData:)` can touch the disk, and `body` is no place for a
    /// network-volume round trip. The path is kept written on every choose precisely so this stays
    /// correct before — and without ever — resolving anything.
    private var displayPath: String {
        let url = folder ?? (folderPath.isEmpty
            ? DragonBackup.defaultFolder(appName: config.appName)
            : URL(fileURLWithPath: folderPath, isDirectory: true))
        return url.path(percentEncoded: false)
    }

    var body: some View {
        DragonForm {
            DragonSection(LocalizedStringKey(L("DragonKit.backup.folderSection"))) {
                LabeledContent {
                    Button(L("DragonKit.backup.choose")) { chooseFolder() }
                } label: {
                    Text(displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            DragonSection(LocalizedStringKey(L("DragonKit.backup.backupsSection"))) {
                HStack {
                    Button(L("DragonKit.backup.now")) { backUpNow() }
                        // A second press while the first write is still in flight would queue a
                        // duplicate run against the same suite instead of doing nothing useful.
                        .disabled(isBackingUp)
                    Button(L("DragonKit.backup.reveal")) { revealFolder() }
                }
                // Both actions need the resolved folder. Until it arrives they would be
                // silently-ignored clicks, which is worse than a button that says it isn't ready.
                .disabled(folder == nil)
                if backups.isEmpty {
                    Text(L("DragonKit.backup.none")).foregroundStyle(.secondary)
                } else {
                    ForEach(backups, id: \.self) { url in
                        LabeledContent {
                            Button(L("DragonKit.backup.restore")) { restoreTarget = url }
                            Button(role: .destructive) { delete(url) } label: {
                                Image(systemName: "trash")
                            }
                            // Every row's delete button is the same unlabelled trash glyph, and
                            // activating the wrong one destroys a backup for good. The filename is
                            // the only thing telling them apart, so VoiceOver has to say it.
                            .accessibilityLabel(
                                String(format: L("DragonKit.backup.deleteAccessibility"), url.lastPathComponent)
                            )
                        } label: {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .task { await load() }
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
            notice?.title ?? "",
            isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
        ) {
            Button(L("DragonKit.ok"), role: .cancel) { notice = nil }
        } message: {
            Text(notice?.message ?? "")
        }
    }

    /// Resolve the folder once, re-mint a stale bookmark, then list. Nothing else re-resolves:
    /// the only thing that changes the folder is `chooseFolder`, which already holds the URL it
    /// was just granted.
    private func load() async {
        let (resolved, refreshed) = await resolveFolder(
            bookmark: folderBookmark,
            legacyPath: folderPath,
            appName: config.appName
        )
        folder = resolved
        if let refreshed { folderBookmark = refreshed }
        await refresh()
    }

    private func refresh() async {
        guard let target = folder else { return }
        let found = await listBackups(in: target)
        // Drop a listing for a folder the user has since navigated away from. Choosing a new
        // folder while a slow network listing is in flight would otherwise let the old folder's
        // answer land last and overwrite the new folder's contents.
        guard target == folder else { return }
        backups = found
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = L("DragonKit.backup.choose")
        // runModal() is UI and stays on the main actor; only the file work below hops off it.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        // The path keeps being written even though the bookmark is the part that survives
        // relaunch: the folder row renders from it without resolving anything, and an install that
        // rolls back to a DragonKit without bookmarks still finds the folder the user chose.
        folderPath = url.path(percentEncoded: false)
        Task {
            // Clearing on failure is not tidiness: a kept-around previous bookmark outranks the
            // path just written, so it would silently send the next launch back to the very folder
            // the user replaced.
            folderBookmark = await makeBookmark(for: url) ?? Data()
            await refresh()
        }
    }

    private func revealFolder() {
        guard let target = folder else { return }
        Task {
            await createFolder(at: target)
            NSWorkspace.shared.activateFileViewerSelecting([target])
        }
    }

    private func backUpNow() {
        guard let target = folder, !isBackingUp else { return }
        isBackingUp = true
        Task {
            defer { isBackingUp = false }
            do {
                let outcome = try await performBackup(
                    suiteName: config.suiteName,
                    appName: config.appName,
                    folder: target,
                    appVersion: config.appVersion,
                    date: Date()
                )
                switch outcome {
                case .written:
                    await refresh()
                case .unchanged:
                    // A no-op is a healthy outcome, not a failure: the user asked for a backup and
                    // already has an identical one. Reporting it through the error alert — the
                    // only message alert this pane used to have — would title a successful check
                    // "Backup Error" and tell them something had gone wrong.
                    notice = Notice(
                        title: L("DragonKit.backup.unchangedTitle"),
                        message: L("DragonKit.backup.unchangedMessage")
                    )
                }
            } catch {
                notice = Notice(
                    title: L("DragonKit.backup.errorTitle"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func delete(_ url: URL) {
        guard let target = folder else { return }
        Task {
            await deleteBackup(at: url, in: target)
            await refresh()
        }
    }

    private func performRestore() {
        guard let url = restoreTarget, let target = folder else { return }
        restoreTarget = nil
        Task {
            do {
                try await restoreBackup(at: url, in: target, suiteName: config.suiteName)
                config.relaunch()
            } catch {
                notice = Notice(
                    title: L("DragonKit.backup.errorTitle"),
                    message: error.localizedDescription
                )
            }
        }
    }
}

// MARK: - Off-main file work

/// Run `body` with `folder`'s security scope held.
///
/// Under App Sandbox the grant `NSOpenPanel` hands over only travels with a resolved
/// security-scoped bookmark, and it is only in effect between these two calls. Without them
/// clipmenu-2's Mac App Store build can list and write the chosen folder in the session where the
/// user picked it and is refused in every session after — the user sees "Back Up Now" start failing
/// after a restart with no hint that re-picking the folder is the fix.
///
/// The return value is not a failure signal. It reports only whether a scope was actually entered,
/// and a URL carrying none — the default folder, or anything outside a sandbox — can legitimately
/// answer either way while the file work succeeds regardless. It is used solely to keep `stop`
/// balanced against `start`, which is what the API requires.
private func withSecurityScope<T>(_ folder: URL, _ body: () throws -> T) rethrows -> T {
    let entered = folder.startAccessingSecurityScopedResource()
    defer { if entered { folder.stopAccessingSecurityScopedResource() } }
    return try body()
}

// Every function below is a `nonisolated async` free function, and that is load-bearing rather
// than stylistic: under SE-0338 a nonisolated async function does not inherit its caller's actor,
// so calling one from the @MainActor pane above hops to the generic executor and the settings
// window keeps drawing. That is the whole fix — the folder is whatever the user picked in
// NSOpenPanel, and a network share or a stale mount can leave `contentsOfDirectory`,
// `createDirectory` and a plist write stalled for seconds, which on the main actor is a frozen
// window. `nonisolated` is spelled out even though a free function in this module already is one,
// so that adding `defaultIsolation: MainActor` to Package.swift later cannot quietly drag the file
// I/O back onto the main actor and silently un-fix this.
//
// They take only Sendable values (String, URL, Data, Date) and never a `UserDefaults`: the pane
// only ever uses `.standard`, so each call lets DragonBackup's default argument apply on the far
// side rather than sending a reference across the hop.

/// Resolve the pane's folder and, when the bookmark came back stale, mint a replacement.
///
/// Stale means macOS could still resolve the bookmark but its contents have moved on — the folder
/// was renamed, or the volume changed. The resolved URL is good; the stored blob is not, and
/// leaving it alone means resolving a steadily older bookmark on every launch until it stops
/// resolving at all. Both halves happen here so both stay off the main actor.
private nonisolated func resolveFolder(
    bookmark: Data,
    legacyPath: String,
    appName: String
) async -> (folder: URL, refreshedBookmark: Data?) {
    let resolution = BackupFolder.folder(bookmark: bookmark, legacyPath: legacyPath, appName: appName)
    let refreshed = resolution.isStale ? BackupFolder.makeBookmark(for: resolution.url) : nil
    return (resolution.url, refreshed)
}

private nonisolated func makeBookmark(for url: URL) async -> Data? {
    BackupFolder.makeBookmark(for: url)
}

private nonisolated func listBackups(in folder: URL) async -> [URL] {
    withSecurityScope(folder) { DragonBackup.listBackups(in: folder) }
}

/// Write-if-changed, then prune only when something was actually written.
///
/// Both halves share one hop and one security scope. Pruning is deliberately skipped for
/// `.unchanged`: nothing was added, so trimming to the retention limit there would delete an older
/// snapshot in response to a no-op.
private nonisolated func performBackup(
    suiteName: String,
    appName: String,
    folder: URL,
    appVersion: String,
    date: Date
) async throws -> DragonBackup.BackupOutcome {
    try withSecurityScope(folder) {
        let outcome = try DragonBackup.writeBackupIfChanged(
            suiteName: suiteName,
            appName: appName,
            to: folder,
            appVersion: appVersion,
            date: date
        )
        if case .written = outcome {
            DragonBackup.prune(in: folder, keeping: DragonBackup.defaultRetentionLimit)
        }
        return outcome
    }
}

private nonisolated func createFolder(at folder: URL) async {
    withSecurityScope(folder) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
}

/// The scope belongs to the folder the user granted, not to the individual file inside it, so the
/// delete is wrapped in the folder's scope rather than the backup's.
private nonisolated func deleteBackup(at url: URL, in folder: URL) async {
    withSecurityScope(folder) {
        try? FileManager.default.removeItem(at: url)
    }
}

private nonisolated func restoreBackup(at url: URL, in folder: URL, suiteName: String) async throws {
    try withSecurityScope(folder) {
        try DragonBackup.restore(from: url, suiteName: suiteName)
    }
}
