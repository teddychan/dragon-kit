import AppKit
import SwiftUI

/// App-supplied configuration for the Uninstall flow.
public struct UninstallConfig {
    public let appName: String
    public let bundleID: String
    /// Extra UserDefaults suites to wipe (e.g. the settings suite from ``DragonSettingsStore``).
    public let suiteNames: [String]
    /// What the confirmation sheet lists as being removed.
    public let checklistItems: [String]

    public init(
        appName: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        suiteNames: [String] = [],
        checklistItems: [String]
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.suiteNames = suiteNames
        self.checklistItems = checklistItems
    }
}

/// Performs a complete self-uninstall: disable the login item, wipe the app's defaults
/// domains, delete leftover preference/saved-state files, move the app to the Trash, then
/// quit. Ported from ice-2's uninstall flow, generalized to any bundle id / suites.
@MainActor
public enum DragonUninstaller {
    public static func run(
        config: UninstallConfig,
        onComplete: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        LoginItem.setEnabled(false)

        let fileManager = FileManager.default
        var domains = config.suiteNames
        if !config.bundleID.isEmpty { domains.append(config.bundleID) }
        for name in domains {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }

        let library = fileManager.homeDirectoryForCurrentUser.appending(path: "Library")
        let leftovers = leftoverPaths(bundleID: config.bundleID, suiteNames: config.suiteNames, library: library)
        for url in leftovers {
            try? fileManager.removeItem(at: url)
        }
        // cfprefsd rewrites an emptied preference plist when the app exits, recreating the
        // file we just deleted. Delete the leftovers again from a detached process that runs
        // after we've quit, so nothing lingers. (Direct-download apps only — a sandboxed Mac
        // App Store app can't spawn processes and is removed by the App Store instead.)
        schedulePostExitCleanup(of: leftovers)

        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            Task { @MainActor in onComplete() }
        }
    }

    /// Preference plists (one per wiped domain — the bundle id and each settings suite) plus
    /// saved application state: everything a full uninstall must remove. Factored out so the
    /// path coverage can be tested without side effects.
    static func leftoverPaths(bundleID: String, suiteNames: [String], library: URL) -> [URL] {
        var domains = suiteNames
        if !bundleID.isEmpty { domains.append(bundleID) }
        var paths = domains.map { library.appending(path: "Preferences/\($0).plist") }
        if !bundleID.isEmpty {
            paths.append(library.appending(path: "Saved Application State/\(bundleID).savedState"))
        }
        return paths
    }

    /// Deletes `urls` from a detached shell that outlives this process, defeating cfprefsd's
    /// on-exit flush that would otherwise resurrect emptied preference plists.
    private static func schedulePostExitCleanup(of urls: [URL]) {
        guard !urls.isEmpty else { return }
        let script = "sleep 2; " + urls.map { "/bin/rm -rf \"\($0.path)\"" }.joined(separator: "; ")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
    }
}

/// Hosts ``UninstallView`` in a small window (Dragon apps are LSUIElement agents). Ported
/// from ice-2.
@MainActor
public final class UninstallWindowController {
    public static let shared = UninstallWindowController()
    private var window: NSWindow?

    private init() {}

    /// Present the confirmation sheet; `onConfirm` runs only if the user chooses Uninstall.
    public func present(config: UninstallConfig, onConfirm: @escaping () -> Void) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let view = UninstallView(
            config: config,
            onCancel: { [weak self] in self?.window?.close() },
            onUninstall: { [weak self] in
                self?.window?.close()
                onConfirm()
            }
        )
        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        win.styleMask = [.titled, .closable]
        win.title = ""
        win.isReleasedWhenClosed = false
        win.center()
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }
}

/// A destructive confirmation sheet that names exactly what uninstalling removes. Uninstall
/// (red) is left; Cancel (the default action) is right, so Return/Esc land on the safe
/// choice. Ported from ice-2.
public struct UninstallView: View {
    let config: UninstallConfig
    let onCancel: () -> Void
    let onUninstall: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 9))
                Text(String(format: L("DragonKit.uninstall.title"), config.appName))
                    .font(.title2).bold()
            }

            Text(String(format: L("DragonKit.uninstall.body"), config.appName))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(config.checklistItems, id: \.self) { checkRow($0) }
            }

            Text(L("DragonKit.uninstall.permissionsNote"))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button(role: .destructive) { onUninstall() } label: {
                    Text(L("DragonKit.uninstall.confirm")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Button(L("DragonKit.cancel")) { onCancel() }
                    .keyboardShortcut(.defaultAction) // Return/Esc → the safe choice
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 420)
    }

    private func checkRow(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }
}

/// Drop-in Uninstall pane: shows the confirmation directly (checklist of what's removed +
/// Uninstall) and, on confirm, runs ``DragonUninstaller`` — no separate window, so the whole
/// flow stays in the settings pane. Pass `onCancel` to also show a Cancel button (e.g. to
/// navigate back to another pane); omit it and no Cancel is shown.
public struct UninstallSettingsPane: SettingsPane {
    public let id = "uninstall"
    public let title = "DragonKit.pane.uninstall"
    public let systemImage = "trash"
    private let config: UninstallConfig
    private let onCancel: (() -> Void)?

    public init(config: UninstallConfig, onCancel: (() -> Void)? = nil) {
        self.config = config
        self.onCancel = onCancel
    }

    public var paneBody: some View { UninstallPaneView(config: config, onCancel: onCancel) }
}

private struct UninstallPaneView: View {
    let config: UninstallConfig
    let onCancel: (() -> Void)?

    var body: some View {
        DragonForm {
            DragonSection(LocalizedStringKey(L("DragonKit.uninstall.section"))) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(String(format: L("DragonKit.uninstall.title"), config.appName))
                        .font(.headline)
                    Text(String(format: L("DragonKit.uninstall.body"), config.appName))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(config.checklistItems, id: \.self) { item in
                            Label {
                                Text(item)
                            } icon: {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }

                    Text(L("DragonKit.uninstall.permissionsNote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            DragonUninstaller.run(config: config)
                        } label: {
                            Text(L("DragonKit.uninstall.confirm"))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        if let onCancel {
                            Button(L("DragonKit.cancel")) { onCancel() }
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
