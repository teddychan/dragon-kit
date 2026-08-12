#!/usr/bin/env python3
"""Tests for dragon-conformance.py.

A checker nobody tested is a checker that silently passes everything — which is exactly the
failure mode this whole spec exists to prevent. So every rule gets a fixture that MUST fail
(proving the rule bites) and the compliant fixture MUST pass (proving no false positives).

    python3 Scripts/test_conformance.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(HERE)
CHECKER = os.path.join(HERE, "dragon-conformance.py")

# A minimal app that satisfies every rule. Individual tests mutate a copy of it.
COMPLIANT_MENU = """import AppKit
import DragonKit

@MainActor
final class AppMenuController {
    func buildMenu() -> NSMenu {
        DragonAppMenu.menu(DragonAppMenu.Config(
            appName: "Test App",
            onAbout: { },
            onSettings: { },
            onCheckForUpdates: { }
        ))
    }
}
"""
COMPLIANT_PANES = """import SwiftUI
import DragonKit

@MainActor
enum Panes {
    static func all(updater: DragonUpdater) -> [AnySettingsPane] {
        [
            AnySettingsPane(GeneralPane()),
            AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),
            AnySettingsPane(BackupSettingsPane(config: .init(appName: "T", suiteName: "s",
                                                            appVersion: "1", relaunch: { }))),
            AnySettingsPane(WhatsNewSettingsPane(content: .init(version: "v1", date: "d",
                                                               summary: "s", sections: []))),
            AnySettingsPane(UpdatesSettingsPane(updater: updater)),
            AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),
            AnySettingsPane(UninstallSettingsPane(config: UninstallConfig(appName: "T"))),
        ]
    }
}

struct GeneralPane: SettingsPane {
    let id = "general"
    let title = "app.pane.general"
    let systemImage = "gearshape"
    var paneBody: some View {
        DragonForm { DragonSection { Toggle("On", isOn: .constant(true)) } }
    }
}
"""
COMPLIANT_STRINGS = '"app.pane.general" = "General";\n'
# Every fixture app gets this, because every real app has one: `COMPLIANT_PANES` above wires
# `AboutSettingsPane(content: AboutConfig.content)` and R15 refuses to report a pass on an About
# pane it never found. Written before `extra`, so a test can still replace it wholesale.
# The Website row is `/fixture-2/` and the Support row is `teddychan/fixture-2` — the
# `dragonapp.com/{app-name}-{major}` convention R15 checks one against the other.
COMPLIANT_ABOUT = """import Foundation
import DragonKit

enum AboutConfig {
    static var content: AboutContent {
        AboutContent(
            appName: "Fixture App",
            versionString: DragonAbout.versionString(),
            copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),
            websiteURL: URL(string: "https://www.dragonapp.com/fixture-2/")!,
            supportURL: URL(string: "https://github.com/teddychan/fixture-2/issues")!,
            licensesURL: URL(string: "https://www.dragonapp.com/fixture-2/licenses/")!,
            license: "MIT"
        )
    }
}
"""
# The seven locales DragonKit ships, which is what clipmenu-2, spectacle-2 and dragon-sample-app
# each ship too — so for them the picker's default is the correct list (R13).
ALL_LOCALES = ("en", "es", "fr", "ja", "ko", "zh-Hans", "zh-Hant")
# Same rule as STALE_PBXPROJ below: a fixture pin that must read as *current* has to stay above
# dragon-kit's newest real tag, or every compliant-app test starts failing the day the kit
# catches up.
COMPLIANT_PACKAGE = ('// swift-tools-version: 6.1\n'
                     '.package(url: "https://github.com/teddychan/dragon-kit", from: "999.9.9"),\n')
COMPLIANT_BUILD = (
    'BUILD="$(git rev-list --count HEAD)"\n'
    'PlistBuddy -c "Set :CFBundleVersion $BUILD" Info.plist\n'
    'COMMIT_DATE="$(git log -1 --format=%cI)"\n'
    'PlistBuddy -c "Set :DragonCommitDate $COMMIT_DATE" Info.plist\n'
)


def language_pane(argument: str = "") -> str:
    """A General-pane section that constructs the kit's `LanguagePicker`, as all five apps do."""
    return """import SwiftUI
import DragonKit

struct LanguageSection: View {
    var body: some View {
        DragonSection("Language") {
            LanguagePicker(%s)
        }
    }
}
""" % argument


