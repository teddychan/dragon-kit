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
import re
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

# `  R15  Sources/AboutConfig.swift:12: message` — `Violation.render`'s shape, and also the shape
# of the two `SystemExit` texts (R0's missing config, R13's missing DragonLanguage), which print
# at column 0. The `exception  R15  …` line does not match: it leads with the word, not the rule.
VIOLATION_LINE = re.compile(r"^\s*(R\d+)\s\s+(\S.*)$")


def violations(out: str) -> list[tuple[str, str]]:
    """Every `(rule, text)` the checker printed, so a test can assert on the branch, not the rule."""
    found = []
    for line in out.splitlines():
        match = VIOLATION_LINE.match(line)
        if match:
            found.append((match.group(1), match.group(2)))
    return found


def expect_pass(name: str, app: str) -> None:
    code, out = run(app)
    if code != 0:
        FAILURES.append(f"{name}: expected PASS, got exit {code}\n{out}")
        print(f"  FAIL  {name}")
    else:
        print(f"  ok    {name}")


def expect_violation(name: str, app: str, rule: str, because: str) -> None:
    """Assert the checker fails, with `rule`, *on the branch whose message contains `because`*.

    `because` is not decoration. This function used to assert `rule in out` and nothing more, so it
    proved a rule fired somewhere — never that the intended code path did. Most rules here have
    several branches, and a broken one usually falls through to another that reports the same rule
    name, so targeted mutations of the checker left the entire suite green. Verified on this one:
    narrowing R1's `Check\\s+for\\s+[Uu]pdates` pattern to `Check\\s+for\\s+Updates` stops the
    "Check for updates…" fixture tripping the hand-rolled-item branch — and that fixture's menu
    also never references `DragonAppMenu`, so R1 still fired from the *other* arm and the old
    assertion reported `ok`. §R15 is the worst case: three fixtures written as negative controls
    for the host comparison all resolved through the "cannot read the argument" arm instead, and
    the host hole shipped underneath them.

    The `other` check is the second half. A fixture that also fails for an unrelated reason is not
    evidence about the rule under test, and it is how a fixture keeps reporting `ok` after the
    branch it was written for stops firing at all.
    """
    code, out = run(app)
    if code == 0:
        FAILURES.append(f"{name}: expected {rule} violation, but the checker PASSED.\n{out}")
        print(f"  FAIL  {name} (rule did not bite)")
        return
    found = violations(out)
    if not any(r == rule and because in text for r, text in found):
        same_rule = [text for r, text in found if r == rule]
        if same_rule:
            FAILURES.append(f"{name}: {rule} fired, but not the branch under test. Expected a "
                            f"message containing {because!r}; got:\n" +
                            "\n".join(f"  - {text}" for text in same_rule))
            print(f"  FAIL  {name} (wrong branch of {rule})")
        else:
            FAILURES.append(f"{name}: failed but not with {rule}:\n{out}")
            print(f"  FAIL  {name} (wrong rule)")
        return
    other = sorted({r for r, _ in found} - {rule})
    if other:
        FAILURES.append(f"{name}: expected {rule} alone, but {', '.join(other)} fired too — the "
                        f"fixture fails for more than the reason under test:\n{out}")
        print(f"  FAIL  {name} (collateral {', '.join(other)})")
        return
    print(f"  ok    {name}")


def check_masking_invariants() -> None:
    """`mask_noncode` must preserve length AND line count, for every caller and every input.

    Asserted directly rather than only through fixtures, because the two properties are what let a
    rule read one file through two views at one index space — and a break in either is silent.
    Line count was the one that broke: `\\` at end of line is Swift's continuation inside a
    multi-line string, and blanking the newline after it kept the length right while moving every
    line number below. §R1 and §R15 number from the original body and never noticed; §R13 numbers
    from the masked copy and misreported by up to 9 lines in ice-2's MenuBarItemManager.swift.
    """
    import importlib.util

    # Importing the checker makes CPython cache its bytecode next to the script. Harmless, but it
    # left a `Scripts/__pycache__/` for a `git add -A` to sweep into a commit, which is what
    # happened.
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("dragon_conformance", CHECKER)
    checker = importlib.util.module_from_spec(spec)
    sys.modules["dragon_conformance"] = checker
    spec.loader.exec_module(checker)

    cases = {
        "line continuation in a multi-line string": '''let s = """
a b \\
c "d"
"""
let after = 1
''',
        "raw string with an odd inner quote": 'let q = #"a straight " here"#\nlet after = 1\n',
        "nested raw delimiters": 'let q = ##"a "# sequence"##\nlet after = 1\n',
        "raw multi-line": 'let q = #"""\n"quoted", 12" wide\n"""#\nlet after = 1\n',
        "backslash inside a raw string": '#"a \\ and a \\#(x)"#\nlet after = 1\n',
        "unterminated block comment": "code()\n/* never closed\nmore\n",
        "unterminated literal": 'let s = "never closed\nlet after = 1\n',
        "comment markers inside a literal": 'let s = "// not a comment /* nor this */"\nx()\n',
        "literal markers inside a comment": '// a " and a #" and a """\nx()\n',
        "escaped quote at end of literal": 'let s = "ends with \\""\nlet after = 1\n',
        "empty": "",
    }
    for name, text in cases.items():
        for blank in (True, False):
            masked = checker.mask_noncode(text, blank_literals=blank)
            label = f"{name} (blank_literals={blank})"
            if len(masked) != len(text):
                FAILURES.append(f"{label}: length {len(text)} -> {len(masked)}")
                print(f"  FAIL  {label} (length)")
            elif masked.count("\n") != text.count("\n"):
                FAILURES.append(f"{label}: newlines {text.count(chr(10))} -> "
                                f"{masked.count(chr(10))}")
                print(f"  FAIL  {label} (line count)")
            else:
                print(f"  ok    {label}")


