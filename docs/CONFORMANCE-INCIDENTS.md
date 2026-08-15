# Conformance incidents

The record behind [`CONFORMANCE.md`](../CONFORMANCE.md). Every rule there is a failure that
actually happened; this is where each failure is written down, one section per rule.

**This file is not normative.** It changes no rule and suppresses nothing. Read it when you want
to know *why* a rule is shaped the way it is, when you are tempted to relax one, or before writing
a new one — most of the mistakes below are mistakes about rule design, not about apps.

Two conventions it exists to serve:

- **Comments explain why, and cite the incident.** A piece of canon with no stated rationale
  drifts back out. That is [`CLAUDE.md`](../CLAUDE.md)'s standard for code and it applies to rules
  too — but the rationale does not have to sit between a reader and the rule.
- **A broken checker is worse than no checker**, because it passes everything silently. Several
  sections below are records of the checker being wrong, not an app being wrong. Those are the
  expensive ones.

A note on dates. Statements here describe **what was true when the incident was recorded**. They
are evidence, not current fleet state. To learn whether an app conforms today, run the checker
against current source — see [`CONFORMANCE.md`](../CONFORMANCE.md) §R11 on why an undeclared
exception is not evidence of anything.

---

## Why the spec exists at all

Before 2026-08-04 all four shipping apps had independently hand-rolled the same lifecycle menu and
drifted: three different string sets, two casings, two update icons, a stray ellipsis, and one app
with no icons. ice-2 had `IceForm`/`IceSection` files that were line-for-line identical to
`DragonForm`/`DragonSection`, plus its own Sparkle wiring — so it silently missed a shared alert
reword. clipmenu-2 and keykey-2 each duplicated the kit's menu strings in their own `.strings`
files, which is how the casing drifted invisibly.

**Documentation did not prevent any of it. The design spec even *mandated* the drifted item.**

That last sentence is the reason these rules are machine-checked rather than review-enforced, and
the reason a rule, its implementation in `Scripts/dragon-conformance.py`, and its test in
`Scripts/test_conformance.py` move as one triad.

---

## §R0 — Declare the app

**A missing config had to be a violation**, or deleting `.dragon-conformance.json` would be the
easiest way to "pass".

**`sources`, `strings` and `paneOrder` are required for the same reason, one level down.** A
missing key used to switch its rule off without a word:

- omitting `strings` disabled §R8 outright — the rule had nothing to iterate and the app passed by
  giving the checker no work to do. §R13 reads the same globs to learn which languages an app
  ships, so one missing key quietly narrowed two rules at once.
- omitting `paneOrder` meant no §R9 at all, silently.

**The schema listing shows an empty `exceptions` array on purpose.** An earlier version showed a
worked example, and it read as a live sanction: the last one named a rule R3 never fired on and a
path (`SyncBackupPane.swift`) clipmenu-2 does not have. The schema is the starting point for a new
app, never a statement about the fleet.

**The listing is annotated JSONC and the real file is strict JSON.** The checker parses it with
`json.load`, so a `//` line does not document the file — it raises `JSONDecodeError` before a
single rule is evaluated. [`STARTING-A-NEW-APP.md`](STARTING-A-NEW-APP.md) carries the copyable
version.

## §R1 — The lifecycle menu comes from `DragonAppMenu`

**This is the drift that motivated the whole spec.** Order, naming, casing, ellipsis, icons and the
omission rules (`onCheckForUpdates: nil` for Mac App Store, `includeQuit: false` for an IME) are
canon, not per-app choices.

**Both halves of the rule read the code, not the line.** `"DragonAppMenu" in line` counted the name
wherever it appeared, so `let marker = "DragonAppMenu"` — or the name in a comment — satisfied this
rule for an app that never called it. And an `NSMenuItem(` whose title sat on the *next* line
matched nothing, which is the spelling every one of these takes once it has four arguments.

The call's arguments are now read as a whole, from a copy that keeps **literals but not comments**.
Reading them from raw text was the first cut and was wrong in this rule's own terms: it made
`NSMenuItem(title: title,  // Quit and About %@ come from DragonAppMenu)` a violation, which the
line-based predecessor would never have reported.

