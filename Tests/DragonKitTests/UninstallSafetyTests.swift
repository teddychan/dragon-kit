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
}
