# Dragon docs audit — remaining work

**Status after PRs #68–#74 + skill/memory edits, re-verified 2026-08-13.**
**24 of 63 fixed · 39 open · 1 new regression.**

Full original detail: `~/git/dragon-kit/DOC-AUDIT-2026-08-12.md`. Numbering is unchanged from it.
Both files are **untracked scratch — not committed, not on any branch.**

dragon-kit `origin/main` is now **`4b391df`**. Line numbers below are against that; re-fetch first.

---

## ✅ Fixed — do not revisit (24)

**dragon-kit PRs #68–#74:** #8, #9 (ADOPT prompt now says *"compliant capability configuration,
not a sanctioned §R11 exception"*) · #12 (IMPLEMENT prompt now *"Do not create or retain an
in-tree…"*) · #26 (§R9's "under §R11" gone) · #37 (*PARTIALLY SUPERSEDED* banner) · #39 (*FULLY
SUPERSEDED — Implementation from this file is prohibited*) · #42 (appcast clause gone) · #58
(`CLAUDE.md` now "approved migration debt" + new `TechDebt.md`)

**liquid-glass skill:** #1 (raw `Form { Section }` gone; 33 `DragonForm`/`DragonKit` references
now) · #2 (*"do not build an app-local `AboutView`"*) · #3 (`/clipmenu-2/`) · #4 (dual-`©` gone) ·
#5 (`SPUStandardUpdaterController` gone) · #6 · #7 (`IceForm` gone) · #47

**memory:** #30, #31, #32, #35, #49, #52, #53, #54

---

## 🔴 NEW REGRESSION — introduced by PR #74

### R1 — `README.md` still defers what `CLAUDE.md` just retired
`~/git/dragon-kit/README.md:289-292` vs `~/git/dragon-kit/CLAUDE.md:173-175`

PR #74 retired the folder-backup deferral in `CLAUDE.md` — *"Backup unification is approved
migration debt. Every app's target is DragonKit's `BackupSettingsPane` + `DragonBackup`."*

`README.md` still says the opposite:

> *"Deferred, deliberately: a generalized **folder-based versioned backup** pane … Generalize it
> here only when a second app (KeyKey / ice-2) needs that same shape; until then `DragonBackup`
> stays UserDefaults-suite-only."*

Same defect class as the original #58, now inverted: the fix landed in one file of the pair. The
paragraph after it (*"That is not this deferral being reversed"*) compounds it.

---

## 🔥 Code — never touched by any PR (12)

Highest-value block. All are **reproducible false passes**: a rule the spec advertises that the
checker does not enforce. Each needs a triad — rule prose + `~/git/dragon-kit/Scripts/dragon-conformance.py`
+ `~/git/dragon-kit/Scripts/test_conformance.py`.

**Do #13 and #14 first.** Until the test harness can prove a branch fired, every other fix here
lands unverified.

| # | Sev | What |
|---|---|---|
| **13** | HIGH | `~/git/dragon-kit/Scripts/test_conformance.py:179-188` — `expect_violation` asserts only `rule not in out`, so it cannot prove the intended branch fired. **Seven targeted mutations left the whole suite green.** |
| **14** | HIGH | `~/git/dragon-kit/CONFORMANCE.md:74-79` says the pin pattern **"MUST anchor on dragon-kit"**; nothing enforces it — and `test_conformance.py:403` **asserts the false pass as expected behaviour**. |
| **11** | **CRITICAL** | §R15 validates neither host. `websiteURL: "https://evil-example.com/fixture-2/"` + `supportURL: "https://notgithub.com/…"` **passes silently.** Website host never checked; `endswith("github.com")` matches `notgithub.com`. **Also needs the kit fix** at `~/git/dragon-kit/Sources/DragonKit/About/AboutContent.swift:292`. |
| 15 | HIGH | §R13 sees only direct init syntax — `LanguagePicker.init()` and a `typealias` both pass; `/* LanguagePicker() */` is a false violation. |
| 16 | HIGH | §R14 misses `copyright: Self.notice` and a literal on the following line. |
| 17 | HIGH | §R1/§R2 are line-based substrings — `let marker = "DragonAppMenu"` satisfies §R1; a multi-line `NSMenuItem(` evades §R2. |
| 18 | HIGH | §R5 counts commented-out pane references (no comment stripping). |
| 19 | HIGH | Omitting `strings` disables §R8; omitting `paneOrder` disables §R9. |
| 20 | HIGH | §R11's own `reason`/`sanctionedBy` are never validated — and it now guards a live exception. |
| 21 | HIGH | §R12 checks for the key `DragonCommitDate`, not a commit date; an empty placeholder passes by design. |
| 22 | HIGH | §R6/§R7 are blacklists, not positive rules — `import LoginServiceKit` passes. |
| 23 | HIGH | `~/git/ice-2/Ice/Settings/SettingsPanes/IceBackupSettingsPane.swift:9-13` cites *"CONFORMANCE.md §R11"* but ice-2 declares **no `exceptions` key**. Needs its own PR in `~/git/ice-2`. |

---

## 📄 dragon-kit docs — still open (7)

