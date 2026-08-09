import Testing
import Foundation
@testable import DragonKit

/// Guards on the uninstall flow's two unsafe edges. Path coverage lives in
/// `DragonUninstallerTests`; this suite is only about *how* the post-exit cleanup runs.
///
/// The post-exit cleanup is a detached `rm -rf`. It used to be assembled by interpolating each
/// path into a `/bin/sh -c` string — `"/bin/rm -rf \"\(url.path)\""` joined with `; `. Double
/// quotes stop word-splitting but not `$`, backticks, backslashes or a closing `"`. The inputs
/// were app-controlled so nothing was exploitable in practice, which is exactly why it survived;
/// these tests exist so it can't come back quietly.
@Suite struct UninstallSafetyTests {
    /// A path made of everything that turns into shell syntax when it's pasted into a script:
    /// a closing double quote, `$(…)` command substitution, backticks, a backslash and spaces.
    /// Under the old string-concatenation form this path executed commands; under argv passing
    /// it is inert text that `rm` receives verbatim.
    private static let hostilePath =
        #"/tmp/dk uninstall/" $(touch /tmp/pwned) `id` \x/com.acme.app.plist"#
    private static let ordinaryPath = "/Users/x/Library/Preferences/com.acme.app.settings.plist"

    @MainActor @Test func pathsAreArgumentsNeverShellText() {
        let urls = [
            URL(fileURLWithPath: Self.hostilePath),
            URL(fileURLWithPath: Self.ordinaryPath),
        ]
        let args = DragonUninstaller.postExitCleanupArguments(for: urls)

        // argv shape: -c, the script, $0, then one slot per path.
        #expect(args.count == urls.count + 3)
        #expect(args[0] == "-c")
        #expect(args[2] == "sh", "the literal sh fills $0 so the first path lands in $1, not $0")

        // The script is a fixed constant. If a future change interpolates a path back into it,
        // this literal stops matching and the test fails — that is the whole point of pinning it.
        #expect(args[1] == DragonUninstaller.postExitCleanupScript)
        #expect(args[1].contains(#"/bin/rm -rf "$@""#))

        // Each path is its own argv element, byte-for-byte, and appears nowhere else — in
        // particular not inside the script, where the shell would parse it.
        #expect(Array(args.dropFirst(3)) == urls.map(\.path))
        #expect(args[3] == Self.hostilePath)
        for path in urls.map(\.path) {
            #expect(args.filter { $0.contains(path) }.count == 1)
        }

        // Nothing path-derived leaks into the script: no fragment of the hostile path, and none
        // of the metacharacters that only a concatenated script could have picked up.
        #expect(!args[1].contains("com.acme.app"))
        #expect(!args[1].contains("touch"))
        #expect(!args[1].contains("`"))
        #expect(args[1].contains(#""$@""#))
        // Every `$` in the script must be one of the shell's own expansions — never something
        // built from app-supplied text. Counting them stopped working once the brew half was
        // added, so enumerate instead: an unexpected `$name` is what a concatenated script
        // would look like.
        let allowedExpansions = ["$@", "${\(DragonUninstaller.cleanupCaskEnvironmentKey):-}",
                                 "$\(DragonUninstaller.cleanupCaskEnvironmentKey)", "$brew"]
        var stripped = args[1]
        for expansion in allowedExpansions.sorted(by: { $0.count > $1.count }) {
            stripped = stripped.replacingOccurrences(of: expansion, with: "")
        }
        #expect(!stripped.contains("$"), "unexpected shell expansion left in the script: \(stripped)")

        // `sleep 2` survives: cfprefsd rewrites an emptied preference plist on app exit, so the
        // delete has to run after we've quit. Dropping it silently un-fixes that.
        #expect(args[1].hasPrefix("sleep 2\n"))
    }

    /// Empty in, empty out — the contract `schedulePostExitCleanup(of:)` relies on to spawn no
    /// process when there is nothing to delete. An `rm -rf "$@"` with no arguments is harmless,
    /// but launching a shell to do nothing isn't work an uninstall should be doing.
    @MainActor @Test func emptyInputProducesNoArguments() {
        #expect(DragonUninstaller.postExitCleanupArguments(for: []).isEmpty)
    }

    /// One path is still a full argv, not a degenerate case that falls back to interpolation.
    @MainActor @Test func singlePathStillUsesArgumentPassing() {
        let url = URL(fileURLWithPath: Self.ordinaryPath)
        let args = DragonUninstaller.postExitCleanupArguments(for: [url])

        #expect(args == ["-c", DragonUninstaller.postExitCleanupScript, "sh", url.path])
    }

    // MARK: - Homebrew receipt

