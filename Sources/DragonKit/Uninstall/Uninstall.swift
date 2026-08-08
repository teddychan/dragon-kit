import AppKit
import OSLog
import SwiftUI

/// App-supplied configuration for the Uninstall flow.
public struct UninstallConfig {
    public let appName: String
    public let bundleID: String
    /// Extra UserDefaults suites to wipe (e.g. the settings suite from ``DragonSettingsStore``).
    public let suiteNames: [String]
    /// What the confirmation sheet lists as being removed.
    public let checklistItems: [String]
    /// Optional, default-off "also delete user data" choice rendered in the confirmation
    /// (e.g. "Also delete clipboard history and snippets"). Only when the user turns it on
    /// are `paths` deleted too. The label is shown as-is — localize it in the app.
    public let optionalDataToggle: (label: String, paths: [URL])?
    /// App-specific paths removed on every uninstall (e.g. support files under
    /// `~/Library/Application Support/<app>`, `Caches/<bundle-id>`,
    /// `HTTPStorages/<bundle-id>`) — things the shared teardown can't know about.
    public let extraCleanupPaths: [URL]
    /// Homebrew cask token (e.g. `"clipmenu-2"`), when the app is distributed as a cask.
    ///
    /// An app that deletes itself leaves Homebrew's records untouched, because Homebrew never
    /// watches the filesystem: its receipt still says the cask is installed, and
    /// `Caskroom/<token>/<version>/<App>.app` is a symlink that is now dangling. The user then
    /// gets `brew install` refusing outright — "already installed" — for an app that isn't there,
    /// with nothing pointing at `brew reinstall` as the way out. Supplying the token lets the
    /// post-exit cleanup clear that record so the two views of the world agree again.
    ///
    /// Best-effort and direct-download only: a sandboxed Mac App Store build can't spawn
    /// processes, and is removed by the App Store anyway.
    public let homebrewCask: String?

    public init(
        appName: String,
        bundleID: String = Bundle.main.bundleIdentifier ?? "",
        suiteNames: [String] = [],
        checklistItems: [String],
        optionalDataToggle: (label: String, paths: [URL])? = nil,
        extraCleanupPaths: [URL] = [],
        homebrewCask: String? = nil
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.suiteNames = suiteNames
        self.checklistItems = checklistItems
        self.optionalDataToggle = optionalDataToggle
        self.extraCleanupPaths = extraCleanupPaths
        self.homebrewCask = homebrewCask
    }
}

/// Performs a complete self-uninstall: disable the login item, wipe the app's defaults
/// domains, delete leftover preference/saved-state files, move the app to the Trash, then
/// quit. Ported from ice-2's uninstall flow, generalized to any bundle id / suites.
@MainActor
public enum DragonUninstaller {
    private static let logger = Logger(subsystem: "com.dragonapp.DragonKit", category: "Uninstall")

