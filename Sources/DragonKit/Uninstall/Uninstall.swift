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
    ///
    /// **Never pass a token flat.** Dragon debug builds are deliberately re-id'd
    /// (`<release id>.debug`) so they can't touch the installed copy's settings or TCC grants —
    /// but a cask token is not bundle-scoped, so a flat token throws that away: uninstalling the
    /// debug build would run `brew uninstall --cask <token> --force` and delete the *release* app
    /// from /Applications, along with its receipt. Only the app knows which id Homebrew installed,
    /// so the app names it — but the comparison itself belongs to the kit: build the value with
    /// ``UninstallConfig/caskToken(_:ifBundleIs:actual:)``.
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

public extension UninstallConfig {
    /// `token`, but only when the running bundle really is the one Homebrew installed —
    /// otherwise `nil`, so no cask is touched.
    ///
    /// `brew uninstall --cask <token> --force` is not bundle-scoped: it deletes whatever the
    /// receipt points at, which is the *release* app in /Applications, and the Dragon casks
    /// carry `uninstall quit:` so it terminates that app first. A debug build (re-id'd
    /// `<release id>.debug` by convention) must therefore never supply one. The sample app and
    /// ice-2 each hand-wrote `bundleID == releaseBundleID ? token : nil` for that; the
    /// comparison lives here instead so the next app doesn't write a third version of it.
    ///
    /// It fails closed, including on the case both hand-written versions got wrong: a debug id,
    /// another app's id, and a *missing* id all return `nil`. A missing id is how the sample app
    /// leaked one — its `Bundle.main.bundleIdentifier ?? releaseBundleID` fallback answered the
    /// release id for a build that couldn't state its own, which is precisely the build that has
    /// no business authorising a delete. Two empty strings don't match each other either.
    static func caskToken(
        _ token: String,
        ifBundleIs releaseBundleID: String,
        actual: String? = Bundle.main.bundleIdentifier
    ) -> String? {
        guard let actual, !actual.isEmpty, actual == releaseBundleID else { return nil }
        return token
    }
}

/// Whether a complete uninstall may run at all, decided before anything destructive happens.
enum UninstallPreflight: Equatable {
    case proceed
    /// The running bundle cannot state an identity, or states one the configuration disagrees
    /// with. Nothing may be authorised on a guess about which of the two is right.
    case identityUnverified
    /// More than one bundle carrying this exact identity exists on disk, so the state keyed on
    /// that identity cannot be attributed to the copy being uninstalled.
    case duplicateCopies([URL])
}

/// Performs a complete self-uninstall: disable the login item, wipe the app's defaults
/// domains, delete leftover preference/saved-state files, move the app to the Trash, then
/// quit. Ported from ice-2's uninstall flow, generalized to any bundle id / suites.
@MainActor
public enum DragonUninstaller {
    /// Whether this uninstall may touch anything, decided from identity alone — no filesystem
    /// and no LaunchServices access of its own, so the whole decision is testable against a
    /// fixed world.
    ///
    /// `recycle()` moves the *running* bundle and is path-scoped, which is safe. Everything
    /// either side of it is keyed on the bundle *identity*: the login item, the defaults
    /// domains, the preference and saved-state plists, the configured cleanup paths, and the
    /// Homebrew token. Two bundles sharing an identity share every one of those, and nothing in
    /// them records which copy they belong to — so with a second copy present there is no
    /// answer to "whose settings are these", only a guess. This refuses to guess.
    ///
    /// ``UninstallConfig/caskToken(_:ifBundleIs:actual:)`` already fails closed on the *wrong*
    /// identity, and that is a different question from this one: it asks who you are, not
    /// whether you are the only one. A local Release-configuration build carries the release
    /// identity honestly and passes it.
    ///
    /// `canonicalize` returns the resolved URL for a bundle that exists and `nil` for one that
    /// does not, which is what makes dead LaunchServices records — this machine held 19 for a
    /// single live copy — incapable of blocking an uninstall.
    ///
    /// **What this covers, exactly.** The candidates are the running bundle, the copies
    /// LaunchServices has registered, and the copies currently running. It cannot prove that no
    /// unlaunched, unregistered same-identity bundle exists somewhere on disk: a copy that was
    /// built and never opened, restored from a backup, or unpacked into a folder macOS has not
    /// indexed is invisible to every API here, and only a whole-disk scan would see it — which
    /// is not a thing an uninstall may do. So this closes the reachable cases, not the set of
    /// all conceivable ones.
    nonisolated static func preflight(
        configBundleID: String,
        actualBundleID: String?,
        currentBundleURL: URL,
        discoveredCopies: [URL],
        canonicalize: (URL) -> URL?
    ) -> UninstallPreflight {
        // No fallback from a missing id to the configured one. That fallback is exactly how the
        // sample app leaked a cask token: it answered the release id for the one build that
        // could not name itself, which is the build with the least business authorising a
        // delete. A disagreement is a stop, not a hint about which to believe.
        guard let actualBundleID, !actualBundleID.isEmpty, actualBundleID == configBundleID else {
            return .identityUnverified
        }

        // The running bundle is resolved separately and is mandatory. Folding it in with the
        // discovered URLs let a failure to canonicalize it be *skipped* like any other dead
        // path, and the count could then reach zero — a fail-open branch inside a decision
        // whose whole purpose is failing closed. A bundle that cannot be resolved to a path on
        // disk cannot be compared against anything, so it authorises nothing.
        guard let current = canonicalize(currentBundleURL) else {
            return .identityUnverified
        }

        // Seeded with the current bundle, so "discovery returned nothing" can never read as
        // "there are no copies" — discovery legitimately omits copies, which is why it is not
        // trusted as the whole picture.
        var seen: Set<URL> = [current]
        var copies: [URL] = [current]
        for url in discoveredCopies {
            guard let canonical = canonicalize(url) else { continue }
            if seen.insert(canonical).inserted { copies.append(canonical) }
        }

        guard copies.count <= 1 else {
            // Sorted by path so the order the user is shown does not depend on the order
            // LaunchServices happened to answer in.
            return .duplicateCopies(copies.sorted { $0.path < $1.path })
        }
        return .proceed
    }