    /// An app that deletes itself leaves Homebrew's records untouched — the receipt still says
    /// the cask is installed and `Caskroom/<token>/<version>/<App>.app` becomes a dangling
    /// symlink — so `brew install` then refuses outright for an app that isn't there. Teddy hit
    /// exactly that after uninstalling Dragon Sample App 1.3.0 from inside the app.
    @MainActor @Test func caskTokenTravelsInTheEnvironmentNeverInTheScript() {
        let hostile = #"clipmenu-2"; rm -rf /; echo ""#
        let environment = DragonUninstaller.postExitCleanupEnvironment(cask: hostile)

        #expect(environment[DragonUninstaller.cleanupCaskEnvironmentKey] == hostile)
        // The guarantee: the token is never text the shell parses. Same rule the paths follow.
        #expect(!DragonUninstaller.postExitCleanupScript.contains(hostile))
        #expect(!DragonUninstaller.postExitCleanupScript.contains("clipmenu-2"))
    }

    /// A nil or empty cask must actively *remove* the key. Merely not setting it would let an
    /// inherited value from the parent environment make an app with no cask configured
    /// uninstall someone else's.
    @MainActor @Test func noCaskRemovesTheKeyRatherThanLeavingItInherited() {
        for empty in [nil, ""] {
            let environment = DragonUninstaller.postExitCleanupEnvironment(cask: empty)
            #expect(environment[DragonUninstaller.cleanupCaskEnvironmentKey] == nil)
        }
    }

    /// The brew call is guarded on the variable being set, so a shell with no cask runs only the
    /// path deletion.
    @MainActor @Test func theScriptOnlyTouchesBrewWhenTheCaskVariableIsSet() {
        let script = DragonUninstaller.postExitCleanupScript
        #expect(script.contains("[ -n \"${\(DragonUninstaller.cleanupCaskEnvironmentKey):-}\" ]"))
        // Ordering is load-bearing: brew removes the app bundle itself, so running it before the
        // Trash move would make NSWorkspace.recycle fail on an already-gone bundle and fire the
        // "Uninstall Incomplete" alert on a successful uninstall.
        let rmIndex = script.range(of: "/bin/rm -rf")!.lowerBound
        let brewIndex = script.range(of: "uninstall --cask")!.lowerBound
        #expect(rmIndex < brewIndex)
        // A GUI app inherits no shell PATH, so brew must be probed at absolute locations.
        #expect(script.contains("/opt/homebrew/bin/brew"))
        #expect(script.contains("/usr/local/bin/brew"))
    }

    /// A cask with nothing left to delete still needs the shell — clearing the receipt is reason
    /// enough on its own.
    @MainActor @Test func aCaskAloneStillSchedulesCleanup() {
        #expect(DragonUninstaller.postExitCleanupArguments(for: [], cask: "clipmenu-2").isEmpty == false)
        #expect(DragonUninstaller.postExitCleanupArguments(for: [], cask: nil).isEmpty)
        #expect(DragonUninstaller.postExitCleanupArguments(for: [], cask: "").isEmpty)
    }

    @MainActor @Test func configDefaultsToNoHomebrewCask() {
        #expect(UninstallConfig(appName: "Acme", checklistItems: ["x"]).homebrewCask == nil)
        #expect(UninstallConfig(appName: "Acme", checklistItems: ["x"], homebrewCask: "acme").homebrewCask == "acme")
    }

    // MARK: - Who may hold a cask token

    /// `brew uninstall --cask --force` deletes the *release* app, so only the build Homebrew
    /// installed may name a token. ``UninstallConfig/caskToken(_:ifBundleIs:actual:)`` fails
    /// closed on everything else — including the missing id that the sample app's
    /// `Bundle.main.bundleIdentifier ?? releaseBundleID` fallback used to answer *with the
    /// release id*, handing the delete to the one build that couldn't even state who it was.
    @Test func aCaskTokenIsOnlyIssuedToTheExactReleaseBundle() {
        let release = "com.dragonapp.dragon-sample-app"
        let token = "dragon-sample-app"
        func issued(to actual: String?) -> String? {
            UninstallConfig.caskToken(token, ifBundleIs: release, actual: actual)
        }

        #expect(issued(to: release) == token)
        #expect(issued(to: release + ".debug") == nil, "the debug re-id is the whole reason this exists")
        #expect(issued(to: "com.dragonapp.clipmenu-2") == nil)
        #expect(issued(to: nil) == nil, "a missing id must authorise nothing")
        #expect(issued(to: "") == nil, "and neither may two empty strings match each other")
    }
}