**KeyKey's IMK adapter is not a violation and not an exception.** IMK routes top-level selections
back to the input controller rather than honoring a closure-backed item's private target, so KeyKey
obtains the canonical `NSMenuItem`s from `DragonAppMenu.items(_:)` and retargets them to `@objc`
selectors on `InputController`. It hand-builds no lifecycle item; DragonKit still supplies each
item's title, icon, order and omission behavior.

## §R2 — Uninstall is not in the menu

A rarely-used destructive action does not belong one click away in the everyday menu, next to Quit.

**§R2 reads its own `exceptions` key, and did not always.** It was gated on §R1's, so an app needing
an Uninstall exception had to declare `R1` — which also switched off every lifecycle-title check on
that path — while §R11 told it `R2` was not suppressible at all. Both statements were wrong in the
way that mattered. Sanctioning `R2` now suppresses `R2` and nothing else.

## §R3 — No app type may shadow a public DragonKit type

**ice-2 declared its own `UpdatesSettingsPane` and `BackupSettingsPane` in files that also
`import DragonKit`.** It compiled — Swift resolves the local type — so the app silently used its own
copy while looking like it used the kit's. Name collision is the most dangerous drift because it is
invisible.

**Top-level on both sides is the rule, not a limitation of the checker.** A nested type lives in its
own namespace and cannot shadow anything: ice-2's `SettingsBackup.BackupError` was reported against
`DragonBackup.BackupError` and was a false positive. Scraping nested kit types is also what forced
`Config` and `Kind` onto a hand-maintained exclusion list — a symptom of the same bug rather than
real exceptions.

## §R4 — No re-implemented design primitives

The incident is short enough to live in the rule itself, and does: the kit was ported *from* ice-2's
own `IceForm`/`IceSection`, and ice-2 then kept its copy, so two line-for-line identical
implementations shipped and only one received fixes.

**§R4's prose is currently broader than its enforcement, on two axes, and the owner has parked the
decision.** The facts are in [`TechDebt.md`](../TechDebt.md); do not act on them without the owner,
and do not narrow or widen this rule while fixing something adjacent. That parking is also why
§R4's wording in `CONFORMANCE.md` should be left exactly as it is — including its Rationale line,
which is the only rule text here that was ever restated rather than relocated, and was restored.

## §R5 — Shared panes come from the kit

Every pane an app writes itself is a pane that stops receiving shared fixes. ice-2's own updates
pane meant it never got the reworded "up to date" alert.

**The reference has to be in code.** This searched raw text, so a line a migration left behind —
`// AnySettingsPane(UninstallSettingsPane(config: config))` — counted as wiring the kit's pane. It
was the one rule where prose *about* the kit was accepted as use of the kit.

## §R6 and §R7 — why both are deny-lists

**Neither has a positive form, deliberately.** "The app must reference `DragonUpdater`" fails an app
with the `mac-app-store` trait, which links no updater at all; "the app must reference `LoginItem`"
fails any app that simply has no launch-at-login feature.

What a deny-list costs is that it only knows the routes written into it, and §R7 knew exactly two:
`import LoginServiceKit` — the login-item library ClipMenu's upstream used — went straight past it.

**Third-party names are matched on `import` or a member access, never bare**, so that *naming* a
library stays distinguishable from *using* one: an entry in an `attributions` array, a test
asserting this rule, a variable name.

**That last part is defensive, with no incident behind it** — and this paragraph used to claim one.
It said ice-2 credits `LaunchAtLogin` in its generated acknowledgements. It does the opposite:
`IceTests/AcknowledgementsTests.swift` asserts the bundled notices do *not* name it, the dependency
having been dropped long ago, and the single mention anywhere in ice-2's `sources` is a `//` comment
that never reaches this rule. Verified at the time by widening the pattern to bare words and
re-running: ice-2 passed either way.

Worth keeping as written. A rule that cannot cite an incident should say so rather than borrow one.

## §R8 — The app owns no kit string keys

clipmenu-2 and keykey-2 both duplicated the kit's canonical menu titles across their own locale
files, which is exactly how the casing drifted without anyone noticing.

Note that `L()` resolves the module bundle **first**, so an app cannot override a kit key even if it
tries — a duplicated key is dead weight that merely *looks* authoritative.

## §R9 — Settings pane order matches the canon