# The settings-pane canon is one string that changes the UI of five apps at once, and it is quoted
# in seven documents besides the one that owns it. It drifted into two spellings and sat that way
# for months: one copy made the Permissions pane unconditional while §R5 gates it on the
# `no-permissions` trait, and the same was true of Updates and `sparkle`. Nothing could catch that,
# because no rule reads prose. This does.
#
# §R9 owns the line. Every other copy must be byte-identical to it, modulo the two substitutions a
# guide legitimately makes: addressing the reader as "your"/"this app's" instead of "the app's".
# A copy that describes a *particular app's* actual sidebar is not a copy of the canon and is
# skipped — `ADOPT-DRAGONKIT-PROMPT.md` and `DOC-RULE-CONFLICT-CHANGELOG.md` each state KeyKey's
# real order, which is deliberately shorter.
CANON_OWNER = "CONFORMANCE.md"
CANON_HEAD = "General → "
CANON_READER_VARIANTS = [("(the app's own panes)", "(this app's own panes)"),
                         ("(the app's own panes)", "(your panes)")]
# Every document that quotes it today. Lowering this number is how the check stops checking.
CANON_COPIES = 6


def canon_line_from_owner() -> str:
    for line in open(os.path.join(KIT, CANON_OWNER), encoding="utf-8"):
        if line.startswith(CANON_HEAD):
            return line.strip()
    raise SystemExit(f"canon check: no line starting {CANON_HEAD!r} in {CANON_OWNER}")


def check_canon_pane_order_is_quoted_not_paraphrased() -> None:
    print("settings-pane canon is one string")
    canon = canon_line_from_owner()
    accepted = {canon} | {canon.replace(a, b) for a, b in CANON_READER_VARIANTS}
    listing = subprocess.run(["git", "ls-files", "*.md"], cwd=KIT, check=True,
                             capture_output=True, text=True).stdout.split()
    checked = 0
    for rel in listing:
        raw = open(os.path.join(KIT, rel), encoding="utf-8").read()
        # Normalize before matching. A copy may wrap across lines, sit inside a block quote, be
        # indented in a fenced prompt, or be wrapped in backticks mid-sentence — STARTING-A-NEW-APP
        # does three of those at once, and a line-prefix match missed it entirely.
        flat = re.sub(r"[\s>`]+", " ", raw)
        for found in re.findall(rf"{re.escape(CANON_HEAD)}.*?→ Uninstall", flat):
            if "(" not in found:
                continue  # a named app's real sidebar, not a copy of the canon
            checked += 1
            if found not in accepted:
                FAILURES.append(
                    f"{rel} paraphrases the settings-pane canon.\n"
                    f"    owner ({CANON_OWNER} §R9): {canon}\n"
                    f"    this copy:                 {found}\n"
                    "    Quote §R9's line exactly; only 'the app's own panes' may become "
                    "'this app's own panes' or 'your panes'.")
    if checked < CANON_COPIES:
        FAILURES.append(f"canon check found {checked} copies of the pane order, expected at least "
                        f"{CANON_COPIES}. Either a document dropped it, or its wrapping changed "
                        "and this check has stopped looking at something.")
    print(f"  ok    {checked} copies match {CANON_OWNER} §R9 byte-for-byte")