| # | Sev | Where | What |
|---|---|---|---|
| **24** | HIGH | `~/git/dragon-kit/CONFORMANCE.md:83` | §R0 still says `exceptions` is *"the real value in all five apps: empty"*; §R11 says one is declared. |
| **25** | HIGH | `~/git/dragon-kit/CONFORMANCE.md:143` | §R4 still claims it flags `*GroupBox`; the checker deliberately excludes it. **OWNER DECISION** — narrow prose, or widen checker (needs a compliant path for a bordered box). |
| 40 | MED | `~/git/dragon-kit/CONFORMANCE.md:126` | §R3 prose omits **top-level**; the checker only matches column-0 declarations. |
| 41 | MED | `~/git/dragon-kit/CONFORMANCE.md:17` | Intro still says rules arrive *"by pinning the workflow at a major tag"*; `:44-48` requires `@main` and says `@v2` does not resolve. |
| 38 | HIGH | `~/git/dragon-kit/docs/STARTING-A-NEW-APP.md:831` | *"R10 excepted, because the scratch package pinned the kit by `path:`"* — not reproducible; §R10 rejects path pins and `rule_r10_pin` never calls `excuses()`. |
| 61 | LOW | `~/git/dragon-kit/docs/STARTING-A-NEW-APP.md:169` | "Five rules" over **six** bullets. |
| 45 | MED | `~/git/dragon-kit/.claude/skills/dragonkit-review/SKILL.md:55` | *"breaks four downstream apps"*; line 3 says five. |

---

## 🌐 Global instructions — untouched (4)

All in `~/.claude/CLAUDE.md`.

| # | Sev | What |
|---|---|---|
| **10** | **CRITICAL** | *"KeyKey … marketing page at `www.dragonapp.com/keykey/`"* — that is the redirect stub. **§R15 fails an app whose About row points there.** Canonical: `/yahoo-keykey-2/`. |
| 27 | MED | *"`docs/<app>/index.html` … (e.g. `clipmenu/`, `keykey/`)"* — both examples are stubs. |
| 43 | MED | clipmenu-2-premium *"No longer built, released, or updated"* vs `~/.claude/skills/dragon-mac-ops/SKILL.md:12` *"a Developer ID diagnostic"*. A dispatchable workflow still exists. |
| 44 | MED | Repo map omits **ice-2, spectacle-2 and dragon-sample-app** — covers 2 of 5 apps. |

---

## 🛠 Skills — still open (5)

| # | Sev | Where | What |
|---|---|---|---|
| 28 | HIGH | `~/.claude/skills/dragon-mac-ops/SKILL.md:104` **and** `~/.claude/skills/update-macos-appstore/SKILL.md` | Both route release work to a **`release` skill that does not exist**. |
| 29 | HIGH | `~/.claude/skills/dragon-mac-ops/SKILL.md:49-51` | Cites `Example/scripts/run.sh` as the build-number reference; `Example/` is untracked. Use `~/git/dragon-sample-app/scripts/run.sh`. |
| 46 | MED | `~/.claude/skills/dragonapp-site-optimize/SKILL.md:81` | Protects `docs/keykey/appcast.xml`, which does not exist. |
| 48 | MED | `~/.claude/skills/liquid-glass-macos/references/per-app-specs.md` | *Partly fixed* — feeds corrected, but **"Ice has no Uninstall pane" remains**; Ice constructs `UninstallSettingsPane`. |
| 60 | LOW | `~/.claude/skills/liquid-glass-macos/SKILL.md` | *"all three apps"* ×3; five apps exist. |

⚠ `~/.claude/skills/liquid-glass-macos/references/appkit-boundary.md` was **never examined by any
pass.** Its three siblings produced six CRITICALs. Read it.

---

## 🧠 Memory — still open (10)

All under `~/.claude/projects/-Users-teddychan-git-dragon-kit/memory/`.

| # | Sev | File | What |
|---|---|---|---|
| 33 | HIGH | `dragonkit-adoption-gaps.md` | Pins recorded as 1.5.0 / v1.3.0; all five are on **4.0.0**. |
| 34 | HIGH | `dragonkit-adoption-gaps.md` | *"`Example/` … CI builds it"* — untracked, not built, and §R10 now makes a `path` pin a violation. |
| 36 | HIGH | `dragonkit-app-propagation.md` | clipmenu MAS as *"open work"* with a separate `mas-v*` tag; resolved 2026-08-11. |
| 50 | MED | `dragonkit-adoption-gaps.md` | Released sample app as `sample-v1.0.3`; it is **v1.4.5**. |
| 51 | MED | `dragonkit-adoption-gaps.md` | ice-2 PR #56 flagged PENDING; merged. |
| 55 | MED | `build-number-git-commit-count.md` | Cites `Example/scripts/run.sh`. |
| 56 | MED | `dragonapp-site-canonical-app-urls.md` | *"a wrong link **now fails**"* since v3.0.0 — nothing checked it per app until §R15. |
| 57 | MED | `dragonkit-not-an-attribution.md` | Cites `sample-app` inside dragon-kit; it lives in `teddychan/dragon-sample-app`. |
| 62 | LOW | `dragonkit-adoption-gaps.md` | Opens *"all four dragon-kit consumers"*; later *"FIVE consumers"*. |
| 63 | LOW | `dragon-sample-app-release.md` | Latest tag `v1.4.2`; now **v1.4.5**. |

`dragonkit-adoption-gaps.md` carries 5 of these — consider rewriting it wholesale rather than
patching.

---

## Recommended order

1. **R1** — one-line regression; close it before it propagates.
2. **#13, #14** — test-harness integrity. Everything in the code block is unverifiable until then.
3. **#11** — the only open CRITICAL in code; needs the kit fix too.
4. **#10** — the only open CRITICAL in docs; it makes §R15 fail an app.
5. **#15–#22, #40** — remaining checker triads.
6. Docs / global / skills / memory batches, in any order.
7. **#23** — separate PR in `~/git/ice-2`.

## Owner decisions — not for an agent

- **#25** — §R4: narrow the prose, or widen the checker?
- **#23** — ice-2's comment: correct the citation, or declare the exception it claims?