**The canon line used to read "Sync & Backup"** — clipmenu-2's name for it — while the kit's own
pane is titled "Backup & Restore" and the checker's slot spellings recognized only
`BackupSettingsPane`/`backup`. So the one app whose pane is named differently had this slot
**silently unchecked**: `\bbackup\b` doesn't match `SyncBackupPane`, R9 compares only the slots it
actually saw, and clipmenu-2 passed with its backup pane free to sit anywhere in the order. Three
names for one slot, and the gap was in the app the rule most needed to cover.

`IceBackupSettingsPane` was added to the slot list later, on the same reasoning: `README.md` and
`TechDebt.md` both stated the rule recognized it while the slot did not name it. Nothing failed,
because ice-2 drives its sidebar from an enum whose `case backup` matches — but that made the hole
one refactor away from live. **A rule that happens to be satisfied by an unrelated detail of one
app's spelling is not a rule that is checking that app.**

Both spellings are migration debt, not a supported difference; they go when clipmenu-2 and ice-2
migrate to `BackupSettingsPane` + `DragonBackup`. See [`TechDebt.md`](../TechDebt.md).

## §R10 — The DragonKit pin is current

**A stale pin is how an app silently misses shared fixes.** Every app sat on 1.3.0 while the kit was
at 1.4.0, so none had the shared menu at all.

**The unanchored-pattern trap.** `pin.pattern` is one search over the whole file, so a version regex
that does not name dragon-kit matches whichever dependency appears first. `minimumVersion =
([0-9.]+)` read **Sparkle's 2.5.2** out of ice-2's `.pbxproj` and compared *that* against the kit's
tags — a false PASS on a stale pin, which is worse than a false failure because it looks like the
rule is protecting you.

§R0 required the anchor from the moment the trap was found, and **nothing enforced it** until the
checker started reading the pattern itself. The anchor is tested on the pattern with its separators
removed, so yahoo-keykey-2's `DRAGONKIT_TAG="v([0-9.]+)"` satisfies it exactly as
`dragon-kit", from: "([0-9.]+)"` does.

**`test_conformance.py` used to assert that false PASS as *expected behaviour*** — an `expect_pass`
named "the trap" — for the most-cited incident in this document. That is the sharpest available
illustration of why a rule and its test move together: the test was not silent about the hole, it
was defending it.

**`"pin": {"kind": "path"}` used to satisfy this rule by construction**, for the one app that
depended on the kit by `path: ".."` because it lived inside it. That app owns its own repository
now, so nothing qualifies — and the branch was an always-pass with no fixture behind it, which made
it the cheapest way for any app to opt out of the staleness check. Declaring it is now itself an
R10 violation, the same way §R0 makes deleting `.dragon-conformance.json` one.

## §R11 — Exceptions are explicit, reasoned, and few

### The five phantom sanctions

This section's table once listed five "currently sanctioned" exceptions, for months, while **not one
of them was declared in any app** — the checker printed nothing on every run of all five. None was
ever needed:

| Was listed | Why it needed no exception |
|---|---|
| clipmenu-2, ice-2 — R3/R4, own folder backup pane | `SyncBackupPane` and `IceBackupSettingsPane` shadow no kit type and hand-roll no grouped `Form`, so R3 and R4 never fired on them. The deferral is real — `DragonBackup` snapshots a UserDefaults suite only — but §R9 carries it, by listing the app's spelling in the Backup slot. |
| clipmenu-2 — R6, MAS links `DragonKit` only | R6 fires on `import Sparkle` in Swift sources. A *target* that omits a product gives it nothing to see. Declared as the `mac-app-store` trait. |
| yahoo-keykey-2 — R1, `includeQuit: false` | A parameter of `DragonAppMenu.Config`. Using the kit's own knob is compliance, not divergence. |
| yahoo-keykey-2 — R5, no Permissions pane | Carried by the `no-permissions` **trait**, which R5 reads directly. |

**A row naming a rule the checker never fires is worse than no row:** it reads as a live sanction,
nothing contradicts it, and the next app copies the shape. Traits and slot spellings are how a
*structural* difference gets declared; `exceptions` is only for a rule that genuinely fires and is
genuinely allowed to. If a row cannot be traced to a violation the checker would otherwise print, it
does not belong in the registry.

