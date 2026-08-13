# Documentation rule-conflict changelog

**Review checkpoint:** 2026-08-13

**Scope:** documentation only; no source-code or API-support claim

This records owner-approved resolutions from the documentation conflict audit. Entries 1–4 cover
shared UI ownership; entry 5 records the app-repository and release-ownership boundary. It is
intentionally separate from the normative rules so a reviewer can evaluate what changed, why it
changed, and whether the ownership boundary is correct.

## Decision summary

| Priority | Conflict | Resolution | Why |
|---:|---|---|---|
| 1 | Liquid Glass described app-local Settings assembly while DragonKit requires shared Settings primitives. | Liquid Glass owns appearance; DragonKit owns the shared window, shell, pane structure, primitives, and canonical order. | It preserves the visual language without allowing every app to recreate shared structure. |
| 2 | Liquid Glass allowed a free-form About view while DragonKit 4 uses fixed slots. | Use `AboutContent` with `AboutSettingsPane`; DragonKit fixes labels, icons, URL details, order, version format, and the Built-with row. | Typed app content remains flexible while cross-app layout and wording cannot drift. |
| 3 | Liquid Glass required a separate uninstall sheet/window and `NSAlert` button rules while DragonKit presents confirmation inline. | DragonKit owns inline presentation. Apps supply cleanup paths, optional-data configuration, and truthful app-specific explanation. | One confirmation UI serves every app without pretending that every app performs the same cleanup. |
| 4 | The adoption prompt treated every Dragon app as an `NSStatusItem` menu-bar app and described Yahoo! KeyKey differences as exceptions. | Distinguish `NSStatusItem` and Input Method Kit hosts while retaining the same DragonKit Settings UI. KeyKey uses no Quit, launch-at-login, or Permissions pane; its input settings and uninstall backend remain app-specific. | Host lifecycle and backend behavior differ, but that does not require a different Settings design system. |
| 5 | The lifecycle implementation prompt allowed an in-tree Sample App fixture even though the accepted lifecycle requires a separate app repository. | Prohibit any in-tree consuming app or app-release infrastructure; make each app repository the sole owner of its complete release surface. | One app copy and one release owner prevent source drift, competing tag namespaces, and split ownership of builds, releases, artifacts, appcasts, downloads, and operations. |

## 1. Liquid Glass appearance vs DragonKit structure

![Liquid Glass appearance guidance compared with DragonKit structural ownership](images/doc-rule-conflicts/liquid-glass-vs-dragonkit.png)

The two sides may look similar by design. The change is who controls the reusable structure:
orange is app-assembled; blue is DragonKit-assembled. Apps still supply their own labels, values,
settings state, and domain behavior.

## 2. Free-form About vs fixed-slot About

![Free-form About assembly compared with DragonKit fixed slots](images/doc-rule-conflicts/about-freeform-vs-canon.png)

The fixed-slot model makes row names, symbols, order, canonical URL details, version presentation,
and the DragonKit credit consistent. Apps retain the icon, name, URLs, holder, licence, original
work, and attribution values.

## 3. Separate uninstall sheet vs inline confirmation

![A separate uninstall sheet compared with DragonKit inline confirmation](images/doc-rule-conflicts/uninstall-inline-vs-sheet.png)

The useful behavioral requirements remain: an explicit removal checklist, an optional user-data
toggle off by default, safe cancellation, visible failures, and an honest explanation of what
macOS controls. Only the competing sheet/window/`NSAlert` presentation rules were removed. The
image illustrates presentation only; it does not establish custom cleanup hooks or runtime behavior.

## 4. Yahoo! KeyKey uses the same Settings UI, not the same lifecycle

![Yahoo! KeyKey 2 Settings window](images/doc-rule-conflicts/yahoo-keykey-settings.png)

This screenshot demonstrates Settings information architecture only; it does not evidence menu
hosting, Quit behavior, launch behavior, or uninstall implementation.

