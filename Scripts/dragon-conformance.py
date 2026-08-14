#!/usr/bin/env python3
"""DragonKit conformance checker — enforces CONFORMANCE.md against an app repo.

Every rule here corresponds to drift that actually shipped; see CONFORMANCE.md for the
history behind each one. Exits 1 on any violation so CI fails the PR.

    python3 dragon-conformance.py --app /path/to/app-repo [--kit /path/to/dragon-kit]
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass, field

# Lifecycle item titles the kit owns (R1). Matched against Swift string literals and L() keys.
LIFECYCLE_PATTERNS = [
    r"About\s+%@", r"About\s+[A-Z]", r"Check\s+for\s+[Uu]pdates", r"Settings…", r"Quit\s",
    r"DragonKit\.menu\.", r"\.menu\.about", r"\.menu\.settings", r"\.menu\.quit",
    r"\.menu\.checkForUpdates",
]
# Keys an app must not define (R8): the kit's canonical menu titles used verbatim as keys.
KIT_OWNED_LITERAL_KEYS = [
    "About %@", "Check for Updates…", "Check for updates…", "Settings…", "Quit %@",
    "Uninstall %@…", "Uninstall %@...",
]
# Canonical relative order of settings panes (R9). Each slot lists the spellings an app may
# use: the kit's pane type, or the enum-case name for an app that drives its sidebar from an
# enum (ice-2). Order is compared on slots, so the two styles are equivalent.
CANONICAL_PANE_SLOTS = [
    ("General", ("GeneralPane", "general")),
    ("Permissions", ("PermissionsSettingsPane", "PermissionsPane", "permissions")),
    # `SyncBackupPane`/`syncBackup` is clipmenu-2's own backup pane — a sanctioned deferral
    # (iCloud sync + versioned folder backup, because DragonBackup is UserDefaults-suite only),
    # carried by this slot rather than by an §R11 exception, which it never needed.
    # Without those spellings the slot was never *seen* for the one app that diverges — and R9
    # compares only the slots it saw, so clipmenu-2's backup pane could sit anywhere in the
    # order and the rule still printed PASS. Verified: `\bbackup\b` does not match
    # `SyncBackupPane` (no word boundary, wrong case), and clipmenu-2 passed R9 with this slot
    # entirely unchecked. A checker that silently skips the app it exists to check is exactly
    # the failure this spec was written to prevent.
    ("Backup", ("BackupSettingsPane", "backup", "SyncBackupPane", "syncBackup")),
    ("What's New", ("WhatsNewSettingsPane", "WhatsNewPane", "whatsNew")),
    ("Updates", ("UpdatesSettingsPane", "updates")),
    ("About", ("AboutSettingsPane", "AboutPane", "about")),
    ("Uninstall", ("UninstallSettingsPane", "uninstall")),
]
# Anchored at column 0 on purpose: only a TOP-LEVEL declaration can shadow a top-level kit
# type. A nested type lives in its own namespace — ice-2's `SettingsBackup.BackupError` cannot
# shadow `DragonBackup.BackupError`, and reporting it was a false positive.
SWIFT_DECL = re.compile(r"^(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+)*"
                        r"(?:struct|class|enum|protocol)\s+([A-Za-z_][A-Za-z0-9_]*)")
# A settings layout primitive is a *generic view wrapper* — `struct IceForm<Content: View>: View`.
# The name alone is far too broad a signal: ice-2's `MenuBarSection` is a menu-bar model and has
# nothing to do with settings layout, so matching on the suffix alone produced a false positive.
#
# `GroupBox` is deliberately NOT in this list. ice-2's `IceGroupBox` was a bordered box, and the
# kit has no equivalent — so the rule offered no compliant path except inlining it or renaming it
# to dodge the check. A rule you can only satisfy by gaming it is a bad rule.
LAYOUT_PRIMITIVE = re.compile(
    r"^\s*(?:public\s+|internal\s+|private\s+|fileprivate\s+|final\s+)*"
    r"(?:struct|class)\s+([A-Za-z_][A-Za-z0-9_]*(?:Form|Section))\s*<[^>]*:\s*View")
# Directories that are never app source (agent worktrees, vendored kit, build output).
SKIP_DIRS = {".git", ".build", "vendor", "build", "DerivedData", ".claude", "node_modules"}

# Where R12 looks for the `DragonCommitDate` stamp when an app declares no `buildFiles`.
# Broad on purpose: the four apps package themselves four different ways (SwiftPM script,
# Xcode project, a bare swiftc script, and the shared release workflow).
DEFAULT_BUILD_FILES = [
    "*.sh", "scripts/*.sh", "scripts/**/*.sh", "**/scripts/*.sh",
    ".github/workflows/*.yml", "**/Info.plist", "**/*.pbxproj",
]


@dataclass
class Violation:
    rule: str
    message: str
    path: str = ""
    line: int = 0

    def render(self, root: str) -> str:
        where = ""
        if self.path:
            rel = os.path.relpath(self.path, root)
            where = f"{rel}:{self.line}: " if self.line else f"{rel}: "
        return f"  {self.rule}  {where}{self.message}"


@dataclass
class Config:
    app: str
    sources: list[str]
    strings: list[str] = field(default_factory=list)
    pin: dict = field(default_factory=dict)
    pane_order: dict = field(default_factory=dict)
    traits: list[str] = field(default_factory=list)
    build_files: list[str] = field(default_factory=list)
    exceptions: list[dict] = field(default_factory=list)

    def excuses(self, rule: str, path: str) -> bool:
        """True when a sanctioned exception covers this rule at this path (R11)."""
        for exc in self.exceptions:
            if exc.get("rule") != rule:
                continue
            p = exc.get("path", "")
            if not p or p in path.replace(os.sep, "/"):
                return True
        return False


def skipped(path: str, root: str) -> bool:
    """Whether `path` lies in a build/vendor directory *inside the app*.

    Relative to `root`, never on the absolute path. Splitting the absolute path matches
    directories above the app too — and this repo's own worktrees live under `.claude/`, which is
    in ``SKIP_DIRS``, so an absolute-path test silently skipped every file in the checkout and
    reported a clean pass. A rule that cannot fail is worse than no rule.
    """
    rel = os.path.relpath(path, root)
    return any(part in SKIP_DIRS for part in rel.split(os.sep))


def swift_files(root: str, sources: list[str]) -> list[str]:
    found: list[str] = []
    for src in sources:
        base = os.path.join(root, src)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS
                           and not d.endswith(".xcodeproj")]
            found.extend(os.path.join(dirpath, f) for f in filenames if f.endswith(".swift"))
    return sorted(found)


def read(path: str) -> list[str]:
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.readlines()


def strip_comment(line: str) -> str:
    """Drop // comments so documentation prose never trips a rule."""
    idx = line.find("//")
    return line if idx < 0 else line[:idx]