Validating the `rule` field is this history made machine-checkable.

### ice-2's R13 row — the same mistake, a second time

A reserved R13 row sat in this section from the day R13 landed. ice-2 shipped no localization at all
at that point — no `.lproj`, no String Catalog, no `L()` call site — so nothing on disk stated its
coverage, and the sanction was written down in advance so it would already be agreed when the app
adopted a picker.

It never appeared in ice-2's `.dragon-conformance.json`, so it never suppressed a violation — which
makes it historical context rather than a *resolved* exception; there was nothing to resolve. R13 is
silent for an app that constructs no `LanguagePicker`, so for the whole time it was listed there was
no violation for it to sanction. ice-2's `strings` glob matched no files either, so R8 had nothing
to read as well: **both rules passed that app by doing no work.** The fix was in the app — point the
glob at real locale files, ship them — not here.

ice-2 PR #102 shipped all seven locales and a bare `LanguagePicker()`, which is what R13 asks of an
app whose coverage matches the kit's.

Worth recording because it is the second time this section made the same point: a reserved row is
still a row that reads as a live sanction to the next person.

### `reason`, `sanctionedBy` and `path`

`reason` and `sanctionedBy` were required in prose and checked nowhere, so an entry with neither
suppressed its rule just as effectively while the run printed `NO REASON GIVEN` beside it and
passed.

`path` is validated for exactly the same reason, one field along. §R5, §R8, §R9 and §R12 consult
`excuses(rule, "")` and nothing else, so a path-scoped entry for one of them printed as a live,
narrowly-scoped sanction on every run and suppressed nothing at all — the app still failed.

**§R15 does take a path, and the only live exception in the fleet is one.** That rule is consulted
both ways — per construction site and once for the whole app — so a path there scopes a real
suppression. Worth stating explicitly, because a reader who has just absorbed "a path-scoped entry
suppressed nothing" can look at the one declared exception, see that it carries a `path`, and
conclude it is another phantom. It is not.

### dragon-sample-app's §R15 exception

**dragon-sample-app has no public-facing page, on purpose.** The site's only page for it is
`/dragon-sample-app/licenses/`: there is no `docs/dragon-sample-app/index.html` and no card for it
on the hub. The app exists to exercise DragonKit's modules — it ships no feature of its own — so it
is a released, updatable, licence-carrying app without a product page. Pointing its Website row at
the canonical path would ship a 404, so it addresses the studio hub, and
`AboutContent.websiteMatchesSupportRepo` is `false` for it.

**A sample or reference app is not a special case.** That entry is an exception on exactly the same
terms as a production app's would be: an applicable rule genuinely fires, and the app declares it.

**It lifts when the app gets a public page, if it ever does.** §R11's whole argument is that an
exception must not become permanent, so the one that exists needs a written condition under which
it ends — and this is it. If a `docs/dragon-sample-app/index.html` and a hub card are ever
published, the Website row moves to the canonical path, `websiteMatchesSupportRepo` becomes `true`,
and the entry is deleted from the app's config.

**The exception landed in dragon-sample-app's repository before §R15 landed here.** A rule merged
here is live in five apps' CI the same day, so merging in the other order would have red-X'd the app
for a divergence already agreed. In between it was inert — the checker matches exceptions by rule
name, so it only added a printed line — which is what made landing it first safe. That ordering is
the pattern to reuse for any future rule that a known app will not satisfy.

## §R12 — The build stamps `DragonCommitDate`

About renders `v2.4.1 (756) · 2026-Aug-07 16:54:20 UTC`. The count came from the commit; the
timestamp came from the **executable's modification date** — when CI linked and signed the binary.
The two halves described different things and drifted: rebuild the same commit tomorrow and the
count holds while the date moves.

`DragonAbout` now reads `DragonCommitDate`, so the line fingerprints one commit. It shows no date at
all when the key is absent — a silent fallback to the old meaning is exactly the drift this replaced
— which is why *not* stamping it has to be a violation rather than a quietly shorter version line.

**The rule used to accept the key appearing *anywhere* in the build surface**, so
`# TODO: stamp DragonCommitDate` satisfied it while nothing wrote the key — and two of the five apps
carried exactly such a comment, next to the real stamp that was doing the work.

