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
    # `SyncBackupPane`/`syncBackup` is clipmenu-2's own backup pane, sanctioned under §R11
    # (iCloud sync + versioned folder backup, because DragonBackup is UserDefaults-suite only).
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
    out: list[Violation] = []
    uses_kit_menu = False
    for path in files:
        for number, raw in enumerate(read(path), 1):
            line = strip_comment(raw)
            if "DragonAppMenu" in line:
                uses_kit_menu = True
            if "NSMenuItem(" not in line:
                continue
            if cfg.excuses("R1", path):
                continue
            if re.search(r"uninstall", line, re.IGNORECASE):
                out.append(Violation("R2", "menu item for Uninstall — it belongs in "
                                     "UninstallSettingsPane, not the dropdown", path, number))
                continue
            for pattern in LIFECYCLE_PATTERNS:
                if re.search(pattern, line):
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
    body = "".join("".join(read(path)) for path in files)
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
            if any(part in SKIP_DIRS for part in path.split(os.sep)):
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
    # A path dependency (the sample app lives inside dragon-kit) is current by construction —
    # there is no version to fall behind. Still requires the declaration, so it's a stated
    # fact rather than a silently skipped rule.
    if spec.get("kind") == "path":
        return []
    if not spec.get("file") or not spec.get("pattern"):
        return [Violation("R10", "config declares no 'pin' — cannot verify the DragonKit "
                          "version is current")]
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
                  traits=raw.get("traits", []), exceptions=raw.get("exceptions", []))


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
    violations: list[Violation] = []
    violations += rule_r1_r2_menu(root, cfg, files)
    violations += rule_r3_shadowed_types(root, cfg, files, kit_types)
    violations += rule_r4_design_primitives(root, cfg, files)
    violations += rule_r5_shared_panes(root, cfg, files)
    violations += rule_r6_r7_modules(root, cfg, files)
    violations += rule_r8_kit_strings(root, cfg)
    violations += rule_r9_pane_order(root, cfg)
    violations += rule_r10_pin(root, cfg, kit)

    print(f"DragonKit conformance — {cfg.app} ({len(files)} Swift files, "
          f"{len(kit_types)} kit types)")
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