| Shared with other Dragon apps | Specific to Yahoo! KeyKey |
|---|---|
| `DragonSettingsWindowController`, `SettingsShell`, shared pane UI, design primitives, and relative sidebar order | Input-method preferences and help content |
| About, Backup & Restore, What's New, Updates, and inline Uninstall presentation | IMK `menu()` host instead of `NSStatusItem` |
| DragonKit lifecycle-menu labels and ordering where an item applies | `includeQuit: false`; macOS manages the IME lifecycle |
| Trait-driven omission of inapplicable panes | `no-permissions`; no launch-at-login; TIS-aware uninstall outcome |

The resulting KeyKey order is **General → KeyKey-owned panes → Backup & Restore → What's New →
Updates → About → Uninstall**. Omitting Permissions and Quit is supported host/capability topology,
not an R11 exception and not permission to hand-roll the remaining shared UI. KeyKey must perform
TIS/input-source deregistration and IME-specific cleanup while retaining the shared inline
presentation, but the supported integration point must be verified before implementation; this
ownership decision does not establish a custom-operation hook.

## 5. Lifecycle repository and release ownership

The previous README path could send an agent from the accepted separate-repository lifecycle to a
prompt that still permitted retaining an in-tree app fixture:

![Previous conflicting lifecycle reader path and ownership](images/doc-rule-conflicts/release-lifecycle-before.png)

The corrected path makes the accepted lifecycle the canonical entry point, requires separate
repository checkouts, and gives each app repository sole ownership of its source, packaging,
workflows, signing/notarization configuration, releases, artifacts, production appcast,
app-side website/download integration, and operational state:

![Current lifecycle reader path and repository ownership](images/doc-rule-conflicts/release-lifecycle-after.png)

DragonKit owns shared package code, lifecycle and conformance contracts, guidance, and reusable
release conventions. Shared automation may execute steps without becoming a release owner, while
the marketing-site repository consumes successful releases without owning or gating them. This
documentation decision does not claim that any external app repository has completed the
migration.

## Independent-review corrections

Before publication of entries 1–4, an independent documentation-only review returned **REVISE
BEFORE CONTINUING**. That review included the resulting corrections:

- replaced remaining blanket “menu-bar app” language with explicit `NSStatusItem` and IMK hosts;
- made `DragonAppMenu` responsible for applicable lifecycle items rather than asserting every host
  has the same menu;
- limited shared uninstall guidance to presentation invariants and left cleanup targets/order to
  each app;
- marked KeyKey's TIS cleanup integration point as requiring verification instead of promising an
  undocumented custom-operation hook;
- limited the KeyKey screenshot to evidence of Settings information architecture;
- corrected the About timestamp to UTC commit time with seconds and labeled obsolete visual
  guidance as previous guidance; and
- described `SyncBackupPane` as an R9 slot spelling rather than an R11 exception.

## Files in this review

Tracked across these documentation-conflict changes:

- `docs/ADOPT-DRAGONKIT-PROMPT.md`
- `docs/DOC-RULE-CONFLICT-CHANGELOG.md`
- `docs/images/doc-rule-conflicts/*.png`
- `README.md`
- `CONFORMANCE.md`
- `docs/MAC-APP-RELEASE-LIFECYCLE.md`
- `docs/IMPLEMENT-MAC-APP-RELEASE-LIFECYCLE-PROMPT.md`
- historical `docs/superpowers/` plans and specifications that require archival banners

The matching Liquid Glass wording was updated locally in these external skill files, which are not
part of the `dragon-kit` Git repository:

- `~/.claude/skills/liquid-glass-macos/SKILL.md`
- `~/.claude/skills/liquid-glass-macos/references/swiftui-recipes.md`
- `~/.claude/skills/liquid-glass-macos/references/per-app-specs.md`
- `~/.claude/skills/liquid-glass-macos/assets/doc-rule-conflicts/*.png`

## Review boundaries

- Review the documents and image evidence only; do not inspect source code for this checkpoint.
- Do not infer that every described adapter or operation is implemented merely because the desired
  documentation boundary is stated.
- In particular, verify that IMK menu hosting remains separate from Settings UI ownership and that
  KeyKey-specific uninstall behavior is not being generalized into menu-bar app behavior.
- Other audit findings remain out of scope unless they are added as an explicit decision here.