    public static func run(
        config: UninstallConfig,
        deleteOptionalData: Bool = false,
        onComplete: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        LoginItem.setEnabled(false)

        let fileManager = FileManager.default

        // App-specific cleanup first (support files, caches — and, when the user opted in,
        // their data), best-effort so a locked file can't strand a half-uninstalled app.
        for url in cleanupPaths(config: config, deleteOptionalData: deleteOptionalData) {
            try? fileManager.removeItem(at: url)
        }

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
        schedulePostExitCleanup(of: leftovers, cask: config.homebrewCask)

        // The teardown above is irreversible and has already happened, so the Trash move is the
        // one step whose failure the user has to hear about: on a read-only volume, an
        // MDM-managed or SIP-protected path, or a plain permission denial, the app is still
        // installed but every setting and the login item are gone. Discarding this error meant
        // `onComplete()` — which terminates by default — reported a successful uninstall that
        // hadn't happened, and the user was told nothing.
        //
        // Only the description crosses the hop: `any Error` isn't Sendable, and the string is
        // all the log line needs.
        let appName = config.appName
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
            let failureReason = error?.localizedDescription
            Task { @MainActor in
                guard let failureReason else {
                    onComplete()
                    return
                }
                reportBundleRemovalFailure(appName: appName, reason: failureReason)
            }
        }
    }

    /// Tells the user the app is still installed, and does *not* run `onComplete` — quitting
    /// here would hide the failure behind a window that just disappeared.
    ///
    /// The raw `localizedDescription` goes to OSLog only. It's an internal error description
    /// (`NSCocoaErrorDomain` file-system copy, typically), not copy anyone can act on, and the
    /// standard this kit is held to forbids surfacing those as user-facing text; the alert says
    /// what to do instead.
    private static func reportBundleRemovalFailure(appName: String, reason: String) {
        logger.error("Moving the app bundle to the Trash failed: \(reason, privacy: .public)")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("DragonKit.uninstall.failedTitle")
        alert.informativeText = String(format: L("DragonKit.uninstall.failedMessage"), appName)
        alert.addButton(withTitle: L("DragonKit.ok"))
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        alert.runModal()
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

    /// The app-specific paths to remove: `extraCleanupPaths` always, plus the optional-data
    /// paths when the user opted in. Factored out so the coverage can be tested without
    /// side effects.
    static func cleanupPaths(config: UninstallConfig, deleteOptionalData: Bool) -> [URL] {
        var paths = config.extraCleanupPaths
        if deleteOptionalData, let toggle = config.optionalDataToggle {
            paths += toggle.paths
        }
        return paths
    }

    /// The `/bin/sh` script the post-exit cleanup runs. A fixed constant, and it must stay one:
    /// no path is ever interpolated into it. `"$@"` re-expands the arguments as separate words
    /// with no further parsing, so a path containing `"`, `$`, a backtick, a backslash or a
    /// space is passed through literally.
    ///
    /// `sleep 2` is load-bearing, not a fudge: cfprefsd flushes and rewrites an emptied
    /// preference plist when the app exits, recreating the file `run` just deleted. The delete
    /// has to land after we're gone.
    /// Environment variable carrying the Homebrew cask token to the detached shell.
    ///
    /// It travels here rather than in the script text for the same reason the paths travel in
    /// argv: nothing app-supplied is ever parsed as shell syntax.
    static let cleanupCaskEnvironmentKey = "DRAGON_UNINSTALL_CASK"

    /// Environment for the detached shell. Inherits the process environment (brew needs `HOME`),
    /// then sets or *removes* the cask key — removing matters, because an inherited value would
    /// otherwise make an app with no cask configured uninstall someone else's.
    static func postExitCleanupEnvironment(cask: String?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        if let cask, !cask.isEmpty {
            environment[cleanupCaskEnvironmentKey] = cask
        } else {
            environment.removeValue(forKey: cleanupCaskEnvironmentKey)
        }
        return environment
    }

    /// The `/bin/sh` script the post-exit cleanup runs. A fixed constant, and it must stay one:
    /// neither a path nor a cask token is ever interpolated into it.
    ///
    /// The `brew` half exists because an app that deletes itself leaves Homebrew's records
    /// untouched — Homebrew never watches the filesystem, so its receipt still claims the cask
    /// is installed and `brew install` then refuses outright for an app that isn't there.
    ///
    /// It runs *after* the bundle is already in the Trash, and that ordering is the whole design:
    /// `brew uninstall --cask` deletes the app itself, so doing this first would make
    /// `NSWorkspace.recycle` fail on a bundle that was already gone and fire the "Uninstall
    /// Incomplete" alert on an uninstall that had actually succeeded. By this point brew's only
    /// remaining job is clearing its own receipt.
    ///
    /// A GUI app inherits no shell `PATH`, so the two standard prefixes are probed explicitly
    /// (Apple silicon, then Intel). Errors are swallowed on purpose: the app is gone either way
    /// and there is no UI left to report into.
    static let postExitCleanupScript = #"""
    sleep 2
    /bin/rm -rf "$@"
    if [ -n "${DRAGON_UNINSTALL_CASK:-}" ]; then
      for brew in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        if [ -x "$brew" ]; then
          "$brew" uninstall --cask --force "$DRAGON_UNINSTALL_CASK" >/dev/null 2>&1 && break
        fi
      done
    fi
    exit 0
    """#

    /// argv for the detached cleanup shell — paths as *arguments*, never as script text.
    ///
    /// This used to be `"/bin/rm -rf \"\(url.path)\""` joined with `; `. Double quotes stop
    /// word-splitting but not `$`, backticks, backslashes or a closing `"`, so a path with any
    /// of those in it became shell syntax in a recursive delete. Today's inputs are
    /// app-controlled (bundle id, suite names, the home directory) and no live exploit existed,
    /// but the rule is that paths and URLs are untrusted input — and the safe form is one line.
    ///
    /// The literal `sh` is `$0` for `sh -c`; the paths land in `$1`…`$n`, which is what `"$@"`
    /// expands. Empty in, empty out: nothing to delete *and* no cask means there is nothing to
    /// run, and ``schedulePostExitCleanup(of:cask:)`` spawns no process at all. A cask with no
    /// leftover paths still runs — `rm -rf` with no operands is a silent no-op under `-f`, and
    /// clearing Homebrew's receipt is reason enough on its own.
    static func postExitCleanupArguments(for urls: [URL], cask: String? = nil) -> [String] {
        let hasCask = !(cask ?? "").isEmpty
        guard !urls.isEmpty || hasCask else { return [] }
        return ["-c", postExitCleanupScript, "sh"] + urls.map(\.path)
    }

    /// Deletes `urls` from a detached shell that outlives this process, defeating cfprefsd's
    /// on-exit flush that would otherwise resurrect emptied preference plists.
    private static func schedulePostExitCleanup(of urls: [URL], cask: String?) {
        let arguments = postExitCleanupArguments(for: urls, cask: cask)
        guard !arguments.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        process.environment = postExitCleanupEnvironment(cask: cask)
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
    @State private var deleteOptionalData = false

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

                    if let toggle = config.optionalDataToggle {
                        Toggle(toggle.label, isOn: $deleteOptionalData)
                            .toggleStyle(.switch)
                    }

                    Text(L("DragonKit.uninstall.permissionsNote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button(role: .destructive) {
                            DragonUninstaller.run(config: config, deleteOptionalData: deleteOptionalData)
                        } label: {
                            Text(L("DragonKit.uninstall.confirm"))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        if let onCancel {
                            Button(L("DragonKit.cancel")) { onCancel() }
                                // §5A: Cancel is the default action, so Return/Esc hits the
                                // safe choice — matching ``UninstallView``, the window variant.
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