def strip_literals(line: str) -> str:
    """Blank out "…" string literals so code that merely *names* a call isn't read as one.

    R13 needs this on top of ``strip_comment``. yahoo-keykey-2 declares
    `sources: ["App", "Packages"]`, which covers
    `Packages/KeyKeyApp/Tests/KeyKeyAppTests/ConfigContentTests.swift` — the app-side test that
    enforces this very rule, and which contains `code.range(of: "LanguagePicker(languages:")`.
    That is a literal, not a comment, so comment-stripping alone reports a call site inside the
    test written to catch the bug. A rule whose first false positive is the app it was written
    for is not a rule anyone will keep.
    """
    return re.sub(r'"[^"\n]*"', '""', line)


def mask_noncode(text: str, *, blank_literals: bool = True) -> str:
    """A copy of `text` with comment text — and, by default, string-literal *contents* — blanked.

    Length-preserving, which is the point: a rule needs both halves of one file at once. The masked
    copy says which occurrences of a call are real code, and the original holds the literals written
    inside it. One index space serves both.

    Neither line-based helper can do it. ``strip_comment`` cuts `URL(string: "https://…")` at the
    slashes in `https://`, and clipmenu-2 and ice-2 both name their website constant on exactly
    such a line; ``strip_literals`` collapses `"…"` to `""` and moves every offset after it.

    Scanned in one pass over the whole file rather than line by line, because every state here
    outlives a line: a Swift multi-line string spans them, a `/* … */` spans them, and a line inside
    a literal that contains a URL would otherwise have its `//` read as a comment. The triple-quote
    delimiter is matched as a unit for the same reason — read as three single quotes it goes
    open-close-open, so any odd number of `"` inside the block leaves the scanner stuck in a
    literal, blanks the real construction below it and reports a conforming app for having none.
    Twenty-seven files across the five apps use multi-line strings.

    `blank_literals=False` keeps literal contents, for §R14: the dual-holder copyright it exists to
    catch is written *inside* a literal, so blanking one would hide the very thing being counted.
    Comments go either way — that is the half every caller needs.

    `/* … */` is handled, and nests the way Swift's does. It used to be skipped deliberately, on the
    grounds that no app wrote one in the wiring these rules read — but skipping it cut both ways:
    `/* LanguagePicker() */` was a false §R13 violation, and a block comment was an unread route
    past every rule that strips only `//`.
    """
    out = list(text)
    inside: str | None = None  # the delimiter that opened the literal we are in
    depth = 0                  # nesting depth of /* … */, which Swift allows
    index = 0
    while index < len(text):
        if depth:
            if text.startswith("/*", index):
                depth += 1
            elif text.startswith("*/", index):
                depth -= 1
            else:
                if text[index] != "\n":
                    out[index] = " "
                index += 1
                continue
            out[index] = out[index + 1] = " "
            index += 2
            continue
        if inside is None:
            if text.startswith('"""', index):
                inside, index = '"""', index + 3
            elif text[index] == '"':
                inside, index = '"', index + 1
            elif text.startswith("//", index):
                while index < len(text) and text[index] != "\n":
                    out[index] = " "
                    index += 1
            elif text.startswith("/*", index):
                depth = 1
                out[index] = out[index + 1] = " "
                index += 2
            else:
                index += 1
            continue
        if text[index] == "\\":  # an escape, so the next character closes nothing
            if blank_literals:
                out[index] = " "
                if index + 1 < len(text):
                    out[index + 1] = " "
            index += 2
        elif text.startswith(inside, index):
            index += len(inside)
            inside = None
        else:
            if blank_literals and text[index] != "\n":
                out[index] = " "
            index += 1
    return "".join(out)


def line_of(body: str, index: int) -> int:
    """The 1-based line number of `index` in `body`."""
    return body.count("\n", 0, index) + 1


def literal_at(body: str, masked: str, quote: int) -> str | None:
    """The contents of the string literal whose opening quote sits at `quote`.

    Masking blanks a literal's contents but keeps both of its quotes, so the closing one is still
    findable in `masked` at the index it occupies in `body`.
    """
    end = masked.find('"', quote + 1)
    return body[quote + 1:end] if end >= 0 else None


def balanced(text: str, start: int) -> str | None:
    """Text between the bracket at `text[start]` and its match, or None if unbalanced."""
    depth = 0
    for index in range(start, len(text)):
        if text[index] in "([{":
            depth += 1
        elif text[index] in ")]}":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
    return None