/// The uninstall's sequencing, which is a safety property in its own right: the post-exit
/// cleanup can end in `brew uninstall --cask --force`, and the Dragon casks carry
/// `uninstall quit:`, so that shell quits the app and deletes the bundle.
///
/// It used to be spawned *before* `NSWorkspace.recycle` was even called, ordered behind the
/// script's `sleep 2` and nothing else. When the Trash move failed the kit showed "Uninstall
/// Incomplete" and deliberately stayed running — and two seconds later brew removed the app the
/// user had just been told was still installed. These tests hold the cleanup to the successful
/// branch.
///
/// They drive the internal `run` overload, whose only reason to exist is that all three of its
/// injected effects are unrunnable here: no bundle is recycled, no shell is spawned, and the
/// failure alert — `NSAlert.runModal()`, which never returns in a test process — is never built.
@Suite struct UninstallSequencingTests {
    /// Records what happened and in which order. One object, so nothing is captured `var`.
    @MainActor private final class Effects {
        var order: [String] = []
        var recycled: [URL] = []
        var cleanupPaths: [URL] = []
        var cleanupCask: String?
        var failureReason: String?

        /// The Trash-move callback hops back through `Task { @MainActor in … }`, so let that
        /// task run before asserting. Bounded and sleepless: yield until the run reaches one of
        /// its two terminal effects.
        func settle() async {
            for _ in 0..<100 where !order.contains(where: { $0 == "complete" || $0 == "failure" }) {
                await Task.yield()
            }
        }
    }

    /// A config whose every *real* side effect is inert: no extra cleanup paths, no settings
    /// suite, and a bundle id that owns no defaults domain, no preference plist and no saved
    /// state, so `run`'s own `removeItem` calls find nothing to delete.
    private static func config(cask: String?) -> UninstallConfig {
        UninstallConfig(
            appName: "Sequencing",
            bundleID: "com.dragonapp.dragonkit.tests.sequencing",
            checklistItems: ["x"],
            homebrewCask: cask
        )
    }

    /// `run` with the Trash move stubbed to report `failureReason` (nil = the bundle made it).
    @MainActor private static func run(cask: String?, failureReason: String?) async -> Effects {
        let effects = Effects()
        DragonUninstaller.run(
            config: config(cask: cask),
            deleteOptionalData: false,
            onComplete: { effects.order.append("complete") },
            recycle: { url, report in
                effects.order.append("recycle")
                effects.recycled.append(url)
                report(failureReason)
            },
            scheduleCleanup: { urls, scheduledCask in
                effects.order.append("cleanup")
                effects.cleanupPaths = urls
                effects.cleanupCask = scheduledCask
            },
            reportFailure: { _, reason in
                effects.order.append("failure")
                effects.failureReason = reason
            }
        )
        await effects.settle()
        return effects
    }

    /// The cleanup is scheduled only once the bundle is in the Trash, and before the app quits —
    /// `onComplete` terminates by default, so anything after it may never run.
    @MainActor @Test func cleanupIsScheduledAfterTheTrashMoveAndBeforeTheAppQuits() async {
        let effects = await Self.run(cask: "dragon-sample-app", failureReason: nil)

        #expect(effects.order == ["recycle", "cleanup", "complete"])
        #expect(effects.recycled == [Bundle.main.bundleURL])
        #expect(effects.cleanupCask == "dragon-sample-app")
        // The paths handed over are the leftovers `run` computed, not an empty stand-in.
        #expect(effects.cleanupPaths.contains {
            $0.path.hasSuffix("Preferences/com.dragonapp.dragonkit.tests.sequencing.plist")
        })
        #expect(effects.failureReason == nil)
    }

    /// A failed Trash move schedules nothing. This is the finding: brew must not be able to
    /// delete an app the user was just told is still installed.
    @MainActor @Test func aFailedTrashMoveSchedulesNoCleanupAtAll() async {
        let effects = await Self.run(cask: "dragon-sample-app", failureReason: "Permission denied")

        #expect(effects.order == ["recycle", "failure"])
        #expect(!effects.order.contains("cleanup"))
        #expect(effects.cleanupPaths.isEmpty)
        #expect(effects.cleanupCask == nil)
        #expect(effects.failureReason == "Permission denied")
    }

    /// And it does not quit: `onComplete` terminates by default, which would hide the failure
    /// behind a window that just disappeared.
    @MainActor @Test func onCompleteRunsOnlyWhenTheBundleReachedTheTrash() async {
        let failed = await Self.run(cask: nil, failureReason: "Read-only volume")
        #expect(!failed.order.contains("complete"))

        let succeeded = await Self.run(cask: nil, failureReason: nil)
        #expect(succeeded.order == ["recycle", "cleanup", "complete"])
    }
}
