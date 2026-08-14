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
| [`plans/2026-06-30-dragon-kit-v0.md`](plans/2026-06-30-dragon-kit-v0.md) | **Why the What's New module exists** — "Post-plan addition — Task 11", added at the owner's request after review. Plus the v0 self-review notes and known risks. The remaining ~1,370 lines are an executable build checklist for a package that now exists. | nowhere (the ~40 unique lines) |
| [`specs/2026-07-03-dragon-kit-reference-app-design.md`](specs/2026-07-03-dragon-kit-reference-app-design.md) | The module-generalisation rationale — why Backup, Updates, Permissions and Uninstall became kit modules rather than sample-app code. | partly `../../README.md` |
| [`specs/2026-07-04-dragon-sample-app-real-app-design.md`](specs/2026-07-04-dragon-sample-app-real-app-design.md) | The Sample App extraction's locked decisions: display name, bundle id, cask token, and the build-number offset the extracted repo needed because its commit count restarted. | `docs/MAC-APP-RELEASE-LIFECYCLE.md` (the rule, not the values) |

## Open question for the owner

`plans/2026-06-30-dragon-kit-v0.md` is 1,412 lines — 26% of all Markdown in this repository — and is
an *executable* checklist: shell commands, complete file bodies, commit and publish steps, all under
a banner saying not to execute them. Its unique content is roughly 40 lines.

Two options, both defensible, neither taken yet:

- **(a) Leave it.** The banner is doing its job and disk is free. *(current state)*
- **(b) Reduce it to a decision record** — goal, locked file structure, Task 11's origin, the
  self-review notes, and the task titles without their bodies (~140 lines), with a note that the full
  text is recoverable from git history. Loses the ability to read the original task bodies without a
  `git show`.

Directory renamed from `docs/superpowers/` on 2026-08-15 — the old name described the tool that
produced the files rather than what they are. Relative links inside the files were unaffected: the
new path is the same depth.