def kit_public_types(kit: str) -> set[str]:
    """Derive the kit's public type names from its sources, so the list can't go stale."""
    names: set[str] = set()
    # Column-0 anchored: only top-level public types are shadowable. Previously this scraped
    # nested types too, which is why `Config` and `Kind` had to be hand-excluded — a symptom of
    # this bug rather than a real exception.
    pattern = re.compile(r"^public\s+(?:final\s+)?(?:struct|class|enum|protocol|actor)\s+"
                         r"([A-Za-z_][A-Za-z0-9_]*)")
    for dirpath, dirnames, filenames in os.walk(os.path.join(kit, "Sources")):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if not name.endswith(".swift"):
                continue
            for line in read(os.path.join(dirpath, name)):
                match = pattern.match(line)
                if match:
                    names.add(match.group(1))
    return names


def kit_languages(kit: str) -> dict[str, str]:
    """Map `DragonLanguage` case names to `.lproj` locale codes, read from the kit's own source.

    `zhHant` in Swift is `zh-Hant.lproj` on disk, so R13 cannot compare a written argument list
    against a directory listing without this. Derived rather than hardcoded for the same reason
    ``kit_public_types`` is: the day the kit adds a language, a frozen list of seven would leave
    R13 quietly demanding the old set from every app.
    """
    case = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*\"([^\"]+)\")?\s*$")
    for dirpath, dirnames, filenames in os.walk(os.path.join(kit, "Sources")):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in sorted(filenames):
            if not name.endswith(".swift"):
                continue
            lines = read(os.path.join(dirpath, name))
            start = next((i for i, line in enumerate(lines)
                          if re.match(r"public\s+enum\s+DragonLanguage\b", line)), None)
            if start is None:
                continue
            found: dict[str, str] = {}
            for line in lines[start + 1:]:
                if line.startswith("}"):  # the enum's own close; nested braces are indented
                    break
                match = case.match(strip_comment(line))
                # `.system` is not a language — it means "follow the OS order" — and the picker
                # renders it separately above the divider. The switch in `displayName` is scanned
                # too, harmlessly: its `case .en:` starts with a dot, which this pattern rejects.
                if match and match.group(1) != "system":
                    found[match.group(1)] = match.group(2) or match.group(1)
            if found:
                return found
    raise SystemExit("R13  cannot find 'public enum DragonLanguage' in the kit's sources, so the "
                     "language set is unknown.\n     Fix the checker — do not let R13 pass by "
                     "having nothing to compare against.")


def latest_kit_version(kit: str) -> tuple[int, int, int] | None:
    try:
        out = subprocess.run(["git", "tag", "--list", "v[0-9]*"], cwd=kit,
                             capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    versions = []
    for tag in out.split():
        match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag.strip())
        if match:
            versions.append(tuple(int(g) for g in match.groups()))
    return max(versions) if versions else None


# --------------------------------------------------------------------------- rules

def rule_r1_r2_menu(root: str, cfg: Config, files: list[str]) -> list[Violation]:
    """Both halves read the code, not the line.

    Two line-based substring tests used to decide this. `"DragonAppMenu" in line` counted the name
    wherever it appeared, so `let marker = "DragonAppMenu"` — or the name in a comment — satisfied
    §R1 for an app that never called it; the masked copy sees only real code. And an `NSMenuItem(`
    whose title sat on the *next* line matched neither the lifecycle patterns nor §R2's `uninstall`,
    which is the spelling every one of these calls takes once it has four arguments. The call's
    arguments are now read as a whole, from the original text so the titles are intact.
    """
    out: list[Violation] = []
    uses_kit_menu = False
    for path in files:
        body = "".join(read(path))
        masked = mask_noncode(body)
        if "DragonAppMenu" in masked:
            uses_kit_menu = True
        if cfg.excuses("R1", path):
            continue
        for call in re.finditer(r"\bNSMenuItem\s*\(", masked):
            span = balanced(masked, call.end() - 1)
            if span is None:
                continue
            args = body[call.end():call.end() + len(span)]
            number = line_of(body, call.start())
            if re.search(r"uninstall", args, re.IGNORECASE):
                out.append(Violation("R2", "menu item for Uninstall — it belongs in "
                                     "UninstallSettingsPane, not the dropdown", path, number))
                continue
            for pattern in LIFECYCLE_PATTERNS:
                if re.search(pattern, args):
                    out.append(Violation("R1", "hand-rolled app-lifecycle menu item — build it "
                                         "with DragonAppMenu.items(_:)", path, number))
                    break
    if files and not uses_kit_menu and not cfg.excuses("R1", ""):
        out.append(Violation("R1", "app never references DragonAppMenu; the menu-bar dropdown "
                             "must come from the kit"))
    return out


def rule_r3_shadowed_types(root: str, cfg: Config, files: list[str],
                           kit_types: set[str]) -> list[Violation]:
    out: list[Violation] = []
    for path in files:
        for number, raw in enumerate(read(path), 1):
            match = SWIFT_DECL.match(strip_comment(raw))
            if match and match.group(1) in kit_types and not cfg.excuses("R3", path):
                name = match.group(1)
                out.append(Violation("R3", f"declares '{name}', shadowing the public DragonKit "
                                     f"type — the local one silently wins", path, number))
    return out