def main() -> int:
    print("mask_noncode invariants")
    check_masking_invariants()

    with tempfile.TemporaryDirectory() as tmp:
        print("compliant baseline")
        expect_pass("a fully compliant app passes", make_app(tmp))

        print("R0 — config required")
        expect_violation("missing config is a violation", make_app(tmp, write_config=False), "R0",
            because="is missing from the app repo root")

        print("R1 — menu must come from DragonAppMenu")
        expect_violation("hand-rolled About item", make_app(tmp, menu=COMPLIANT_MENU + """
extension AppMenuController {
    func legacy() -> NSMenuItem {
        NSMenuItem(title: "About Test App", action: nil, keyEquivalent: "")
    }
}
"""), "R1",
            because="hand-rolled app-lifecycle menu item")
        expect_violation("hand-rolled Check for Updates item", make_app(tmp, menu="""import AppKit
final class M {
    func f() -> NSMenuItem { NSMenuItem(title: "Check for updates…", action: nil,
                                        keyEquivalent: "") }
}
"""), "R1",
            because="hand-rolled app-lifecycle menu item")
        expect_violation("app never references DragonAppMenu", make_app(tmp, menu="""import AppKit
final class M { func f() -> NSMenu { NSMenu() } }
"""), "R1",
            because="never references DragonAppMenu")
        # `"DragonAppMenu" in line` counted the name wherever it appeared, so a string literal —
        # or a comment — satisfied R1 for an app that never calls the kit's menu at all.
        expect_violation("the kit's name in a literal is not a call", make_app(
            tmp, menu="""import AppKit
final class M {
    let marker = "DragonAppMenu"
    func f() -> NSMenu { NSMenu() }
}
"""), "R1",
            because="never references DragonAppMenu")

        print("R2 — no Uninstall in the menu")
        expect_violation("Uninstall menu item", make_app(tmp, menu=COMPLIANT_MENU + """
extension AppMenuController {
    func bad() -> NSMenuItem {
        NSMenuItem(title: "Uninstall Test App…", action: nil, keyEquivalent: "")
    }
}
"""), "R2",
            because="menu item for Uninstall")
        # The same item wrapped, which is how every one of these reads once it has four arguments.
        # Both rules were line-based substring tests, so the line holding `NSMenuItem(` carried no
        # title to match and the item was invisible to R1 and R2 alike.
        expect_violation("a multi-line Uninstall item", make_app(tmp, menu=COMPLIANT_MENU + """
extension AppMenuController {
    func bad() -> NSMenuItem {
        NSMenuItem(
            title: "Uninstall Test App…",
            action: nil,
            keyEquivalent: ""
        )
    }
}
"""), "R2",
            because="menu item for Uninstall")
        expect_violation("a multi-line About item", make_app(tmp, menu=COMPLIANT_MENU + """
extension AppMenuController {
    func legacy() -> NSMenuItem {
        NSMenuItem(
            title: "About Test App",
            action: nil,
            keyEquivalent: ""
        )
    }
}
"""), "R1",
            because="hand-rolled app-lifecycle menu item")
        # Reading the arguments across the whole construction was right; slicing them out of the
        # RAW text was not. It let comments *inside* the argument list match, which the line-based
        # predecessor would never have done — a regression, and one §R1's own prose forbids. The
        # existing "commented-out lifecycle item" fixture does not cover it: there the whole
        # `NSMenuItem(` sits inside the comment, so masking hides the call itself.
        expect_pass("a comment inside the argument list is not a title", make_app(
            tmp, menu=COMPLIANT_MENU + """
extension AppMenuController {
    func appOwn(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title,   // Quit and About %@ are built by DragonAppMenu, not here
                   action: nil, keyEquivalent: "")
    }
}
"""))
        # R2 reads its own exception key. It was gated on R1's, so an app needing an Uninstall
        # exception had to declare R1 — switching off every lifecycle-title check on that path —
        # while §R11 told it "R2 is not a rule this checker can suppress", which was false in the
        # way that mattered: R1 suppressed it.
        uninstall_menu = COMPLIANT_MENU + """
extension AppMenuController {
    func bad() -> NSMenuItem {
        NSMenuItem(title: "Uninstall Test App…", action: nil, keyEquivalent: "")
    }
}
"""
        expect_pass("an R2 exception suppresses R2", make_app(
            tmp, menu=uninstall_menu, config_over={"exceptions": [{
                "rule": "R2", "path": "Sources/Menu.swift",
                "reason": "the host assembles this menu itself",
                "sanctionedBy": "CONFORMANCE.md §R11"}]}))
        # ...and it suppresses R2 *only* — an R2 exception must not silence the lifecycle arm.
        expect_violation("an R2 exception does not silence R1", make_app(
            tmp, menu=uninstall_menu + """
extension AppMenuController {
    func legacy() -> NSMenuItem {
        NSMenuItem(title: "About Test App", action: nil, keyEquivalent: "")
    }
}
""", config_over={"exceptions": [{
                "rule": "R2", "path": "Sources/Menu.swift",
                "reason": "the host assembles this menu itself",
                "sanctionedBy": "CONFORMANCE.md §R11"}]}), "R1",
            because="hand-rolled app-lifecycle menu item")

        print("R3 — no shadowing kit type names")
        expect_violation("app declares its own UpdatesSettingsPane", make_app(
            tmp, extra={"Sources/Shadow.swift": "import SwiftUI\nstruct UpdatesSettingsPane {}\n"}
        ), "R3",
            because="shadowing the public DragonKit")
        expect_violation("app declares its own UninstallView", make_app(
            tmp, extra={"Sources/Shadow.swift": "import SwiftUI\nstruct UninstallView {}\n"}
        ), "R3",
            because="shadowing the public DragonKit")

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
            tmp, extra={"Sources/Shadow.swift": "import Foundation\nenum DragonBackup {}\n"}), "R3",
            because="shadowing the public DragonKit")

        print("R4 — no re-implemented design primitives")
        expect_violation("app declares IceForm", make_app(
            tmp, extra={"Sources/IceForm.swift": """import SwiftUI
struct IceForm<Content: View>: View {
    var body: some View { Text("x") }
}
"""}), "R4",
            because="a generic view wrapper")
        expect_violation("app declares IceSection", make_app(
            tmp, extra={"Sources/IceSection.swift": """import SwiftUI
struct IceSection<Header: View, Content: View, Footer: View>: View {
    var body: some View { Text("x") }
}
"""}), "R4",
            because="a generic view wrapper")
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
"""}), "R4",
            because="hand-rolled grouped Form")

        print("R5 — shared panes must be the kit's")
        expect_violation("no Uninstall pane", make_app(
            tmp, panes=COMPLIANT_PANES.replace("UninstallSettingsPane", "HomeGrownUninstall")
        ), "R5",
            because="no reference to UninstallSettingsPane")
        # R5 searched raw text, so the line a migration left behind counted as wiring the pane —
        # the one rule where prose *about* the kit was accepted as use of the kit.
        expect_violation("a commented-out pane reference is not a pane", make_app(
            tmp, panes=COMPLIANT_PANES.replace(
                "UninstallSettingsPane", "HomeGrownUninstall") + """