An empty `<key>DragonCommitDate</key>` placeholder is still accepted deliberately: ice-2 ships one
and its release workflow fills it, which is a stamping route rather than a note about one.

**The recognized spellings are a whitelist, and saying so is the point.** Listing them descriptively
while rejecting everything else would be a rule documented more broadly than it is enforced, which
is the failure this whole document exists to prevent.

## §R13 — The language picker offers exactly the languages the app ships

**yahoo-keykey-2 shipped through v2.11.4 calling `LanguagePicker()` bare** while shipping only
`App/en.lproj` and `App/zh-Hant.lproj`, so its Settings offered Español, Français, 日本語, 한국어 and
简体中文 — and choosing one translated the kit's four panes while every KeyKey string fell back to
English. Fixed in yahoo-keykey-2 PR #103 as `LanguagePicker(languages: [.en, .zhHant])`.

ice-2 hit the same default first: its PR #83 added Simplified Chinese alone, and the contributor
hand-rolled a three-option picker in `GeneralSettingsPane` — the re-implementation §R4 forbids.

DragonKit 3.4.0 added the `languages:` parameter for exactly this — **and the parameter existing did
not stop it happening again.** Nothing failed on keykey's picker; it was found by eye while
verifying an unrelated pin bump, which is the definition of a rule that needs machine-checking.

**Why equality, in both directions.** The picker is the app's own statement of its coverage.
Offering more than it ships is the shipping bug above; shipping more than it offers is translation
work no user can select. A `.lproj` `DragonLanguage` has no case for is not counted — `Base.lproj`
is not a language, and a `de.lproj` is one the picker physically cannot list, so counting either
would leave the rule with no satisfiable form. The direction that matters is untouched: a locale the
kit lacks can never enter the offered list either.

**Why it reads the written argument rather than asserting through the type.**
`LanguagePicker.languages` is `private` and `offeredLanguages` is `internal`, so a constructed
picker reveals nothing to an app-side test. yahoo-keykey-2's
`ConfigContentTests.testLanguagePickerOffersExactlyTheShippedLocalizations` is the app-local version
of this comparison; this rule is what gives the other four apps the same signal.

A call inside `/* … */` used to be a false violation with no compliant fix but deleting the comment,
because only `//` was stripped.

## §R14 — The About copyright is kit-assembled and names one holder

**The dual-holder line** (`© 2008–2014 Naotaka Morimoto · © 2026 Teddy Chan`) **was in two of five
apps and not the other three.**

`copyright` is a plain `String`, so no signature can close it — which is exactly why it gets a rule.
The rest of the About pane's slots are closed by the kit's own signature and need none: `licensesURL`
is a required parameter, and the upstream project's repository lives *inside* `OriginalWork`, so the
`Original project` link and the `Based on` credit are one value. Both were separate optionals, and
all four combinations shipped — clipmenu-2 and ice-2 credited an upstream project the pane never
linked, while spectacle-2 and the sample app listed `Sparkle → MIT` in Credits with no notices page
anywhere. Found by putting five screenshots side by side, which is how About drift has been found
every time. Under 4.0.0 each of those is a compile error, caught by the app's own build.

**The rule was checked in the wrong shape first.** It was a same-line search for `copyright: "`,
which is a test of the one spelling nobody was going to use: `copyright: Self.notice` passed, and so
did a literal wrapped onto the following line, which is how the slot reads as soon as the argument
list is long enough to wrap.

### The reasoning that was wrong, and must not be reinstated

An earlier draft of this rule argued that a Dragon app reimplements its upstream rather than reusing
its source, and therefore has no upstream copyright to assert.

That is true of yahoo-keykey-2, which had reasoned its way to the single-holder form on exactly
those grounds — and **false of the two apps the rule actually touched.** ice-2 is a **git fork** of
Jordan Baird's Ice, 1371 commits from its `Initial commit`, GPL-3.0, and GPL §4 requires the
upstream notice to travel with a derivative work; clipmenu-2's own `LICENSE` names both Naotaka
Morimoto and Teddy Chan.

Generalising from one app's situation to a legal claim about all five was wrong, and it was caught
by an agent that refused the instruction and went and read the licences. **Do not reinstate that
reasoning.**