def rule_r4_design_primitives(root: str, cfg: Config, files: list[str]) -> list[Violation]:
    out: list[Violation] = []
    for path in files:
        if cfg.excuses("R4", path):
            continue
        lines = read(path)
        body = "".join(strip_comment(line) for line in lines)
        if "Form {" in body and ".formStyle(.grouped)" in body:
            number = next((i for i, l in enumerate(lines, 1)
                           if ".formStyle(.grouped)" in strip_comment(l)), 0)
            out.append(Violation("R4", "hand-rolled grouped Form — use DragonForm / "
                                 "DragonSection", path, number))
        for number, raw in enumerate(lines, 1):
            match = LAYOUT_PRIMITIVE.match(strip_comment(raw))
            if match:
                out.append(Violation("R4", f"declares '{match.group(1)}', a generic view wrapper "
                                     f"duplicating DragonForm / DragonSection", path, number))
    return out


def rule_r5_shared_panes(root: str, cfg: Config, files: list[str]) -> list[Violation]:
    """Read from code only: a *commented-out* pane reference used to satisfy this rule.

    It searched the raw text of every source file, so `// AnySettingsPane(UninstallSettingsPane…)`
    left behind by a migration counted as wiring the kit's pane — the one rule where prose about
    the kit was accepted as use of the kit.
    """
    body = "".join(mask_noncode("".join(read(path))) for path in files)
    required = [("AboutSettingsPane", "AboutPane"), ("WhatsNewSettingsPane", "WhatsNewPane"),
                ("UninstallSettingsPane",)]
    if "sparkle" in cfg.traits:
        required.append(("UpdatesSettingsPane",))
    if "no-permissions" not in cfg.traits:
        required.append(("PermissionsSettingsPane", "PermissionsPane"))
    out: list[Violation] = []
    for names in required:
        if not any(name in body for name in names) and not cfg.excuses("R5", ""):
            out.append(Violation("R5", f"no reference to {' or '.join(names)} — shared panes "
                                 f"must come from the kit"))
    return out


def rule_r6_r7_modules(root: str, cfg: Config, files: list[str]) -> list[Violation]:
    checks = [
        ("R6", r"\bimport\s+Sparkle\b|SPUStandardUpdaterController|\bSPUUpdater\b",
         "direct Sparkle use — updates go through DragonKitUpdates' DragonUpdater"),
        ("R7", r"\bSMAppService\b|\bimport\s+LaunchAtLogin\b",
         "direct launch-at-login wiring — use the kit's LoginItem"),
    ]
    out: list[Violation] = []
    for path in files:
        for number, raw in enumerate(read(path), 1):
            line = strip_comment(raw)
            for rule, pattern, message in checks:
                if re.search(pattern, line) and not cfg.excuses(rule, path):
                    out.append(Violation(rule, message, path, number))
    return out


def rule_r8_kit_strings(root: str, cfg: Config) -> list[Violation]:
    out: list[Violation] = []
    for pattern in cfg.strings:
        for path in glob.glob(os.path.join(root, pattern), recursive=True):
            if skipped(path, root):
                continue
            for number, raw in enumerate(read(path), 1):
                match = re.match(r'\s*"([^"]+)"\s*=', raw)
                if not match:
                    continue
                key = match.group(1)
                if key.startswith("DragonKit."):
                    out.append(Violation("R8", f"defines kit-owned key '{key}' — the module "
                                         f"bundle wins, so this is dead weight", path, number))
                elif key in KIT_OWNED_LITERAL_KEYS:
                    out.append(Violation("R8", f"defines '{key}', a kit-owned menu title — "
                                         f"this is how the casing drifted", path, number))
    return out


def rule_r9_pane_order(root: str, cfg: Config) -> list[Violation]:
    target = cfg.pane_order.get("file")
    if not target:
        return []
    path = os.path.join(root, target)
    if not os.path.exists(path):
        return [Violation("R9", f"paneOrder.file '{target}' does not exist")]
    seen: list[str] = []
    for raw in read(path):
        line = strip_comment(raw)
        for slot, spellings in CANONICAL_PANE_SLOTS:
            if slot in seen:
                continue
            if any(re.search(rf"\b{re.escape(name)}\b", line) for name in spellings):
                seen.append(slot)
    expected = [slot for slot, _ in CANONICAL_PANE_SLOTS if slot in seen]
    if seen != expected:
        return [Violation("R9", f"settings pane order is {seen}, canon is {expected} "
                          f"(order is read from {target})", path)]
    return []