    /// The production canonicalization behind ``preflight(…)``: one bundle reachable by several
    /// names resolves to one path, and a path that no longer exists resolves to nothing.
    ///
    /// Finder alias files are resolved explicitly, before symlinks. An alias is not a symlink —
    /// it is a regular file whose contents are a bookmark — so `resolvingSymlinksInPath()` does
    /// not follow one, and alone it would have counted an alias pointing at the running bundle
    /// as a *second* copy and blocked a legitimate uninstall.
    ///
    /// Existence is checked last, on the fully resolved path, because that is what demotes a
    /// dead LaunchServices record to something incapable of blocking an uninstall.
    nonisolated static func canonicalBundleURL(_ url: URL) -> URL? {
        let dealiased = (try? URL(resolvingAliasFileAt: url, options: [.withoutUI])) ?? url
        let resolved = dealiased.resolvingSymlinksInPath().standardizedFileURL
        return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
    }

    /// Every same-identity bundle the system will admit to, from both directories that know.
    ///
    /// LaunchServices is not sufficient on its own: a copy built independently under `.build`
    /// was absent from `urlsForApplications(withBundleIdentifier:)` *while it was running*, and
    /// `NSRunningApplication` found it. A running duplicate is the case that matters most — it
    /// is the one actively holding the shared defaults open — so missing it would have left the
    /// hazard in place exactly when it is realest.
    /// Both sources are parameters so the case that motivated the second one — registered comes
    /// back empty, running does not — is reachable from a test without launching an app.
    nonisolated static func discoverBundleCopies(
        withIdentifier identifier: String,
        registered: (String) -> [URL] = {
            NSWorkspace.shared.urlsForApplications(withBundleIdentifier: $0)
        },
        running: (String) -> [URL] = {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).compactMap(\.bundleURL)
        }
    ) -> [URL] {
        registered(identifier) + running(identifier)
    }

    private static let logger = Logger(subsystem: "com.dragonapp.DragonKit", category: "Uninstall")

    public static func run(
        config: UninstallConfig,
        deleteOptionalData: Bool = false,
        onComplete: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        run(
            config: config,
            deleteOptionalData: deleteOptionalData,
            onComplete: onComplete,
            recycle: { url, report in
                NSWorkspace.shared.recycle([url]) { _, error in report(error?.localizedDescription) }
            },
            scheduleCleanup: { urls, cask in schedulePostExitCleanup(of: urls, cask: cask) },
            reportFailure: { appName, reason in
                reportBundleRemovalFailure(appName: appName, reason: reason)
            },
            preflight: {
                let actual = Bundle.main.bundleIdentifier
                return preflight(
                    configBundleID: config.bundleID,
                    actualBundleID: actual,
                    currentBundleURL: Bundle.main.bundleURL,
                    // Asked for the *actual* running identity, never the configured one: the two
                    // disagreeing is itself a stop, and querying the configured id would search
                    // for copies of a bundle this process has not shown itself to be. An absent
                    // id short-circuits to `.identityUnverified` without a query at all.
                    discoveredCopies: actual.map { discoverBundleCopies(withIdentifier: $0) } ?? [],
                    canonicalize: canonicalBundleURL
                )
            },
            reportBlocked: { decision in
                reportUninstallBlocked(config: config, decision: decision)
            }
        )
    }

    /// ``run(config:deleteOptionalData:onComplete:)`` with its three irreversible effects — the
    /// Trash move, the detached post-exit cleanup and the failure alert — passed in, so the
    /// *order* between them is testable without recycling a real bundle, spawning a real shell,
    /// or blocking a test process on `NSAlert.runModal()`, which never returns there.
    ///
    /// An overload rather than three defaulted parameters on the public entry point: a public
    /// function's default argument may not name an internal declaration ("static method
    /// 'schedulePostExitCleanup' is internal and cannot be referenced from a default argument
    /// value"), so those defaults would have had to publish the kit's internals — and with them
    /// a supported way for an app to substitute its own Trash move or swallow the failure alert.
    /// The public signature is untouched; the five apps keep compiling.
    static func run(
        config: UninstallConfig,
        deleteOptionalData: Bool,
        onComplete: @escaping @MainActor () -> Void,
        recycle: @escaping @MainActor (URL, @escaping @Sendable (String?) -> Void) -> Void,
        scheduleCleanup: @escaping @MainActor ([URL], String?) -> Void,
        reportFailure: @escaping @MainActor (_ appName: String, _ reason: String) -> Void,
        preflight: @MainActor () -> UninstallPreflight,
        reportBlocked: @MainActor (UninstallPreflight) -> Void,
        // Defaulted rather than threaded through every call site: the only reason it is a
        // parameter at all is that disabling the login item is the *first* destructive step, so
        // "a blocked run does not reach it" is the assertion that proves the gate is genuinely
        // in front of the teardown rather than merely in front of the parts that were injected.
        setLoginItemEnabled: (Bool) -> Void = LoginItem.setEnabled
    ) {
        // First, and before anything that cannot be undone. Every step below this line is keyed
        // on the bundle identity rather than on this bundle's path, so they are only correct
        // while this is the sole bundle carrying that identity — see ``preflight(…)``. Telling
        // the user is the one thing a blocked uninstall may do.
        let decision = preflight()
        guard decision == .proceed else {
            reportBlocked(decision)
            return
        }

        setLoginItemEnabled(false)

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
        let cask = config.homebrewCask
        recycle(Bundle.main.bundleURL) { failureReason in
            Task { @MainActor in
                if let failureReason {
                    // Nothing else runs. The app is still installed, and the post-exit cleanup
                    // below would not merely misdescribe that — with a cask it would enforce the
                    // opposite.
                    reportFailure(appName, failureReason)
                    return
                }
                // Scheduled here, and only here. The detached shell ends in
                // `brew uninstall --cask --force`, which quits the app (the Dragon casks carry
                // `uninstall quit:`) and deletes the bundle; spawning it before the recycle, as
                // this did until #50, ordered that behind a fixed `sleep 2` instead of behind
                // the move having worked. A failed recycle then showed "Uninstall Incomplete",
                // deliberately did not quit — and was overruled two seconds later by brew
                // removing the app the user had just been told was still installed.
                //
                // No cleanup is scheduled on the failure path, and that costs nothing real.
                // The detached `rm` exists to beat cfprefsd's rewrite of the plists emptied
                // above — but its `sleep` is measured from the spawn, not from app exit, and on
                // this path the app deliberately does not quit. The old ordering therefore ran
                // that `rm` while the app was still alive, and cfprefsd wrote the emptied
                // domains back at the eventual real exit anyway. There was never durable
                // protection here to lose. (Direct-download apps only either way: a sandboxed
                // Mac App Store build can't spawn processes and is removed by the App Store.)
                scheduleCleanup(leftovers, cask)
                onComplete()
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

    /// Tells the user why nothing was removed, and does *not* run `onComplete` — quitting here
    /// would look exactly like the successful uninstall that did not happen.
    ///
    /// Both messages say plainly that no data was removed, because the alert arrives after the
    /// user pressed a confirmed, irreversible-sounding button and the honest answer is that it
    /// did nothing. The paths go in the duplicate message rather than the log alone: the user
    /// cannot act on "there is another copy" without being told where it is.
    private static func reportUninstallBlocked(config: UninstallConfig, decision: UninstallPreflight) {
        let alert = NSAlert()
        alert.alertStyle = .warning

        switch decision {
        case .proceed:
            return
        case .identityUnverified:
            // Identifiers are public; the bundle path is not — see the duplicate case below.
            logger.error(
                """
                Uninstall blocked: running bundle \(Bundle.main.bundleURL.path, privacy: .private) \
                reports id \(Bundle.main.bundleIdentifier ?? "<none>", privacy: .public), \
                configured id is \(config.bundleID, privacy: .public)
                """
            )
            alert.messageText = L("DragonKit.uninstall.blockedIdentityTitle")
            alert.informativeText = String(
                format: L("DragonKit.uninstall.blockedIdentityMessage"), config.appName
            )
        case .duplicateCopies(let urls):
            // The count is public; the paths are not. A full bundle path contains the account
            // name and whatever the user called their folders, and OSLog `.public` is what puts
            // a string into sysdiagnose archives and anything else collecting the log.
            logger.error(
                """
                Uninstall blocked: \(urls.count, privacy: .public) bundles share id \
                \(config.bundleID, privacy: .public) — \
                \(urls.map(\.path).joined(separator: ", "), privacy: .private)
                """
            )
            alert.messageText = L("DragonKit.uninstall.blockedDuplicatesTitle")
            alert.informativeText = String(
                format: L("DragonKit.uninstall.blockedDuplicatesMessage"), config.appName
            )
            // The paths go in a bounded, scrollable accessory rather than in `informativeText`.
            // NSAlert grows to fit its text without limit: 42 paths measured 1640pt tall and 100
            // measured 3496pt, which is an alert taller than the display with its buttons off
            // screen — unusable exactly when the user most needs to read it. Nothing is dropped;
            // the list scrolls and stays selectable so it can be copied.
            alert.accessoryView = duplicateCopyAccessory(urls)
        }

        alert.addButton(withTitle: L("DragonKit.ok"))
        if let icon = NSApp.applicationIconImage { alert.icon = icon }
        alert.runModal()
    }

    /// How a discovered copy's path is shown: the user's home abbreviated to `~`.
    ///
    /// Every row of this list starts `/Users/<account name>/` otherwise, which is both the least
    /// informative part of the path and the part that pushes the part that distinguishes one
    /// copy from another off the readable width.
    nonisolated static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// The complete list, one path per line. Never truncated — the accessory scrolls instead,
    /// because a user told "there is another copy" cannot act on it without being told which.
    nonisolated static func duplicateCopyList(_ urls: [URL]) -> String {
        urls.map(displayPath).joined(separator: "\n")
    }

    /// Height of the path list, bounded regardless of how many copies were found.
    ///
    /// The bound is the whole point: an unbounded NSAlert with 100 paths measured 3496pt, taller
    /// than any display, with its buttons off screen. Small lists still shrink to fit, so the
    /// ordinary two-copy case does not get a mostly-empty scroll box.
    nonisolated static func duplicateCopyListHeight(lineCount: Int) -> CGFloat {
        let lineHeight: CGFloat = 15
        let padding: CGFloat = 8
        let natural = CGFloat(max(lineCount, 1)) * lineHeight + padding
        return min(max(natural, 34), 150)
    }

    /// Internal rather than private so a test can assert the assembled view is actually bounded,
    /// not merely that the arithmetic feeding it is.
    static func duplicateCopyAccessory(_ urls: [URL]) -> NSScrollView {
        let width: CGFloat = 380
        let height = duplicateCopyListHeight(lineCount: urls.count)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textView.string = duplicateCopyList(urls)
        textView.isEditable = false
        // Selectable on purpose: the actionable next step is to go and move one of these, and
        // retyping a path by hand off an alert is how the wrong one gets moved.
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false
        return scrollView
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
    /// That it runs *after* the bundle is in the Trash is enforced by **where ``run`` spawns it**
    /// — inside the successful-recycle callback — and by nothing else. The `sleep` cannot carry
    /// that: it only holds the shell back until this process has exited. The claim used to be
    /// written here while the spawn sat above the recycle call, which left
    /// `brew uninstall --cask --force` (a command that quits the app and deletes the bundle)
    /// riding a two-second delay rather than a successful move, and overruling the "Uninstall
    /// Incomplete" alert on the path where the move had failed.
    ///
    /// With the ordering actually enforced, brew's only remaining job by the time it runs is
    /// clearing its own receipt, and `NSWorkspace.recycle` never races it for the bundle.
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
    ///
    /// One caller, and it has to stay that way: the successful-recycle branch of ``run``. The
    /// shell can also uninstall the Homebrew cask, which deletes the app, so anywhere earlier
    /// makes that contingent on a `sleep` instead of on the Trash move having worked.
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