// Migration note: this used to be AnySettingsPane(UninstallSettingsPane(config: config)).
/* AnySettingsPane(UninstallSettingsPane(config: UninstallConfig(appName: "T"))) */
"""), "R5",
            because="no reference to UninstallSettingsPane")

        print("R6/R7 — modules")
        expect_violation("direct Sparkle use", make_app(
            tmp, extra={"Sources/Up.swift": "import Sparkle\nfinal class U {}\n"}), "R6",
            because="direct Sparkle use")
        expect_violation("SPUStandardUpdaterController", make_app(
            tmp, extra={"Sources/Up.swift":
                        "final class U { let c = SPUStandardUpdaterController() }\n"}), "R6",
            because="direct Sparkle use")
        expect_violation("direct SMAppService", make_app(
            tmp, extra={"Sources/Login.swift":
                        "import ServiceManagement\nlet x = SMAppService.mainApp\n"}), "R7",
            because="direct launch-at-login wiring")
        # Neither rule can be inverted into a positive one — an app with `mac-app-store` links no
        # updater, and an app may have no launch-at-login feature at all — so both are deny-lists,
        # and a deny-list only knows the routes written into it. §R7 knew exactly two, and
        # `import LoginServiceKit` (the login-item library ClipMenu's upstream used) walked past.
        expect_violation("import LoginServiceKit", make_app(
            tmp, extra={"Sources/Login.swift":
                        "import LoginServiceKit\nfinal class L {}\n"}), "R7",
            because="direct launch-at-login wiring")
        expect_violation("the deprecated LSSharedFileList route", make_app(
            tmp, extra={"Sources/Login.swift":
                        "let list = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems"
                        ", nil)\n"}), "R7",
            because="direct launch-at-login wiring")
        expect_violation("Sparkle 1.x's SUUpdater", make_app(
            tmp, extra={"Sources/Up.swift": "final class U { let u = SUUpdater.shared() }\n"}),
            "R6",
            because="direct Sparkle use")
        # ...anchored on `import` or a member access, never the bare name: ice-2 credits
        # LaunchAtLogin in an About comment and in its generated acknowledgements, and matching the
        # word alone would fail it for naming a library it does not use.
        expect_pass("crediting a login library is not using one", make_app(
            tmp, extra={"Sources/Credits.swift": """import DragonKit