def rule_r10_pin(root: str, cfg: Config, kit: str) -> list[Violation]:
    spec = cfg.pin
    # `{"kind": "path"}` used to return no violations, for the one app that lived inside
    # dragon-kit and depended on it by `path: ".."`: current by construction, no version to fall
    # behind. That app owns its own repository now — MAC-APP-RELEASE-LIFECYCLE.md allows one
    # public vX.Y.Z series per repository and this one's belongs to the Swift package — so nothing
    # qualifies any more, and a branch that answers "compliant" to whichever app declares it is a
    # hole rather than an exemption. It is the same shape as deleting .dragon-conformance.json,
    # which §R0 makes a violation for exactly this reason. test_conformance.py never covered it,
    # which is how an untested always-pass branch sat in the checker unnoticed.
    if spec.get("kind") == "path":
        return [Violation("R10", 'pin declares {"kind": "path"}; the exemption is retired — '
                          "every app pins a published DragonKit version")]
    if not spec.get("file") or not spec.get("pattern"):
        return [Violation("R10", "config declares no 'pin' — cannot verify the DragonKit "
                          "version is current")]
    # §R0 has said the pattern MUST anchor on dragon-kit since the trap was found, and nothing
    # enforced it — while `test_conformance.py` asserted the false pass it produces as *expected
    # behaviour*. The pattern is one search over the whole file, so an unanchored version regex
    # matches whichever dependency appears first: `minimumVersion = ([0-9.]+)` read Sparkle's
    # 2.5.2 out of ice-2's .pbxproj and compared that against the kit's tags, reporting a pass
    # while the real pin was stale. Compared with the separators removed so yahoo-keykey-2's
    # `DRAGONKIT_TAG="v([0-9.]+)"` anchors as surely as `dragon-kit", from: "([0-9.]+)"`.
    if "dragonkit" not in re.sub(r"[^a-z0-9]", "", spec["pattern"].lower()):
        return [Violation("R10", f"pin.pattern {spec['pattern']!r} does not anchor on dragon-kit "
                          "— one unanchored search over the file matches whichever dependency "
                          "comes first, which is how a stale pin reported PASS against Sparkle's "
                          'version. Anchor it: "dragon-kit\\";[^}]*minimumVersion = ([0-9.]+)"')]
    path = os.path.join(root, spec["file"])
    if not os.path.exists(path):
        return [Violation("R10", f"pin.file '{spec['file']}' does not exist")]
    match = re.search(spec["pattern"], "".join(read(path)))
    if not match:
        return [Violation("R10", f"pin.pattern found no DragonKit version in "
                          f"{spec['file']}", path)]
    found = tuple(int(part) for part in match.group(1).split("."))
    latest = latest_kit_version(kit)
    if latest is None:
        return []
    if found < latest:
        pretty_found = ".".join(str(n) for n in found)
        pretty_latest = ".".join(str(n) for n in latest)
        return [Violation("R10", f"pinned to DragonKit {pretty_found} but {pretty_latest} is "
                          f"released — a stale pin silently misses shared fixes", path)]
    return []


def rule_r12_commit_date(root: str, cfg: Config) -> list[Violation]:
    """The build must stamp `DragonCommitDate` into Info.plist.

    About renders `v2.4.1 (756) · 2026-Aug-07 16:54:20 UTC`. The build number is
    `git rev-list --count HEAD`, and the timestamp used to be the *executable's* modification
    date — when CI linked and signed the binary. The two halves therefore described different
    things and drifted apart: rebuild the same commit tomorrow and the count holds while the date
    moves. `DragonAbout` now reads `DragonCommitDate` (`git log -1 --format=%cI`) so the whole
    line fingerprints one commit, and deliberately shows no date at all when the key is missing —
    a silent fallback to the old meaning is the drift this replaced. An app that never stamps the
    key silently loses the timestamp, which is what this rule catches.

    Checked by grepping the app's build surface rather than by running it: whichever of a shell
    script, a workflow, an Info.plist or an Xcode project stamps the key, the key has to appear
    in the repo somewhere.
    """
    if cfg.excuses("R12", ""):
        return []
    for pattern in (cfg.build_files or DEFAULT_BUILD_FILES):
        for path in glob.glob(os.path.join(root, pattern), recursive=True):
            if skipped(path, root) or not os.path.isfile(path):
                continue
            if "DragonCommitDate" in "".join(read(path)):
                return []
    return [Violation("R12", "no build step stamps 'DragonCommitDate' into Info.plist — About's "
                      "version line will show no build timestamp (searched "
                      f"{cfg.build_files or DEFAULT_BUILD_FILES})")]


def app_localizations(root: str, cfg: Config, kit_codes: set[str]) -> set[str]:
    """The locale codes the app ships its OWN strings in, from the `.lproj` path components of
    the `strings` globs R8 already declares — an app states its localization set once.

    A code `DragonLanguage` has no case for is dropped rather than counted. `Base.lproj` is not a
    language, and a `de.lproj` is one the picker physically cannot list, so counting either would
    leave R13 with no satisfiable form — the `IceGroupBox` mistake, a rule whose only compliant
    path is to game it. The direction that matters is untouched: a code the kit lacks can never
    appear in the offered list either.
    """
    found: set[str] = set()
    for pattern in cfg.strings:
        for path in glob.glob(os.path.join(root, pattern), recursive=True):
            if skipped(path, root):
                continue
            for part in os.path.relpath(path, root).split(os.sep):
                code = part[:-len(".lproj")] if part.endswith(".lproj") else ""
                if code in kit_codes:
                    found.add(code)
    return found