So the reason is narrower and holds regardless of lineage: **the About header is a presentation slot
in a settings pane, and it read one way in three apps and another in two.**

**Do not let this rule near a legal notice.** The upstream copyright is carried where it legally
belongs — the `LICENSE` file and the licences page — neither of which this rule touches. ice-2's
`LICENSE` fills in the GPL's own notice template with Jordan Baird's name and year, and its
`Acknowledgements.rtf` states the fork inherits GPL-3.0; clipmenu-2's `LICENSE` names Naotaka
Morimoto and Teddy Chan. Lineage in the pane is `OriginalWork`'s job, twice over: the
`Original project` link and the `Based on` credit.

### `NSHumanReadableCopyright` is not where GPL §4 is satisfied

This document used to cite ice-2's dual-holder value as the example of an upstream notice travelling
correctly outside the pane. ice-2 changed it in 2.14.7 and the reasoning is worth keeping: the key is
an *optional* Apple one that no licence names — three of the five apps shipped without it at all —
so it draws a line in Finder's Get Info panel rather than discharging an obligation, and having it
disagree with About made the app state two different things about itself depending on where you
looked.

The kit neither reads nor requires it, and §R14 does not check it. Setting it to the same
single-holder string About renders is a **convention, not a rule**. If the five ever diverge there,
that is a second presentation slot drifting, not a licence question.

## §R15 — About's Website row addresses the app's canonical page

**Nothing checked this per app.** clipmenu-2 and yahoo-keykey-2 assert it in their own test suites;
spectacle-2, ice-2 and dragon-sample-app shipped the row on trust, and giving those three the signal
is the point of the rule.

The failure it catches is silent by construction — a wrong Website row still resolves in a browser.
`dragonapp.com/clipmenu/` is a `<meta refresh>` stub whose `rel=canonical` points at `/clipmenu-2/`;
it opens fine, and only this comparison distinguishes it from the page the app actually has.

**The host half was missing from the rule as it first shipped**, and from
`AboutContent.websiteMatchesSupportRepo` — the kit property §R15 exists to assert per app — so the
two had the same hole and would have re-split if only one were fixed. Only the *path* was compared,
which `https://evil-example.com/ice-2/` satisfies as readily as the real page; and a bare
`hasSuffix("github.com")` is true of **`notgithub.com`**, which yielded an owner and a repo for the
comparison to agree with. Both are now matched on the label boundary, so `www.` is a subdomain and
`notgithub` is a different registrable name.

**§R15 already had three negative controls when this was found.** All three tested wrong *paths*,
none tested a wrong *host*, and the gap sat open underneath them. A rule's tests can be numerous and
still all point the same direction.

**Why it reads written literals.** The property is only reachable from a *constructed*
`AboutContent`, and constructing one means building the app. It follows one hop of indirection:
clipmenu-2 and ice-2 both name their URLs in a `let` before passing them, and a rule that only
understood a literal at the call site would read nothing at all for two of the five apps.

---

## Before you write rule R16

Seven failure modes, each already shipped here at least once. This is an index, not a summary —
follow the link for the case.

1. A rule with nothing to iterate passes → [§R0](#r0--declare-the-app), [§R13](#r13--the-language-picker-offers-exactly-the-languages-the-app-ships)
2. A rule that reads text rather than code reads comments → [§R1](#r1--the-lifecycle-menu-comes-from-dragonappmenu), [§R5](#r5--shared-panes-come-from-the-kit)
3. An unanchored pattern matches the wrong dependency, silently → [§R10](#r10--the-dragonkit-pin-is-current)
4. An indirection the rule cannot follow must be a violation, not a skip → [§R15](#r15--abouts-website-row-addresses-the-apps-canonical-page)
5. A documented reservation is not an exception → [§R11](#ice-2s-r13-row--the-same-mistake-a-second-time)
6. The test can defend the bug → [§R10](#r10--the-dragonkit-pin-is-current)
7. A rule with no incident behind it should say so rather than borrow one → [§R7](#r6-and-r7--why-both-are-deny-lists)

And the one that is not about rules at all: **what finds About drift is five screenshots side by
side.** Prefer closing a gap in the *signature* — a required parameter, two fields folded into one
type — over writing an eighth rule. The kit's tests pin what the kit assembles; they cannot see
that two apps left an optional slot nil.
