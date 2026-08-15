---
name: dragonkit-review
description: Code review changes in the dragon-kit repo — checks the DragonKit product split, public-API compatibility across the five consuming apps, localization and menu canon, and the conformance rule triad. Use for "review my changes", "code review", "is this ready to merge/PR", or before running `gh pr create` in dragon-kit. Defaults to the branch diff against main; pass "uncommitted" for the working tree, or a PR number/URL for PR mode.
allowed-tools: Read, Grep, Glob, Bash, ReportFindings
---

# DragonKit code review

Review only what a machine can't. The compiler, `swift test` and
`Scripts/dragon-conformance.py` already cover a large share of what a generic reviewer would
flag here — run them, and spend your attention on the rest.

Read [CLAUDE.md](../../../CLAUDE.md) first if it isn't already in context. This skill assumes
its rules.

## 1. Pick the diff

| Argument | Target |
|---|---|
| *(none)* | `git diff main...HEAD` — the branch, the default |
| `uncommitted` / `local` | `git diff HEAD` plus untracked files |
| a PR number or URL | `gh pr diff <n>` |

Get the file list, then read every changed file **in full** — not just the hunks. Most findings
below depend on what the file already contained.

If nothing changed, say so and stop.

## 2. Run the machines first

```bash
swift test
python3 Scripts/test_conformance.py
```

`swift test` includes the host-wiring suites, which are what a client app's build used to prove.
There is no app in this repository to point the checker at; if a rule changed, also run it against
a real app's clone: `python3 Scripts/dragon-conformance.py --app ~/git/dragon-sample-app --kit .`

If one fails, report the failure verbatim as the top finding and keep reviewing — don't
hand-analyze what the output already tells you. If you can't run them (no macOS 26 toolchain,
say), state that plainly rather than implying they passed.

## 3. The rubric

These are the axes worth a human's attention in this repo. Each one exists because it already
broke something.

**Product split.** Any `import Sparkle`, `SPUUpdater`, `SPUStandardUpdaterController`, or new
package dependency outside `Sources/DragonKitUpdates/`. The core must stay dependency-free —
clipmenu-2's sandboxed Mac App Store target links it alone and cannot carry Sparkle.

**Public API compatibility.** Diff the `public` surface. A removed or renamed symbol, a changed
signature, a new non-defaulted parameter on a public initializer, or a new protocol requirement
without a default breaks all five downstream apps and forces a major tag. Ask whether the change
could have been additive with a default instead. If it genuinely must break, the PR should say
so.

**Localization.** Key *parity* across the seven `.lproj` files is already covered by
`LocalizationTests.allLanguagesDefineTheSameKeys()` — don't re-check it. What's left to a human:
a new user-visible string literal that never goes through `L(_:)`; a key present in all seven
files but still holding the English text in the other six; and `%@` placeholders dropped,
duplicated or reordered by a translation, since the test compares key sets and never looks at
the values. Apps cannot patch any of this — the module bundle resolves first.

**Menu and pane canon.** Any change to `DragonAppMenu`'s order, titles, casing, ellipses or SF
Symbols; anything re-introducing Uninstall to the dropdown; any change to the canonical settings
pane order. These change every Dragon app's UI at once. A canon change that doesn't also update
`README.md`, `CONFORMANCE.md` and the tests is incomplete.

**Mirrored rules in the two prompt documents.** `docs/ADOPT-DRAGONKIT-PROMPT.md` and
`docs/IMPLEMENT-MAC-APP-RELEASE-LIFECYCLE-PROMPT.md` deliberately restate rules, because a prompt
is pasted where this repo is absent. Each carries a `<!-- MIRRORS: … -->` marker naming what it
mirrors. If the diff touches a mirrored rule and neither prompt changed, that is a finding — those
two files are the copies most likely to drift, and the least likely to be noticed.

**Conformance triad.** If any one of `CONFORMANCE.md`, `Scripts/dragon-conformance.py`,
`Scripts/test_conformance.py` changed, check the other two. A rule written but not implemented
is the exact failure the spec exists to prevent. Also check: does a new rule have a test? Is a
new regex anchored on `dragon-kit` (an unanchored one matches whichever dependency appears first
in the file — it matched Sparkle's version in ice-2's `.pbxproj`)? Does the rule stay
enforceable if the app deletes its `.dragon-conformance.json`? Does the new or changed rule have a
matching section in `docs/CONFORMANCE-INCIDENTS.md` — a rule with no recorded incident is either
undermotivated or is borrowing someone else's, and §R7 is the template for saying so honestly.

**Exception status.** Never infer conformance from an empty `exceptions` list, or from the absence
of a documented exception. The registry is what the apps declare; an empty one says only that no
divergence is sanctioned. Inspect current app source and run the current checker — and say *not
currently verified* rather than "conforming" when you have not. The checker validates an entry's
four fields (§R11) but **not that the rule would fire without it**, so for a declared entry,
reproduce the unsuppressed violation before treating it as load-bearing. A prose-only reservation
that was never app-declared is historical context, not a live or a resolved exception.

**Host wiring.** A new public pane, config or initializer that `Tests/*/HostWiringTests.swift`
doesn't construct is API nothing here compiles as a client. Those two suites replaced the in-tree
sample app's build, and they import the kit plainly — a diff that switches either to `@testable`,
or adds a shared pane without wiring it there, puts the five-app contract back on review alone.
The Mac App Store shape (`DragonKitTests`) must stay free of `DragonKitUpdates`.

**Concurrency.** `@MainActor` on new types touching AppKit or SwiftUI; Swift 6 strict-concurrency
correctness in anything crossing an isolation boundary.

**Rationale comments.** This repo's standard is that non-obvious decisions carry a comment
naming the app and the bug that forced them. New canon with no stated why is a real finding
here, even though it would be a nitpick anywhere else — undocumented canon is how the original
drift happened.

**Deferrals undone.** Flag a PR that quietly generalizes `DragonBackup` to folder-based backup,
re-adds Uninstall to the menu, pins the reusable conformance workflow to a tag, or removes a
*currently declared* §R11 exception without the verification above. Each of those is a deliberate
decision with a written reason.

Beyond this, apply ordinary judgment — real bugs, broken invariants, dead code the change
created.

## 4. Don't report these

- Anything `swift build`, `swift test`, or the conformance checker catches. Run them; don't
  duplicate them by eye.
- Pre-existing issues on lines the diff didn't touch.
- Nitpicks a senior engineer wouldn't raise: formatting, naming taste, import order.
- Missing app-side localizations. Out of scope by design — the rule is that localization *goes
  through* `L()`, not that every app ships seven languages.
- The untracked `sample-app/` directory. Stale build output (`.build/`, `Package.resolved`) left
  from when Dragon Sample App lived here; `.gitignore` names it. It is not an in-tree app.
- Missing test coverage or documentation in general, unless the change is to canon or to a
  conformance rule — where both are required.

## 5. Report

Rank by severity, most severe first. For each finding give: the file and line, one sentence on
the defect, and a concrete failure — which app breaks, what a user sees, or what silently stops
being enforced. A finding you can't state a failure for is a finding to drop.

Use `ReportFindings` if it's available; otherwise a short markdown list. In PR mode, ask before
posting a comment to the PR — don't post unprompted.

End with the machine-check results and an explicit verdict: ready to merge, or the specific
things to fix first.