let attributions = [
    Attribution(name: "LaunchAtLogin", license: "MIT"),
    Attribution(name: "LoginServiceKit", license: "MIT"),
]
"""}))

        print("R8 — app must not own kit string keys")
        expect_violation("DragonKit.* key in app strings", make_app(
            tmp, strings=COMPLIANT_STRINGS + '"DragonKit.menu.settings" = "Settings…";\n'), "R8",
            because="defines kit-owned key")
        expect_violation("kit menu title used as a key", make_app(
            tmp, strings=COMPLIANT_STRINGS + '"Check for updates…" = "Rechercher…";\n'), "R8",
            because="a kit-owned menu title")
        # Omitting the glob disabled the rule outright: the loop had nothing to iterate and the app
        # passed by giving the checker no work to do — the same shape as deleting the config, which
        # §R0 makes a violation for exactly this reason.
        expect_violation("no 'strings' at all disables the rule", make_app(
            tmp, config_over={"strings": []}), "R8",
            because="declares no 'strings'")
        expect_pass("...and that is what §R11 is for", make_app(
            tmp, locales=(), config_over={"strings": [], "exceptions": [{
                "rule": "R8",
                "reason": "String Catalogs, so there is no .strings file to read keys from",
                "sanctionedBy": "CONFORMANCE.md §R11"}]}))

        print("R9 — pane order")
        bad_order = COMPLIANT_PANES.replace(
            "AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),", ""
        ).replace(
            "AnySettingsPane(PermissionsSettingsPane(permissions: [.accessibility()])),",
            "AnySettingsPane(AboutSettingsPane(content: AboutConfig.content)),\n"
            "            AnySettingsPane(PermissionsSettingsPane(permissions: "
            "[.accessibility()])),")
        expect_violation("About before Permissions", make_app(tmp, panes=bad_order), "R9",
            because="settings pane order is")
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
"""}, config_over={"paneOrder": {"file": "Sources/Nav.swift"}}), "R9",
            because="settings pane order is")
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
            tmp, panes=panes_with_backup_named("SyncBackupPane()", ahead_of_permissions=True)), "R9",
            because="settings pane order is")
        # ice-2's spelling, which README.md and TechDebt.md both stated was recognized and which
        # was not in the slot at all. ice-2's own Backup slot is seen anyway — its `paneOrder` file
        # is an enum with `case backup` — so nothing failed and nothing would have, until a
        # refactor to naming pane types there took the slot silently unchecked, exactly as
        # clipmenu-2's was.
        expect_pass("app's own IceBackupSettingsPane, in the canonical slot", make_app(
            tmp, panes=panes_with_backup_named("IceBackupSettingsPane()")))
        expect_violation("app's own IceBackupSettingsPane, ahead of Permissions", make_app(
            tmp, panes=panes_with_backup_named("IceBackupSettingsPane()",
                                               ahead_of_permissions=True)), "R9",
            because="settings pane order is")

        # Same hole on the other side of the config. The sidebar order is canon that changes the
        # UI of every Dragon app at once, and an app that named no file simply wasn't checked.
        expect_violation("no 'paneOrder' at all disables the rule", make_app(
            tmp, config_over={"paneOrder": {}}), "R9",
            because="declares no 'paneOrder'")

        print("R10 — pin must be current")
        expect_violation("stale pin", make_app(tmp, package=(
            '.package(url: "https://github.com/teddychan/dragon-kit", from: "0.0.1"),\n')), "R10",
            because="a stale pin silently misses shared fixes")
        # The retired path-pin exemption, which returned "no violations" for any app declaring it
        # and had no fixture of its own — so the checker carried an always-pass branch that
        # nothing here would have noticed. It existed only for an app living inside the kit, an
        # arrangement MAC-APP-RELEASE-LIFECYCLE.md no longer permits. This fixture is what stops
        # it coming back as the cheapest way for a stale app to pass.
        expect_violation("retired path-pin exemption is itself a violation", make_app(
            tmp, config_over={"pin": {"kind": "path"}}), "R10",
            because="the exemption is retired")
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
                                 "pattern": r'dragon-kit";[^}]*minimumVersion = ([0-9.]+)'}}), "R10",
            because="a stale pin silently misses shared fixes")
        # This fixture used to be an `expect_pass` — the suite asserted the trap's false PASS as
        # *expected behaviour*, for the most-cited incident in the spec, while §R0 had said the
        # pattern "MUST anchor on dragon-kit" the whole time. A rule stated in prose and
        # contradicted by its own test is the failure this document exists to prevent, so R10
        # now reads the pattern itself.
        expect_violation("an unanchored pattern is rejected before it can read Sparkle", make_app(
            tmp, extra={"Proj.pbxproj": STALE_PBXPROJ},
            config_over={"pin": {"file": "Proj.pbxproj",
                                 "pattern": r'minimumVersion = ([0-9.]+)'}}),
            "R10", because="does not anchor on dragon-kit")
        # ...and the anchor is a *spelling* test, not a literal one: yahoo-keykey-2 pins with
        # `DRAGONKIT_TAG="v2.13.0"` in a shell script, which anchors just as surely.
        expect_pass("keykey's DRAGONKIT_TAG spelling anchors too", make_app(
            tmp, extra={"tools/build-app.sh": 'DRAGONKIT_TAG="v999.9.9"\n'},
            config_over={"pin": {"file": "tools/build-app.sh",
                                 "pattern": r'DRAGONKIT_TAG="v([0-9.]+)"'}}))

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
        # §R11 has required `reason` and `sanctionedBy` since it was written and nothing checked
        # either: an entry with neither suppressed its rule just as effectively, and the run
        # printed `NO REASON GIVEN` beside it without failing. It now guards a live exception.
        expect_violation("an exception with no reason", make_app(
            tmp, config_over={"exceptions": [{
                "rule": "R4", "path": "Sources/SyncBackupPane.swift",
                "sanctionedBy": "CONFORMANCE.md R11 table"}]}), "R11",
            because="declares no 'reason'")
        expect_violation("an exception with no owner", make_app(
            tmp, config_over={"exceptions": [{
                "rule": "R4", "path": "Sources/SyncBackupPane.swift",
                "reason": "iCloud sync + versioned folder backup"}]}), "R11",
            because="declares no 'sanctionedBy'")
        # The §R11 table's own recorded mistake, machine-checked: five sanctions sat there for
        # months naming rules that never fired on the apps they were written for. A row naming a
        # rule the checker cannot suppress reads as a live sanction and sanctions nothing.
        # R10 is genuinely un-suppressible: `rule_r10_pin` never consults `excuses()`, because a
        # stale pin is the one thing no app may opt out of. (R2 used to stand here, and was the
        # wrong example — see "R2 reads its own exception key" below.)
        expect_violation("an exception for a rule that cannot fire", make_app(
            tmp, config_over={"exceptions": [{
                "rule": "R10", "reason": "we will bump next sprint",
                "sanctionedBy": "CONFORMANCE.md §R11"}]}), "R11",
            because="not a rule this checker can suppress")
        # §R5, §R8, §R9 and §R12 are whole-app checks — each consults `excuses(rule, "")` and
        # nothing else — so a path-scoped entry printed as a live, narrowly-scoped sanction on
        # every run and suppressed nothing. Same defect as naming a rule that never fires, left
        # open one field along: this fixture PASSED §R11 and still failed §R8.
        expect_violation("a path on a rule that is only ever checked app-wide", make_app(
            tmp, config_over={"exceptions": [{
                "rule": "R8", "path": "Sources", "reason": "String Catalogs",
                "sanctionedBy": "CONFORMANCE.md §R11"}]}), "R11",
            because="only ever checked for the app as a whole")
        # ...and §R15 must keep accepting one, because dragon-sample-app's live exception is
        # path-scoped and that rule is consulted both ways.
        expect_pass("§R15 still takes a path", make_app(
            tmp, extra={"Sources/AboutConfig.swift": COMPLIANT_ABOUT.replace(
                "https://www.dragonapp.com/fixture-2/\")!,\n            supportURL",
                "https://www.dragonapp.com\")!,\n            supportURL")},
            config_over={"exceptions": [{
                "rule": "R15", "path": "Sources/AboutConfig.swift",
                "reason": "no public app page exists", "sanctionedBy": "CONFORMANCE.md §R11"}]}))

        print("R12 — the build stamps DragonCommitDate")
        # About shows no timestamp at all when the key is absent — deliberately, since a silent
        # fallback to the executable's mtime is the drift this replaced. So "nobody stamps it"
        # has to be a violation rather than a quietly shorter version line.
        expect_violation("build script never stamps the commit date", make_app(
            tmp, build='BUILD="$(git rev-list --count HEAD)"\n'), "R12",
            because="no build step stamps")
        expect_pass("stamped by a workflow instead of a script", make_app(
            tmp, build="# packaging happens in CI\n",
            extra={".github/workflows/release.yml":
                   'run: PlistBuddy -c "Set :DragonCommitDate $(git log -1 --format=%cI)" x\n'}))
        expect_pass("stamped via a placeholder in Info.plist", make_app(
            tmp, build="# stamped by the release workflow\n",
            extra={"Info.plist": "<key>DragonCommitDate</key><string></string>\n"}))
        # The rule accepted the key appearing *anywhere* in the build surface, so a note in a
        # script's header comment satisfied it while nothing wrote the key — and two of the five
        # apps have exactly such a comment, next to a real stamp that was doing the work.
        # A scripting-language stamper assigns to the key rather than shelling out to PlistBuddy,
        # and genuinely writes it. The list is closed — CONFORMANCE.md §R12 says so now — so a
        # route it does not name has to be added here rather than left to §R11.
        expect_pass("a plistlib stamper", make_app(
            tmp, build="# packaging is python\n",
            extra={"scripts/stamp.py": 'import plistlib\npl["DragonCommitDate"] = date\n'},
            config_over={"buildFiles": ["scripts/*.py"]}))
        expect_pass("a Ruby plist stamper", make_app(
            tmp, build="# packaging is ruby\n",
            extra={"scripts/stamp.rb": "plist['DragonCommitDate'] = date\n"},
            config_over={"buildFiles": ["scripts/*.rb"]}))
        expect_violation("the key named in a comment is not a stamp", make_app(
            tmp, build="""#!/bin/bash
# Stamps CFBundleVersion, and should stamp DragonCommitDate too.
# TODO: DragonCommitDate once the release workflow lands.
BUILD="$(git rev-list --count HEAD)"
"""), "R12",
            because="no build step stamps")
        expect_violation("declared buildFiles that don't stamp it", make_app(
            tmp, build='PlistBuddy -c "Set :DragonCommitDate $D" Info.plist\n',
            config_over={"buildFiles": ["Package.swift"]}), "R12",
            because="no build step stamps")

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
            tmp, locales=("en", "zh-Hant"), extra={"Sources/Lang.swift": language_pane()}), "R13",
            because="takes the kit's default of all")
        expect_pass("explicit list matching the shipped .lproj", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant]")}))
        expect_violation("explicit list wider than the shipped .lproj", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant, .ja]")}), "R13",
            because="must agree")
        # The other direction: a translation shipped that no user can select. Equality catches it
        # because the picker is the app's statement of its own coverage, and keykey's own
        # testLanguagePickerOffersExactlyTheShippedLocalizations asserts the same both ways.
        expect_violation("shipped .lproj the picker never offers", make_app(
            tmp, locales=("en", "zh-Hant", "ja"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant]")}), "R13",
            because="must agree")
        # Source case names are not locale codes — `.zhHant` is `zh-Hant.lproj` on disk. An
        # unrecognized token has to be reported rather than dropped, or a typo shrinks the offered
        # set until it agrees with a shorter .lproj list by accident.
        expect_violation("a token that is no DragonLanguage case", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhhant]")}), "R13",
            because="no DragonLanguage case")
        expect_violation("non-literal languages: argument", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: Self.supported")}), "R13",
            because="non-literal 'languages:' argument")
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
            tmp, locales=(), extra={"Sources/Lang.swift": language_pane()}), "R13",
            because="no '.lproj' is reachable")
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
"""}), "R13",
            because="takes the kit's default of all")
        # Three ways the rule used to read nothing where a picker stood, or read a picker where
        # none stood. `.init` spelled out is the same construction; an alias hides which languages
        # a picker offers; and a block comment was invisible to `strip_comment`, so a disabled
        # call was reported as a live one — a false violation with no compliant fix but deleting
        # the comment.
        expect_violation("LanguagePicker.init() is the same construction", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": """import SwiftUI
