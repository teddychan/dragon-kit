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
COMPLIANT_PACKAGE = ('// swift-tools-version: 6.1\n'
                     '.package(url: "https://github.com/teddychan/dragon-kit", from: "9.9.9"),\n')


def make_app(tmp: str, *, menu: str = COMPLIANT_MENU, panes: str = COMPLIANT_PANES,
             strings: str = COMPLIANT_STRINGS, package: str = COMPLIANT_PACKAGE,
             extra: dict[str, str] | None = None, config_over: dict | None = None,
             write_config: bool = True) -> str:
    root = tempfile.mkdtemp(dir=tmp)
    os.makedirs(os.path.join(root, "Sources"), exist_ok=True)
    os.makedirs(os.path.join(root, "Sources", "en.lproj"), exist_ok=True)
    open(os.path.join(root, "Sources", "Menu.swift"), "w").write(menu)
    open(os.path.join(root, "Sources", "Panes.swift"), "w").write(panes)
    open(os.path.join(root, "Sources", "en.lproj", "Localizable.strings"), "w").write(strings)
    open(os.path.join(root, "Package.swift"), "w").write(package)
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

        print("R10 — pin must be current")
        expect_violation("stale pin", make_app(tmp, package=(
            '.package(url: "https://github.com/teddychan/dragon-kit", from: "0.0.1"),\n')), "R10")

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