def rule_r13_language_picker(root: str, cfg: Config, files: list[str],
                             languages: dict[str, str]) -> list[Violation]:
    """Every `LanguagePicker` must offer exactly the languages the app has translated itself into.

    yahoo-keykey-2 shipped through v2.11.4 calling `LanguagePicker()` bare while shipping only
    `App/en.lproj` and `App/zh-Hant.lproj`, so Settings offered Español, Français, 日本語, 한국어
    and 简体中文 — and choosing one translated the kit's four panes while every KeyKey string fell
    back to English. ice-2 hit the same default first (PR #83 added Simplified Chinese alone) and
    its contributor hand-rolled a three-option picker in `GeneralSettingsPane`, the
    re-implementation §R4 forbids. DragonKit 3.4.0 added the `languages:` parameter for exactly
    this, and the parameter existing did not stop it happening again: nothing failed on keykey's
    picker, which was found by eye while verifying an unrelated pin bump.

    Compared as equality, in both directions, because the picker is the app's statement of its own
    coverage. Offering more than it ships is the shipping bug above; shipping more than it offers
    is translation work no user can reach. A bare call is not itself a violation — it means the
    default, `DragonLanguage.selectable`, which is the correct list for the three apps whose
    coverage matches the kit's. Requiring an explicit argument instead would fail clipmenu-2,
    spectacle-2 and dragon-sample-app for being right.
    """
    kit_codes = set(languages.values())
    shipped = app_localizations(root, cfg, kit_codes)
    everything = ", ".join(sorted(kit_codes))
    out: list[Violation] = []
    for path in files:
        if cfg.excuses("R13", path):
            continue
        raw_body = "".join(read(path))
        # Masked rather than line-stripped: `strip_comment` never saw `/* LanguagePicker() */`, so
        # a block-commented call was a false violation, and a block comment was an unread route
        # past the rule in both directions.
        body = mask_noncode(raw_body)
        # An alias puts the call site out of the rule's sight — `typealias LP = LanguagePicker`
        # then `LP()` reads as no picker at all. Reported rather than chased: R13 compares written
        # arguments, so one hop of type indirection has no written argument to compare.
        for alias in re.finditer(r"\btypealias\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*LanguagePicker\b",
                                 body):
            out.append(Violation("R13", f"aliases LanguagePicker as '{alias.group(1)}' — R13 reads "
                                 "the written call site, so an alias hides which languages the "
                                 "picker offers. Construct LanguagePicker by name", path,
                                 line_of(body, alias.start())))
        # `.init` spelled out is the same construction and used to be invisible to this rule.
        for call in re.finditer(r"\bLanguagePicker\s*(?:\.\s*init\s*)?\(", body):
            number = line_of(body, call.start())
            args = balanced(body, call.end() - 1) or ""
            if not shipped:
                out.append(Violation("R13", "constructs LanguagePicker, but no '.lproj' is "
                                     f"reachable through 'strings' ({cfg.strings or '[]'}) — the "
                                     "checker cannot tell which languages this app ships. Point "
                                     "'strings' at the app's locale files, or sanction R13 in "
                                     "'exceptions' with a reason and an owner (§R11)", path,
                                     number))
                continue
            if "languages:" not in args:  # took the default, DragonLanguage.selectable
                if shipped == kit_codes:
                    continue
                fix = ", ".join("." + name for name, code in sorted(languages.items())
                                if code in shipped)
                out.append(Violation("R13", f"LanguagePicker takes the kit's default of all "
                                     f"{len(kit_codes)} languages ({everything}) but this app "
                                     f"ships only {', '.join(sorted(shipped))} — the others "
                                     f"translate the kit's panes and leave every app string in "
                                     f"English. Pass languages: [{fix}]", path, number))
                continue
            start = args.find("[", args.find("languages:"))
            listed = balanced(args, start) if start >= 0 else None
            if listed is None:
                out.append(Violation("R13", "passes a non-literal 'languages:' argument — R13 "
                                     "compares the written list against the app's '.lproj', so it "
                                     "has to be a literal like [.en, .zhHant]", path, number))
                continue
            tokens = [token.strip().lstrip(".") for token in listed.split(",")]
            tokens = [token for token in tokens if token]
            # Mapping through the case names, and reporting an unrecognized one instead of
            # dropping it, is what stops a typo'd `.zhhant` from shrinking the offered set until
            # it accidentally agrees with a shorter `.lproj` list.
            unknown = [token for token in tokens if token not in languages]
            if unknown:
                out.append(Violation("R13", f"'languages:' names {', '.join(unknown)}, which is "
                                     f"no DragonLanguage case", path, number))
                continue
            offered = {languages[token] for token in tokens}
            if offered != shipped:
                out.append(Violation("R13", f"LanguagePicker offers "
                                     f"{', '.join(sorted(offered)) or '(nothing)'} but the app "
                                     f"ships {', '.join(sorted(shipped))} — the picker and the "
                                     f"app's '.lproj' must agree", path, number))
    return out


def rule_r14_about_copyright(root: str, cfg: Config, files: list[str]) -> list[Violation]:
    """The About copyright is kit-assembled and names one holder — the app's own.

    Every other slot in the About pane is now closed by the kit's own signature: `licensesURL` is
    a required parameter, and the upstream project's URL lives inside `OriginalWork`, so an app
    cannot ship a `Based on` credit with no `Original project` link (clipmenu-2 and ice-2 both
    did) or list bundled components with no notices page (spectacle-2 and the sample app both
    did). Those are compile errors in DragonKit 4.0.0 and need no rule here.

    `copyright` is the exception, and the reason this rule exists: it is a plain `String`, so no
    signature can stop an app hand-typing `© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan` and
    reintroducing the dual-holder line 4.0.0 removed. A Dragon app reimplements its upstream
    rather than reusing its source, so asserting the upstream author's copyright over *this*
    binary states something the app's own notices contradict; the lineage belongs to
    `OriginalWork` and the upstream licence text to the licences page.

    Three ways in, all checked: a literal in the slot, two copyright symbols on one line, and the
    removed `original:` argument (a compile error today, but the `@available(*, unavailable)`
    overload carrying that message is temporary, and after it goes the compiler only says "extra
    argument").
    """
    out: list[Violation] = []
    slot = re.compile(r"\bcopyright\s*:\s*")
    kit_call = re.compile(r"DragonAbout\s*\.\s*copyright\s*\(")
    dual_form = re.compile(r"DragonAbout\s*\.\s*copyright\s*\(\s*original\s*:")
    for path in files:
        if cfg.excuses("R14", path):
            continue
        body = "".join(read(path))
        # Literals are kept: the dual-holder line this rule exists to catch is written *inside*
        # one, so blanking them would hide the thing being counted. Comments still go, which is
        # what lets ice-2 discuss the old spelling in a comment without failing.
        masked = mask_noncode(body, blank_literals=False)
        # Positive: whatever fills the slot must BE the kit's call. The old test was
        # `copyright:\s*"` on one line, so it saw a literal on the same line and nothing else —
        # `copyright: Self.notice` passed, and so did a literal wrapped onto the following line,
        # which is how every one of these reads once the argument list is long enough to wrap.
        for match in slot.finditer(masked):
            value = masked[match.end():].lstrip()
            if kit_call.match(value):
                continue
            number = line_of(masked, match.start())
            if value.startswith('"'):
                out.append(Violation("R14", "the About copyright is a string literal — assemble "
                                     "it with DragonAbout.copyright(years:holder:) so every app "
                                     "formats it identically", path, number))
            else:
                out.append(Violation("R14", f"the About copyright comes from "
                                     f"'{value.split(chr(10))[0].strip()[:40]}' — assemble it with "
                                     "DragonAbout.copyright(years:holder:); R14 reads the written "
                                     "call site and cannot follow an indirection to check what it "
                                     "names", path, number))
        for number, line in enumerate(masked.splitlines(), 1):
            if line.count("©") > 1:
                out.append(Violation("R14", "two copyright holders on one line — the About "
                                     "copyright names the app's own holder only; the upstream "
                                     "author is credited by OriginalWork and their licence text "
                                     "by the licences page", path, number))
        if dual_form.search(masked):
            out.append(Violation("R14", "DragonAbout.copyright(original:) — the dual-holder "
                                 "copyright was removed in DragonKit 4.0.0; call "
                                 "copyright(years:holder:)", path))
    return out