import DragonKit

struct LanguageSection: View {
    var body: some View { LanguagePicker.init() }
}
"""}), "R13",
            because="takes the kit's default of all")
        expect_violation("an aliased picker is reported, not skipped", make_app(
            tmp, locales=ALL_LOCALES,
            extra={"Sources/Lang.swift": """import SwiftUI
import DragonKit

typealias AppLanguagePicker = LanguagePicker

struct LanguageSection: View {
    var body: some View { AppLanguagePicker() }
}
"""}), "R13",
            because="aliases LanguagePicker")
        # The other half of the raw-string trap, on the rule whose line numbers come from the
        # masked copy: a raw string must not hide a live call below it, and `\\` inside one
        # escapes nothing.
        expect_violation("a raw string does not hide the picker below it", make_app(
            tmp, locales=("en", "zh-Hant"), extra={"Sources/Lang.swift": '''import SwiftUI
import DragonKit

let hint = #"type a straight " to search"#

struct LanguageSection: View {
    var body: some View { LanguagePicker() }
}
'''}), "R13",
            because="takes the kit's default of all")
        expect_pass("a block-commented call is not a call site", make_app(
            tmp, locales=("en", "zh-Hant"),
            extra={"Sources/Lang.swift": language_pane("languages: [.en, .zhHant]") + """