def make_app(tmp: str, *, menu: str = COMPLIANT_MENU, panes: str = COMPLIANT_PANES,
             strings: str = COMPLIANT_STRINGS, package: str = COMPLIANT_PACKAGE,
             build: str = COMPLIANT_BUILD, locales: tuple[str, ...] = ("en",),
             extra: dict[str, str] | None = None, config_over: dict | None = None,
             write_config: bool = True) -> str:
    root = tempfile.mkdtemp(dir=tmp)
    os.makedirs(os.path.join(root, "Sources"), exist_ok=True)
    os.makedirs(os.path.join(root, "scripts"), exist_ok=True)
    open(os.path.join(root, "Sources", "Menu.swift"), "w").write(menu)
    open(os.path.join(root, "Sources", "Panes.swift"), "w").write(panes)
    # `locales` is the app's own localization set, which R13 derives from these very directories.
    # An empty tuple is ice-2's shape: no `.lproj` at all.
    for locale in locales:
        os.makedirs(os.path.join(root, "Sources", f"{locale}.lproj"), exist_ok=True)
        open(os.path.join(root, "Sources", f"{locale}.lproj",
                          "Localizable.strings"), "w").write(strings)
    open(os.path.join(root, "Package.swift"), "w").write(package)
    open(os.path.join(root, "scripts", "build.sh"), "w").write(build)
    open(os.path.join(root, "Sources", "AboutConfig.swift"), "w").write(COMPLIANT_ABOUT)
    for name, body in (extra or {}).items():
        path = os.path.join(root, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w").write(body)
    config = {
        "app": "Fixture App",
        "sources": ["Sources"],
        "strings": ["Sources/**/*.lproj/Localizable.strings"],
        "pin": {"file": "Package.swift",
                "pattern": r'dragon-kit", from: "([0-9.]+)"'},
        "paneOrder": {"file": "Sources/Panes.swift"},
        "traits": ["sparkle"],
    }
    config.update(config_over or {})
    if write_config:
        with open(os.path.join(root, ".dragon-conformance.json"), "w") as handle:
            json.dump(config, handle)
    return root


def run(app: str) -> tuple[int, str]:
    proc = subprocess.run([sys.executable, CHECKER, "--app", app, "--kit", KIT],
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


FAILURES: list[str] = []


def expect_pass(name: str, app: str) -> None:
    code, out = run(app)
    if code != 0:
        FAILURES.append(f"{name}: expected PASS, got exit {code}\n{out}")
        print(f"  FAIL  {name}")
    else:
        print(f"  ok    {name}")


def expect_violation(name: str, app: str, rule: str) -> None:
    code, out = run(app)
    if code == 0:
        FAILURES.append(f"{name}: expected {rule} violation, but the checker PASSED.\n{out}")
        print(f"  FAIL  {name} (rule did not bite)")
    elif rule not in out:
        FAILURES.append(f"{name}: failed but not with {rule}:\n{out}")
        print(f"  FAIL  {name} (wrong rule)")
    else:
        print(f"  ok    {name}")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        print("compliant baseline")
        expect_pass("a fully compliant app passes", make_app(tmp))

        print("R0 — config required")
        expect_violation("missing config is a violation", make_app(tmp, write_config=False), "R0")

        print("R1 — menu must come from DragonAppMenu")
        expect_violation("hand-rolled About item", make_app(tmp, menu=COMPLIANT_MENU + """
extension AppMenuController {
    func legacy() -> NSMenuItem {
        NSMenuItem(title: "About Test App", action: nil, keyEquivalent: "")
    }
}
"""), "R1")
        expect_violation("hand-rolled Check for Updates item", make_app(tmp, menu="""import AppKit
final class M {
    func f() -> NSMenuItem { NSMenuItem(title: "Check for updates…", action: nil,
                                        keyEquivalent: "") }
}
"""), "R1")
        expect_violation("app never references DragonAppMenu", make_app(tmp, menu="""import AppKit
final class M { func f() -> NSMenu { NSMenu() } }
"""), "R1")

        print("R2 — no Uninstall in the menu")
        expect_violation("Uninstall menu item", make_app(tmp, menu=COMPLIANT_MENU + """
extension AppMenuController {
    func bad() -> NSMenuItem {
        NSMenuItem(title: "Uninstall Test App…", action: nil, keyEquivalent: "")
    }
}
"""), "R2")

        print("R3 — no shadowing kit type names")
        expect_violation("app declares its own UpdatesSettingsPane", make_app(
            tmp, extra={"Sources/Shadow.swift": "import SwiftUI\nstruct UpdatesSettingsPane {}\n"}
        ), "R3")
        expect_violation("app declares its own UninstallView", make_app(
            tmp, extra={"Sources/Shadow.swift": "import SwiftUI\nstruct UninstallView {}\n"}
        ), "R3")

        # Regression: R3 compared *nested* declarations against nested kit types, so ice-2's
        # SettingsBackup.BackupError was reported as shadowing DragonBackup.BackupError. Different
        # namespaces — it cannot shadow. Only top-level declarations can.
        expect_pass("nested type sharing a nested kit type's name is not shadowing", make_app(
            tmp, extra={"Sources/Backup.swift": """import Foundation
enum SettingsBackup {
    enum BackupError: Error { case unreadable }
    struct Config { var path: String }
}
"""}))
        expect_violation("top-level shadow is still caught", make_app(
            tmp, extra={"Sources/Shadow.swift": "import Foundation\nenum DragonBackup {}\n"}), "R3")

        print("R4 — no re-implemented design primitives")
        expect_violation("app declares IceForm", make_app(
            tmp, extra={"Sources/IceForm.swift": """import SwiftUI
struct IceForm<Content: View>: View {
    var body: some View { Text("x") }
}
"""}), "R4")
        expect_violation("app declares IceSection", make_app(
            tmp, extra={"Sources/IceSection.swift": """import SwiftUI
struct IceSection<Header: View, Content: View, Footer: View>: View {
    var body: some View { Text("x") }
}
"""}), "R4")
        # Regression: the first version of R4 matched any type named *Section, so ice-2's
        # app-domain MenuBarSection model was reported as a settings layout primitive.
        expect_pass("app-domain *Section model is not a layout primitive", make_app(
            tmp, extra={"Sources/MenuBarSection.swift": """import Foundation
struct MenuBarSection: Hashable {
    var name: String
    var isHidden: Bool
}
"""}))
        expect_violation("hand-rolled grouped Form", make_app(
            tmp, extra={"Sources/Custom.swift": """import SwiftUI
struct Custom: View {
    var body: some View {
        Form { Text("x") }
            .formStyle(.grouped)
    }
}
"""}), "R4")

        print("R5 — shared panes must be the kit's")
        expect_violation("no Uninstall pane", make_app(
            tmp, panes=COMPLIANT_PANES.replace("UninstallSettingsPane", "HomeGrownUninstall")
        ), "R5")

        print("R6/R7 — modules")
        expect_violation("direct Sparkle use", make_app(
            tmp, extra={"Sources/Up.swift": "import Sparkle\nfinal class U {}\n"}), "R6")
        expect_violation("SPUStandardUpdaterController", make_app(
            tmp, extra={"Sources/Up.swift":
                        "final class U { let c = SPUStandardUpdaterController() }\n"}), "R6")
        expect_violation("direct SMAppService", make_app(
            tmp, extra={"Sources/Login.swift":
                        "import ServiceManagement\nlet x = SMAppService.mainApp\n"}), "R7")

        print("R8 — app must not own kit string keys")
        expect_violation("DragonKit.* key in app strings", make_app(
            tmp, strings=COMPLIANT_STRINGS + '"DragonKit.menu.settings" = "Settings…";\n'), "R8")
        expect_violation("kit menu title used as a key", make_app(
            tmp, strings=COMPLIANT_STRINGS + '"Check for updates…" = "Rechercher…";\n'), "R8")

        print("R9 — pane order")
        bad_order = COMPLIANT_PANES.replace(
            "AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),", ""
        ).replace(
            "AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),",
            "AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),\n"
            "            AnySettingsPane(PermissionsSettingsPane(permissions: "
            "[.accessibility()])),")
        expect_violation("About before Permissions", make_app(tmp, panes=bad_order), "R9")
        # An app may drive its sidebar from an enum instead of a pane array (ice-2 does), so
        # R9 has to read case names too — measuring type names only reported a false order.
        expect_pass("enum-driven sidebar in canonical order", make_app(
            tmp, extra={"Sources/Nav.swift": """import Foundation
enum SettingsNavigationIdentifier: String {
    case general = "General"
    case hotkeys = "Hotkeys"
    case permissions = "Permissions"
    case backup = "Backup & Restore"
    case whatsNew = "What's New"
    case updates = "Updates"
    case about = "About"
    case uninstall = "Uninstall"
}
"""}, config_over={"paneOrder": {"file": "Sources/Nav.swift"}}))
        expect_violation("enum-driven sidebar out of order", make_app(
            tmp, extra={"Sources/Nav.swift": """import Foundation
enum SettingsNavigationIdentifier: String {
    case general = "General"
    case updates = "Updates"
    case backup = "Backup & Restore"
    case about = "About"
    case uninstall = "Uninstall"
}
"""}, config_over={"paneOrder": {"file": "Sources/Nav.swift"}}), "R9")
        # An app may ship its OWN backup pane under §R11 — clipmenu-2's `SyncBackupPane` adds
        # iCloud sync and versioned folder backup, which DragonBackup deliberately doesn't do.
        # It is still bound by R9's *position*. This was a live hole, not a hypothetical: the
        # slot's spellings were only `BackupSettingsPane`/`backup`, and `\bbackup\b` matches
        # neither `SyncBackupPane` (no word boundary, wrong case) — so R9 never saw the slot,
        # and since it compares only the slots it saw, clipmenu-2 passed with its backup pane
        # free to sit anywhere in the sidebar. The rule reported PASS on the one app it most
        # needed to check, which is the silent-checker failure this whole spec exists to stop.
        def panes_with_backup_named(decl: str, ahead_of_permissions: bool = False) -> str:
            backup = f"AnySettingsPane({decl}),"
            order = [
                "AnySettingsPane(GeneralPane()),",
                "AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),",
                backup,
                "AnySettingsPane(WhatsNewSettingsPane(content: .init(version: \"v1\", date: \"d\","
                " summary: \"s\", sections: []))),",
                "AnySettingsPane(UpdatesSettingsPane(updater: updater)),",
                "AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),",
                "AnySettingsPane(UninstallSettingsPane(config: UninstallConfig(appName: \"T\"))),",
            ]
            if ahead_of_permissions:  # the drift R9 must catch
                order.remove(backup)
                order.insert(1, backup)
            body = "\n".join("            " + line for line in order)
            return ("import SwiftUI\nimport DragonKit\n\n@MainActor\nenum Panes {\n"
                    "    static func all(updater: DragonUpdater) -> [AnySettingsPane] {\n"
                    "        [\n" + body + "\n        ]\n    }\n}\n")

        expect_pass("app's own SyncBackupPane, in the canonical slot", make_app(
            tmp, panes=panes_with_backup_named("SyncBackupPane()")))
        expect_violation("app's own SyncBackupPane, ahead of Permissions", make_app(
            tmp, panes=panes_with_backup_named("SyncBackupPane()", ahead_of_permissions=True)), "R9")

        print("R10 — pin must be current")
        expect_violation("stale pin", make_app(tmp, package=(
            '.package(url: "https://github.com/teddychan/dragon-kit", from: "0.0.1"),\n')), "R10")
        # The retired path-pin exemption, which returned "no violations" for any app declaring it
        # and had no fixture of its own — so the checker carried an always-pass branch that
        # nothing here would have noticed. It existed only for an app living inside the kit, an
        # arrangement MAC-APP-RELEASE-LIFECYCLE.md no longer permits. This fixture is what stops
        # it coming back as the cheapest way for a stale app to pass.
        expect_violation("retired path-pin exemption is itself a violation", make_app(
            tmp, config_over={"pin": {"kind": "path"}}), "R10")
        # Regression, and the reason §R0 now insists the pattern be anchored on dragon-kit.
        # The pattern is one search over the whole file, so an unanchored version regex matches
        # whichever dependency appears first. In ice-2's .pbxproj that was Sparkle at 2.5.2 —
        # numerically ABOVE DragonKit's newest tag — so the rule reported a false PASS while the
        # real DragonKit pin was stale. A false pass is worse than a false failure: it looks
        # like the rule is protecting you.
        # The decoy version must stay ABOVE dragon-kit's newest tag, or this fixture starts
        # depending on the kit's own version instead of testing the regex. It was Sparkle's real
        # 2.5.2, which held only while the kit was below that — tagging v3.0.0 turned the
        # documented false PASS into a genuine stale-pin violation and broke main. Hence a
        # synthetic number no real tag will reach.
        STALE_PBXPROJ = """
			repositoryURL = "https://github.com/sparkle-project/Sparkle";
			requirement = {
				minimumVersion = 999.0.0;
			};
			repositoryURL = "https://github.com/teddychan/dragon-kit";
			requirement = {
				minimumVersion = 1.0.0;
			};
"""
        expect_violation("anchored pbxproj pattern catches the real stale DragonKit pin", make_app(
            tmp, extra={"Proj.pbxproj": STALE_PBXPROJ},
            config_over={"pin": {"file": "Proj.pbxproj",
                                 "pattern": r'dragon-kit";[^}]*minimumVersion = ([0-9.]+)'}}),
            "R10")
        expect_pass("unanchored pattern silently reads Sparkle's version — the trap", make_app(
            tmp, extra={"Proj.pbxproj": STALE_PBXPROJ},
            config_over={"pin": {"file": "Proj.pbxproj",
                                 "pattern": r'minimumVersion = ([0-9.]+)'}}))

        print("R11 — exceptions suppress a rule at a path")
        expect_pass("sanctioned exception is honored", make_app(
            tmp,
            extra={"Sources/SyncBackupPane.swift": """import SwiftUI
struct MyBackupSection: View {
    var body: some View {
        Form { Text("versioned folder backup") }
            .formStyle(.grouped)
    }
}
"""},
            config_over={"exceptions": [{
                "rule": "R4", "path": "Sources/SyncBackupPane.swift",
                "reason": "iCloud sync + versioned folder backup; DragonBackup is suite-only",
                "sanctionedBy": "CONFORMANCE.md R11 table"}]}))

        print("R12 — the build stamps DragonCommitDate")
        # About shows no timestamp at all when the key is absent — deliberately, since a silent
        # fallback to the executable's mtime is the drift this replaced. So "nobody stamps it"
        # has to be a violation rather than a quietly shorter version line.
        expect_violation("build script never stamps the commit date", make_app(
            tmp, build='BUILD="$(git rev-list --count HEAD)"\n'), "R12")
        expect_pass("stamped by a workflow instead of a script", make_app(
            tmp, build="# packaging happens in CI\n",
            extra={".github/workflows/release.yml":
                   'run: PlistBuddy -c "Set :DragonCommitDate $(git log -1 --format=%cI)" x\n'}))
        expect_pass("stamped via a placeholder in Info.plist", make_app(
            tmp, build="# stamped by the release workflow\n",
            extra={"Info.plist": "<key>DragonCommitDate</key><string></string>\n"}))
        expect_violation("declared buildFiles that don't stamp it", make_app(
            tmp, build='PlistBuddy -c "Set :DragonCommitDate $D" Info.plist\n',
            config_over={"buildFiles": ["Package.swift"]}), "R12")

        print("R13 — the language picker offers exactly what the app ships")
        # The false-positive trap this rule has to survive. clipmenu-2, spectacle-2 and
        # dragon-sample-app all call LanguagePicker() bare AND ship all seven .lproj, so the
        # default is the correct list for them — a rule that merely demanded an explicit argument
        # would fail three conforming apps.
        expect_pass("bare picker in an app that ships all seven", make_app(
            tmp, locales=ALL_LOCALES, extra={"Sources/Lang.swift": language_pane()}))
        # The bug itself: yahoo-keykey-2 through v2.11.4 shipped App/en.lproj and
        # App/zh-Hant.lproj while its Settings offered Español, Français, 日本語, 한국어 and
        # 简体中文. Choosing one translated the kit's four panes and left every app string in
        # English, and nothing anywhere failed on it.
        expect_violation("bare picker in an app that ships two", make_app(
            tmp, locales=("en", "zh-Hant"), extra={"Sources/Lang.swift": language_pane()}), "R13")
        expect_pass("explicit list matching the shipped .lproj", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant]")}))
        expect_violation("explicit list wider than the shipped .lproj", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant, .ja]")}), "R13")
        # The other direction: a translation shipped that no user can select. Equality catches it
        # because the picker is the app's statement of its own coverage, and keykey's own
        # testLanguagePickerOffersExactlyTheShippedLocalizations asserts the same both ways.
        expect_violation("shipped .lproj the picker never offers", make_app(
            tmp, locales=("en", "zh-Hant", "ja"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant]")}), "R13")
        # Source case names are not locale codes — `.zhHant` is `zh-Hant.lproj` on disk. An
        # unrecognized token has to be reported rather than dropped, or a typo shrinks the offered
        # set until it agrees with a shorter .lproj list by accident.
        expect_violation("a token that is no DragonLanguage case", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhhant]")}), "R13")
        expect_violation("non-literal languages: argument", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: Self.supported")}), "R13")
        expect_pass("multi-line call site", make_app(
            tmp, locales=("en", "zh-Hant"), extra={"Sources/Lang.swift": """import SwiftUI
import DragonKit

struct LanguageSection: View {
    var body: some View {
        LanguagePicker(
            languages: [.en, .zhHant]
        )
    }
}
"""}))
        # ice-2's shape: English-only, no picker. R13 constrains what a picker claims, not how
        # many languages an app ships — see CONFORMANCE.md "Out of scope, deliberately".
        expect_pass("an app with no picker at all is outside R13", make_app(tmp, locales=()))
        # A picker with nothing to compare against must FAIL rather than skip. A silent skip is
        # the "passes everything" failure the whole spec exists to prevent, and it would make R13
        # unenforceable for any app that localizes with String Catalogs instead of .lproj.
        expect_violation("picker with no .lproj to compare against", make_app(
            tmp, locales=(), extra={"Sources/Lang.swift": language_pane()}), "R13")
        expect_pass("...and that is what §R11 is for", make_app(
            tmp, locales=(), extra={"Sources/Lang.swift": language_pane()},
            config_over={"exceptions": [{
                "rule": "R13",
                "reason": "String Catalogs, so no .lproj exists for the checker to read",
                "sanctionedBy": "CONFORMANCE.md R11 table"}]}))
        # A `.lproj` DragonLanguage has no case for is dropped, not counted: Base.lproj is not a
        # language and the picker physically cannot list `de`, so counting either would leave R13
        # with no satisfiable form — the mistake §R4 records about IceGroupBox.
        expect_pass("a locale the kit has no case for is not counted", make_app(
            tmp, locales=ALL_LOCALES + ("de", "Base"),
            extra={"Sources/Lang.swift": language_pane()}))
        # Regression: yahoo-keykey-2 declares sources ["App", "Packages"], which covers the
        # app-side test enforcing this same rule — and that test contains
        # `code.range(of: "LanguagePicker(languages:")` as a STRING LITERAL, not a comment. So
        # stripping comments alone reports a call site inside the test written to catch the bug.
        expect_pass("a string literal naming the call is not a call site", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant]"),
                   "Sources/PickerTests.swift": '''import XCTest

final class PickerTests: XCTestCase {
    func testPickerIsConfigured() throws {
        let code = try String(contentsOfFile: "Lang.swift", encoding: .utf8)
        guard code.range(of: "LanguagePicker(languages:") != nil else {
            return XCTFail("Lang.swift calls LanguagePicker() bare")
        }
    }
}
'''}))
        expect_pass("a comment naming the call does not trip R13", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant]") + """
// Historical note: this was bare through 2.11.4, which meant
// LanguagePicker(languages: [.en, .es, .fr, .ja, .ko, .zhHans, .zhHant]) in effect.
"""}))
        expect_violation("a comment naming the call does not satisfy R13 either", make_app(
            tmp, locales=("en", "zh-Hant"), extra={"Sources/Lang.swift": language_pane() + """
// TODO: LanguagePicker(languages: [.en, .zhHant]) once the strings land.
"""}), "R13")

        print("R14 — the About copyright is kit-assembled and names one holder")
        # `make_app` already writes this file; these tests replace it with a mutated copy. Shared
        # with R15 rather than duplicated, so the two rules cannot end up testing different About
        # panes after someone edits one of them.
        compliant_about = COMPLIANT_ABOUT
        expect_pass("copyright assembled by the kit helper", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about}))
        expect_violation("copyright hand-typed as a literal", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                'DragonAbout.copyright(years: "2026", holder: "Teddy Chan")',
                '"Copyright © 2026 Teddy Chan"')}), "R14")
        # The exact line 4.0.0 removed, hand-typed back in — the one route no signature can close.
        expect_violation("two copyright holders on one line", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                'DragonAbout.copyright(years: "2026", holder: "Teddy Chan")',
                '"© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan"')}), "R14")
        # Multi-line, exactly as clipmenu-2 and ice-2 wrote it. A compile error under 4.0.0 too,
        # but only while the @available(*, unavailable) overload carrying the message survives.
        expect_violation("the removed original: argument", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                'DragonAbout.copyright(years: "2026", holder: "Teddy Chan")',
                """DragonAbout.copyright(
                original: (years: "2008–2014", holder: "Naotaka Morimoto"),
                years: "2026",
                holder: "Teddy Chan"
            )""")}), "R14")
        # Real cases from the apps, both of which must pass. yahoo-keykey-2's test suite asserts
        # the expected copyright, and ice-2's AboutConfig discusses the old spelling in a comment.
        expect_pass("a test asserting the expected copyright is not the slot", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about,
                        "Sources/ConfigContentTests.swift": """import XCTest

final class ConfigContentTests: XCTestCase {
    func testCopyright() {
        XCTAssertEqual(content.copyright, "© 2026 Teddy Chan")
    }
}
"""}))
        expect_pass("copyright prose in a comment is not a violation", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                "enum AboutConfig {",
                "// Was © 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan before DragonKit 4.0.0.\n"
                "enum AboutConfig {")}))

        print("R15 — About's Website row addresses the app's canonical page")
        about = "Sources/AboutConfig.swift"
        # dragon-sample-app's real shape: the Website row on the studio hub while the Support row
        # names a repository. It is the sanctioned divergence, and it has to be a violation first —
        # an exception for a rule that never fires is the §R11 table's own recorded mistake.
        expect_violation("website on the site root", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                "https://www.dragonapp.com/fixture-2/\")!,\n            supportURL",
                "https://www.dragonapp.com\")!,\n            supportURL")}), "R15")
        expect_pass("...and that is what §R11 is for", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                "https://www.dragonapp.com/fixture-2/\")!,\n            supportURL",
                "https://www.dragonapp.com\")!,\n            supportURL")},
            config_over={"exceptions": [{
                "rule": "R15", "path": about,
                "reason": "no public app page exists; the site hosts only the licences page",
                "sanctionedBy": "CONFORMANCE.md §R11"}]}))
        # The trap clipmenu-2's own AboutConfig comment records: `/clipmenu/` is a <meta refresh>
        # stub whose rel=canonical points at `/clipmenu-2/`. It resolves in a browser, so nothing
        # but this comparison distinguishes it from the canonical page.
        expect_violation("website on the redirect stub, not the canonical page", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace("/fixture-2/\")!,\n            supportURL",
                                                       "/fixture/\")!,\n            supportURL")}),
            "R15")
        # clipmenu-2 and ice-2 both name their URLs before passing them, so R15 reads nothing at
        # all for two of the five apps unless it follows one hop. Both directions are tested: the
        # indirection must resolve *and* must still bite, or "resolved" would just mean "skipped".
        # The trailing comments matter too — `strip_comment` would cut these lines at the `//` in
        # `https://` and leave no URL to read.
        indirect = """import Foundation
import DragonKit

enum AboutConfig {
    private static let websiteURL = URL(string: "https://www.dragonapp.com/fixture-2/")!  // canon
    private static let issuesURL = URL(string: "https://github.com/teddychan/fixture-2/issues")!

    static var content: AboutContent {
        AboutContent(
            appName: "Fixture App",
            versionString: DragonAbout.versionString(),
            copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),
            websiteURL: websiteURL,
            supportURL: issuesURL,
            licensesURL: URL(string: "https://www.dragonapp.com/fixture-2/licenses/")!,
            license: "MIT"
        )
    }
}
"""
        expect_pass("URLs named by a constant, as clipmenu-2 and ice-2 write them", make_app(
            tmp, extra={about: indirect}))
        expect_violation("a constant holding the wrong page still bites", make_app(
            tmp, extra={about: indirect.replace('dragonapp.com/fixture-2/")!  // canon',
                                                'dragonapp.com")!  // canon')}), "R15")
        # An argument the checker cannot read must fail, not pass. R15 compares written literals,
        # so anything it can't resolve is a rule that would otherwise go quiet.
        expect_violation("a websiteURL R15 cannot resolve", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                'URL(string: "https://www.dragonapp.com/fixture-2/")!',
                "Self.site")}), "R15")
        expect_violation("a support row that names no repository", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                "https://github.com/teddychan/fixture-2/issues",
                "https://www.dragonapp.com/fixture-2/support/")}), "R15")
        # The silent-checker arm. An app that restructures its About wiring out of the checker's
        # sight must fail rather than drop out of the rule — §R0, §R10 and §R13 all take this line.
        expect_violation("no AboutContent construction anywhere", make_app(
            tmp, extra={about: "import Foundation\n\nenum AboutConfig { }\n"}), "R15")
        expect_pass("an app-wide exception silences that arm too", make_app(
            tmp, extra={about: "import Foundation\n\nenum AboutConfig { }\n"},
            config_over={"exceptions": [{
                "rule": "R15",
                "reason": "About is assembled by a helper the checker cannot read",
                "sanctionedBy": "CONFORMANCE.md §R11"}]}))
        # The keykey trap, which R13 hit for real: yahoo-keykey-2's `sources` cover its own test
        # suite, and a test that asserts this rule names the call in a STRING LITERAL. Read as a
        # construction, its "arguments" are unparseable and the app fails for having a test.
        expect_pass("a string literal naming the construction is not one", make_app(
            tmp, extra={"Sources/AboutTests.swift": '''import XCTest

final class AboutTests: XCTestCase {
    func testAboutIsConfigured() throws {
        let code = try String(contentsOfFile: "AboutConfig.swift", encoding: .utf8)
        XCTAssertNotNil(code.range(of: "AboutContent("))
        XCTAssertNotNil(code.range(of: "https://www.dragonapp.com/fixture-2/"))
    }
}
'''}))
        # Found in review, not in an app — but the shape is everywhere: 27 files across the five
        # apps use a Swift multi-line string, none of them yet the one that builds About. Scanned
        # as three single quotes the delimiter reads open-close-open, so an odd number of `"` in
        # the block leaves the scanner stuck inside a literal for the rest of the FILE, blanks the
        # real construction below it, and reports a conforming app for having no About pane at all.
        multiline = COMPLIANT_ABOUT.replace("enum AboutConfig {", '''enum AboutConfig {
    static let blurb = """
    A sample app, 12" wide, for DragonKit.
    """
''')
        expect_pass("a multi-line string above the construction", make_app(
            tmp, extra={about: multiline}))
        expect_violation("...and the construction below it is still read", make_app(
            tmp, extra={about: multiline.replace("/fixture-2/\")!,\n            supportURL",
                                                 "\")!,\n            supportURL")}), "R15")
        # ...and the other direction, the one R13 also pins: prose cannot satisfy the rule either.
        expect_violation("a commented-out construction does not count as one", make_app(
            tmp, extra={about: """import Foundation
import DragonKit

// AboutContent(websiteURL: URL(string: "https://www.dragonapp.com/fixture-2/")!,
//              supportURL: URL(string: "https://github.com/teddychan/fixture-2/issues")!)
enum AboutConfig { }
"""}), "R15")

        print("no-false-positive checks")
        expect_pass("app builds its own non-lifecycle menu items", make_app(
            tmp, menu=COMPLIANT_MENU + """
extension AppMenuController {
    func history() -> NSMenuItem {
        NSMenuItem(title: "Clear history", action: nil, keyEquivalent: "")
    }
}
"""))
        expect_pass("commented-out lifecycle item is not a violation", make_app(
            tmp, menu=COMPLIANT_MENU + """
// Historical note: this used to be NSMenuItem(title: "Quit App") before DragonAppMenu.
"""))
        expect_pass("app-domain type named ...Section is fine outside settings", make_app(
            tmp, extra={"Sources/Engine.swift":
                        "struct MenuBarItemInfo {}\nstruct Snapshot {}\n"}))

    print()
    if FAILURES:
        print(f"{len(FAILURES)} test(s) failed:\n")
        for failure in FAILURES:
            print(failure)
            print("-" * 60)
        return 1
    print("All conformance-checker tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