# `URL(string: "…")`, the only spelling any of the five apps uses for an About row. Matched up to
# the opening quote only: these run against the *masked* copy, where the contents are blanked, and
# ``literal_at`` reads them back out of the original.
URL_LITERAL = re.compile(r'URL\s*\(\s*string:\s*"')
# `private static let websiteURL = URL(string: "…")!` — clipmenu-2 and ice-2 both name their two
# URLs before passing them, so R15 has to follow one hop of indirection or it reads nothing at all
# for two of the five apps. One hop only: a constant assigned from another constant is reported as
# unreadable rather than chased, because a rule that quietly gives up is the failure mode here.
URL_CONSTANT = re.compile(r'\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::[^=\n]+)?=\s*'
                          r'URL\s*\(\s*string:\s*"')


def host_is(url: str, domain: str) -> bool:
    """Whether `url`'s host is `domain` or a subdomain of it — `AboutLinkDetail.host(of:is:)`.

    A bare `endswith("github.com")` — which this replaces on both sides — is also true of
    **`notgithub.com`**, so a support row on a lookalike host yielded an owner and a repo and
    read as a GitHub link everywhere. The leading dot is what makes `www.` a subdomain and
    `notgithub` a different registrable name.
    """
    host = (urllib.parse.urlsplit(url).hostname or "").lower()
    return host == domain or host.endswith("." + domain)


def github_repository(url: str) -> str | None:
    """The repo name in a `github.com/owner/repo/...` URL — `AboutLinkDetail.repository(of:)`."""
    if not host_is(url, "github.com"):
        return None
    segments = [segment for segment in urllib.parse.urlsplit(url).path.split("/") if segment]
    return segments[1] if len(segments) >= 2 else None


def about_argument(masked: str, start: int, end: int, label: str) -> tuple[int, int] | None:
    """Where a labelled `AboutContent(` argument's value sits, or None if it isn't passed.

    Located in the masked copy — so a comment or a literal mentioning the label cannot win — and
    returned as absolute indices, because the value itself has to be read from the original.
    """
    match = re.compile(rf"\b{label}\s*:\s*([^,]+)").search(masked, start, end)
    return match.span(1) if match else None


def rule_r15_website_page(root: str, cfg: Config, files: list[str]) -> list[Violation]:
    """About's Website row must address the app's canonical page.

    This is the per-app assertion of `AboutContent.websiteMatchesSupportRepo`, a kit property that
    has existed since the About slots were fixed and that *nothing checked per app*: it is only
    reachable from a constructed `AboutContent`, so only clipmenu-2 and yahoo-keykey-2 asserted it,
    in their own test suites. The other three shipped the row on trust. Giving those three the
    signal is the whole point of the rule.

    The site convention is `dragonapp.com/{app-name}-{major}`, which is also the GitHub repo name
    for every Dragon app — so the Website row and the Support row check each other and there is no
    table to maintain. The checker reads the written literals out of the app's sources, the way
    §R13 reads the `languages:` argument, because the property cannot be evaluated without building
    the app.

    Anything it cannot read is a violation, never a skip: an unreadable argument, a support row
    that names no repository, no `AboutContent(` construction at all. A rule that goes quiet when
    an app restructures its About wiring would pass every app that stopped conforming, which is the
    silent-checker failure this spec exists to prevent (§R0, §R10 and §R13 all take the same line).

    dragon-sample-app is the one sanctioned divergence, declared in *its* repo under §R11: the site
    hosts `/dragon-sample-app/licenses/` and its appcast and nothing else, so the canonical path
    would be a 404 and the row addresses the studio hub instead.
    """
    out: list[Violation] = []
    constructed = False
    for path in files:
        body = "".join(read(path))
        masked = mask_noncode(body)
        constants = {match.group(1): literal_at(body, masked, match.end() - 1)
                     for match in URL_CONSTANT.finditer(masked)}
        for call in re.finditer(r"\bAboutContent\s*\(", masked):
            span = balanced(masked, call.end() - 1)
            if span is None:
                continue
            args_end = call.end() + len(span)
            constructed = True
            if cfg.excuses("R15", path):
                continue
            number = body.count("\n", 0, call.start()) + 1

            def resolve(label: str) -> str | None:
                where = about_argument(masked, call.end(), args_end, label)
                if where is None:
                    return None
                literal = URL_LITERAL.match(masked, *where)
                if literal:
                    return literal_at(body, masked, literal.end() - 1)
                return constants.get(masked[where[0]:where[1]].strip().rstrip("!").strip())

            website, support = resolve("websiteURL"), resolve("supportURL")
            if website is None or support is None:
                unreadable = " and ".join(
                    f"'{label}:'" for label, value in (("websiteURL", website),
                                                       ("supportURL", support)) if value is None)
                out.append(Violation("R15", f"cannot read {unreadable} — R15 compares the written "
                                     "literals, so each must be a URL(string: \"…\") at the call "
                                     "site or a 'let' assigned one in the same file", path, number))
                continue
            repo = github_repository(support)
            if repo is None:
                out.append(Violation("R15", f"supportURL is {support}, which names no "
                                     "github.com/owner/repo — the Website row is checked against "
                                     "the support row's repository, so there is nothing to compare "
                                     "it with", path, number))
                continue
            # The host was never checked at all, on either side of the comparison, so
            # `websiteURL: URL(string: "https://evil-example.com/ice-2/")!` passed this rule
            # silently — the path was all it read. Checked before the path so the message names
            # the actual defect rather than reporting a page mismatch on the wrong site.
            if not host_is(website, "dragonapp.com"):
                out.append(Violation("R15", f"About's Website row is on "
                                     f"'{urllib.parse.urlsplit(website).hostname or website}', not "
                                     f"the studio site — the canonical page is "
                                     f"https://www.dragonapp.com/{repo}/", path, number))
                continue
            page = urllib.parse.urlsplit(website).path.strip("/")
            if page != repo:
                out.append(Violation("R15", f"About's Website row addresses "
                                     f"'{page or '(the site root)'}' but the support row's "
                                     f"repository is '{repo}' — the canonical page is "
                                     f"https://www.dragonapp.com/{repo}/. If this app genuinely "
                                     f"has no page, sanction R15 in 'exceptions' with a reason and "
                                     f"an owner (§R11)", path, number))
    if not constructed and not cfg.excuses("R15", ""):
        out.append(Violation("R15", "no AboutContent(…) construction is reachable through "
                             f"'sources' ({cfg.sources}) — R15 reads the Website and Support rows "
                             "from the call site, and cannot report a pass on an About pane it "
                             "never found"))
    return out