/* Superseded: LanguagePicker() offered all seven while this app shipped two.
   /* and Swift lets these nest, so the scanner has to as well */
*/
"""}))

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
                '"Copyright © 2026 Teddy Chan"')}), "R14",
            because="is a string literal")
        # The exact line 4.0.0 removed, hand-typed back in — the one route no signature can close.
        expect_violation("two copyright holders on one line", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                'DragonAbout.copyright(years: "2026", holder: "Teddy Chan")',
                '"© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan"')}), "R14",
            because="two copyright holders on one line")
        # Multi-line, exactly as clipmenu-2 and ice-2 wrote it. A compile error under 4.0.0 too,
        # but only while the @available(*, unavailable) overload carrying the message survives.
        expect_violation("the removed original: argument", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                'DragonAbout.copyright(years: "2026", holder: "Teddy Chan")',
                """DragonAbout.copyright(
                original: (years: "2008–2014", holder: "Naotaka Morimoto"),
                years: "2026",
                holder: "Teddy Chan"
            )""")}), "R14",
            because="the dual-holder")
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
        # The slot is checked positively now: whatever fills it must BE the kit's call. The old
        # test was `copyright:\\s*"` on a single line, so it saw a same-line literal and nothing
        # else — an indirection passed, and so did a literal wrapped onto the next line, which is
        # how these read as soon as the argument list is long enough to wrap.
        expect_violation("copyright from an indirection", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                'DragonAbout.copyright(years: "2026", holder: "Teddy Chan")',
                "Self.notice")}), "R14",
            because="the About copyright comes from")
        expect_violation("a literal wrapped onto the following line", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                'copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),',
                'copyright:\n                "Copyright 2026 Teddy Chan",')}), "R14",
            because="is a string literal")
        expect_pass("...and the kit's call wrapped the same way is fine", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about.replace(
                'copyright: DragonAbout.copyright(years: "2026", holder: "Teddy Chan"),',
                'copyright:\n                DragonAbout.copyright(years: "2026", '
                'holder: "Teddy Chan"),')}))
        # The label is located in the fully-masked copy and the *value* read from the
        # literal-preserving one. Reading the label out of the literal-preserving copy meant any
        # Swift string containing the text `copyright:` was reported as a bad About slot — and
        # yahoo-keykey-2's `sources: ["App", "Packages"]` reach its own test suite, which is the
        # trap §R13 hit for real. The fixture below this one asserts on `content.copyright`, a
        # property read with no label at all, so it never covered this.
        expect_pass("a literal containing the label is not the slot", make_app(
            tmp, extra={"Sources/AboutConfig.swift": compliant_about,
                        "Sources/Legacy.swift": """import Foundation

