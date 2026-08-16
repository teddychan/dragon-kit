# Historical plans and specs

**Nothing in this directory is current. Implementation from these files is prohibited.** Each one
carries its own banner naming the documents that superseded it; those banners are accurate and were
checked against the current normative set.

They are kept because **a superseded document is the only place some decisions were ever written
down.** Deleting one does not simplify the doc set — it destroys the answer to a question that will
be asked again. The table below names what each file is the sole record of, so a future consolidation
knows what it would be throwing away.

Current authority is [`../../README.md`](../../README.md) → "For AI agents: current documentation
authority".

| File | Sole record of | Also lives in |
|---|---|---|
| [`specs/2026-06-30-dragon-kit-v0-template-design.md`](specs/2026-06-30-dragon-kit-v0-template-design.md) | **Why the platform floor is macOS 26** — §6.2: matches clipmenu-2's SDK, newest APIs without `@available` gating, and the accepted trade-off that apps below 26 cannot adopt the kit. Also §6.1 (SPM-based app template) and §6.3 (publish-after-green). | nowhere |
| [`specs/2026-08-08-about-pane-canon-design.md`](specs/2026-08-08-about-pane-canon-design.md) | **The rejected About alternatives** — a bundled Acknowledgements document rejected by the owner in favour of website-hosted licence pages (a licence trade-off the owner asked to be recorded rather than buried); KeyKey's data attributions staying in the pane; no `tagline` header slot. Also the measured screenshot evidence of the original five-pane drift. | nowhere |
| [`plans/2026-06-30-dragon-kit-v0.md`](plans/2026-06-30-dragon-kit-v0.md) | **Why the What's New module exists** — "Post-plan addition — Task 11", added at the owner's request after review. Plus the locked file structure, the per-task design notes (why the primitives are source-compatible ports, why `SettingsShell` takes a `Binding<String?>`, why the accessory-app window controller had to exist at all), and the v0 self-review notes and known risks. **Reduced to a decision record on 2026-08-16**; the executable checklist it used to carry is in git history. | nowhere |
| [`specs/2026-07-03-dragon-kit-reference-app-design.md`](specs/2026-07-03-dragon-kit-reference-app-design.md) | The module-generalisation rationale — why Backup, Updates, Permissions and Uninstall became kit modules rather than sample-app code. | partly `../../README.md` |
| [`specs/2026-07-04-dragon-sample-app-real-app-design.md`](specs/2026-07-04-dragon-sample-app-real-app-design.md) | The Sample App extraction's locked decisions: display name, bundle id, cask token, and the build-number offset the extracted repo needed because its commit count restarted. | `docs/MAC-APP-RELEASE-LIFECYCLE.md` (the rule, not the values) |

## The v0 plan was reduced, and what that cost

`plans/2026-06-30-dragon-kit-v0.md` was 1,412 lines — 26% of all Markdown in this repository — and
an *executable* checklist: shell commands, complete file bodies, commit and publish steps, all under
a banner saying not to execute them. On **2026-08-16** it was reduced to a decision record: goal,
architecture, locked file structure, every per-task design note, Task 11's origin, and the
self-review notes.

Two corrections worth recording, because the first estimate of what was unique was wrong:

- **Its unique content was not ~40 lines.** Six per-task rationale notes were missed by the survey
  that produced that figure, because they explain with "so" and "doesn't open cleanly" rather than
  with decision vocabulary. All six are kept. If you re-survey a document for unique content, grep
  for blockquotes, not for the word *rationale*.
- **One `Superseded 2026-08-06` note did not need keeping.** It recorded that Task 1's
  `DragonKit.ping` fixture and `SmokeTests.swift` were deleted and must not be reintroduced. That
  reason already lives at its enforcement site, on `resolvesKeyFromModuleBundle()` in
  [`Tests/DragonKitTests/LocalizationTests.swift`](../../Tests/DragonKitTests/LocalizationTests.swift),
  which is where the repo's conventions say it belongs. The record keeps a pointer, not a copy.

What it cost: reading an original task body now needs a `git show`. The banner names the blob and
the command.

This directory keeps the name `docs/superpowers/`. It was briefly renamed to `docs/history/` on
the grounds that the old name described a tool rather than a purpose — and reverted, because
`clipmenu-2`, `ice-2`, `spectacle-2`, `yahoo-keykey-2` and `www.dragonapp.com` all use
`docs/superpowers/` for exactly this, and the files themselves open with
`REQUIRED SUB-SKILL: Use superpowers:executing-plans`. The name is accurate provenance, and one
repo differing from five is worse than either consistent state.