# --------------------------------------------------------------------------- driver

def load_config(root: str, override: str | None = None) -> Config:
    # `--config` exists for diagnosing a repo without writing into it (e.g. taking a baseline
    # before the config is committed). CI never passes it, so R0 still applies there.
    path = override or os.path.join(root, ".dragon-conformance.json")
    if not os.path.exists(path):
        raise SystemExit("R0  .dragon-conformance.json is missing from the app repo root.\n"
                         "    See CONFORMANCE.md §R0. A missing config is a violation, not a "
                         "pass.")
    with open(path, encoding="utf-8") as handle:
        raw = json.load(handle)
    missing = [key for key in ("app", "sources") if key not in raw]
    if missing:
        raise SystemExit(f"R0  .dragon-conformance.json is missing required key(s): "
                         f"{', '.join(missing)}")
    return Config(app=raw["app"], sources=raw["sources"], strings=raw.get("strings", []),
                  pin=raw.get("pin", {}), pane_order=raw.get("paneOrder", {}),
                  traits=raw.get("traits", []), build_files=raw.get("buildFiles", []),
                  exceptions=raw.get("exceptions", []))


def main() -> int:
    parser = argparse.ArgumentParser(description="Check an app against CONFORMANCE.md")
    parser.add_argument("--app", required=True, help="path to the app repo")
    parser.add_argument("--kit", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))), help="path to a dragon-kit checkout")
    parser.add_argument("--config", default=None,
                        help="config path override, for diagnosing a repo without writing to it")
    args = parser.parse_args()

    root = os.path.abspath(args.app)
    kit = os.path.abspath(args.kit)
    cfg = load_config(root, args.config)
    files = swift_files(root, cfg.sources)
    if not files:
        print(f"R0  no Swift files under {cfg.sources} — check 'sources' in "
              f".dragon-conformance.json")
        return 1

    kit_types = kit_public_types(kit)
    languages = kit_languages(kit)
    violations: list[Violation] = []
    violations += rule_r1_r2_menu(root, cfg, files)
    violations += rule_r3_shadowed_types(root, cfg, files, kit_types)
    violations += rule_r4_design_primitives(root, cfg, files)
    violations += rule_r5_shared_panes(root, cfg, files)
    violations += rule_r6_r7_modules(root, cfg, files)
    violations += rule_r8_kit_strings(root, cfg)
    violations += rule_r9_pane_order(root, cfg)
    violations += rule_r10_pin(root, cfg, kit)
    violations += rule_r12_commit_date(root, cfg)
    violations += rule_r13_language_picker(root, cfg, files, languages)
    violations += rule_r14_about_copyright(root, cfg, files)
    violations += rule_r15_website_page(root, cfg, files)

    print(f"DragonKit conformance — {cfg.app} ({len(files)} Swift files, "
          f"{len(kit_types)} kit types, {len(languages)} kit languages)")
    # R11: exceptions are printed every run so they stay visible rather than becoming permanent.
    for exc in cfg.exceptions:
        print(f"  exception  {exc.get('rule')}  {exc.get('path', '(app-wide)')} — "
              f"{exc.get('reason', 'NO REASON GIVEN')}")

    if not violations:
        print("PASS — no violations.")
        return 0
    print(f"\nFAIL — {len(violations)} violation(s):")
    for violation in sorted(violations, key=lambda v: (v.rule, v.path, v.line)):
        print(violation.render(root))
    print("\nSee CONFORMANCE.md for the rule and the history behind it.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