let legacyNotice = "copyright: (c) 2008 Somebody"
let template = "copyright: %@"
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
                "https://www.dragonapp.com\")!,\n            supportURL")}), "R15",
            because="but the support row's repository is")
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
                                                       "/fixture/\")!,\n            supportURL")}), "R15",
            because="but the support row's repository is")
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
                                                'dragonapp.com")!  // canon')}), "R15",
            because="but the support row's repository is")
        # An argument the checker cannot read must fail, not pass. R15 compares written literals,
        # so anything it can't resolve is a rule that would otherwise go quiet.
        expect_violation("a websiteURL R15 cannot resolve", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                'URL(string: "https://www.dragonapp.com/fixture-2/")!',
                "Self.site")}), "R15",
            because="cannot read 'websiteURL:'")
        expect_violation("a support row that names no repository", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                "https://github.com/teddychan/fixture-2/issues",
                "https://www.dragonapp.com/fixture-2/support/")}), "R15",
            because="which names no")
        # The hole this rule shipped with, and why the audit rates it CRITICAL: **neither host was
        # checked**. Only the path was compared, so any host carrying `/fixture-2/` satisfied the
        # rule — and `endswith("github.com")` is true of `notgithub.com`, which yielded an owner
        # and a repo and made the comparison agree with itself. Both fixtures below PASSED before
        # the fix. Three negative controls for §R15 already existed; all three tested paths and
        # none tested a host, which is exactly how this sat open underneath them.
        expect_violation("the right path on somebody else's site", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                "https://www.dragonapp.com/fixture-2/\")!,\n            supportURL",
                "https://evil-example.com/fixture-2/\")!,\n            supportURL")}), "R15",
            because="not the studio site")
        expect_violation("a support row on a github.com lookalike", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                "https://github.com/teddychan/fixture-2/issues",
                "https://notgithub.com/teddychan/fixture-2/issues")}), "R15",
            because="which names no")
        # ...and the label boundary has to cut the other way too, or the fix fails four real apps:
        # `www.` is a subdomain of each site, and the bare domain is the site itself.
        expect_pass("www. and the bare domain are both the site", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace(
                "https://www.dragonapp.com/fixture-2/\")!,\n            supportURL",
                "https://dragonapp.com/fixture-2/\")!,\n            supportURL").replace(
                    "https://github.com/teddychan/fixture-2/issues",
                    "https://www.github.com/teddychan/fixture-2/issues")}))
        # The silent-checker arm. An app that restructures its About wiring out of the checker's
        # sight must fail rather than drop out of the rule — §R0, §R10 and §R13 all take this line.
        expect_violation("no AboutContent construction anywhere", make_app(
            tmp, extra={about: "import Foundation\n\nenum AboutConfig { }\n"}), "R15",
            because="no AboutContent(…) construction is reachable")
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
        # Raw strings are the same trap, and unlike the multi-line case they are already in
        # shipping source: eight files in ice-2, two in spectacle-2. Without the `#` delimiter the
        # leading `"` opened a *plain* literal, the inner quotes re-paired, and an odd number of
        # them left the scanner inside a literal to end of file — blanking the real construction
        # below and reporting a conforming app for having no About pane at all. Reproduced on
        # ice-2's own AboutConfig.swift before the fix.
        # ONE raw string holding an ODD number of quotes is the whole defect: unaware of the `#`,
        # the scanner re-pairs the inner quotes, runs out of them, and stays inside a literal to
        # end of file — blanking the construction below. An even count would re-pair by luck and
        # prove nothing, so this fixture is deliberately minimal. Verified against the unfixed
        # scanner on ice-2's own AboutConfig.swift, which reported `R15 cannot read 'websiteURL:'`.
        odd_raw = COMPLIANT_ABOUT.replace(
            "enum AboutConfig {",
            'private let quoteHint = #"use a straight " here"#\n\nenum AboutConfig {')
        expect_pass("a raw string above the construction", make_app(
            tmp, extra={about: odd_raw}))
        expect_violation("...and the construction below it is still read", make_app(
            tmp, extra={about: odd_raw.replace("/fixture-2/\")!,\n            supportURL",
                                               "\")!,\n            supportURL")}), "R15",
            because="but the support row's repository is")
        # The other delimiter forms, as a positive control: `##"…"##` and the raw multi-line form
        # must not be read as code either.
        expect_pass("every raw-string delimiter form", make_app(
            tmp, extra={about: COMPLIANT_ABOUT.replace("enum AboutConfig {", '''enum AboutConfig {
    static let nested = ##"a "# sequence needs two hashes"##
    static let block = #"""
    A raw multi-line "quote", 12" wide.
    """#
''')}))
        expect_violation("...and the construction below it is still read", make_app(
            tmp, extra={about: multiline.replace("/fixture-2/\")!,\n            supportURL",
                                                 "\")!,\n            supportURL")}), "R15",
            because="but the support row's repository is")
        # ...and the other direction, the one R13 also pins: prose cannot satisfy the rule either.
        expect_violation("a commented-out construction does not count as one", make_app(
            tmp, extra={about: """import Foundation
import DragonKit

// AboutContent(websiteURL: URL(string: "https://www.dragonapp.com/fixture-2/")!,
//              supportURL: URL(string: "https://github.com/teddychan/fixture-2/issues")!)
enum AboutConfig { }
"""}), "R15",
            because="no AboutContent(…) construction is reachable")

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

    check_canon_pane_order_is_quoted_not_paraphrased()

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
