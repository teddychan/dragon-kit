# Documentation rule-conflict changelog

**Review checkpoint:** 2026-08-13

**Scope:** documentation only; no source-code or API-support claim

This records the owner-approved resolutions from the documentation conflict audit. It
is intentionally separate from the normative rules so a pull-request reviewer can evaluate what
changed, why it changed, and whether the ownership boundary is correct before later findings are
handled.

## Decision summary

| Priority | Conflict | Resolution | Why |
|---:|---|---|---|
| 1 | Liquid Glass described app-local Settings assembly while DragonKit requires shared Settings primitives. | Liquid Glass owns appearance; DragonKit owns the shared window, shell, pane structure, primitives, and canonical order. | It preserves the visual language without allowing every app to recreate shared structure. |
| 2 | Liquid Glass allowed a free-form About view while DragonKit 4 uses fixed slots. | Use `AboutContent` with `AboutSettingsPane`; DragonKit fixes labels, icons, URL details, order, version format, and the Built-with row. | Typed app content remains flexible while cross-app layout and wording cannot drift. |
| 3 | Liquid Glass required a separate uninstall sheet/window and `NSAlert` button rules while DragonKit presents confirmation inline. | DragonKit owns inline presentation. Apps supply cleanup paths, optional-data configuration, and truthful app-specific explanation. | One confirmation UI serves every app without pretending that every app performs the same cleanup. |
| 4 | The adoption prompt treated every Dragon app as an `NSStatusItem` menu-bar app and described Yahoo! KeyKey differences as exceptions. | Distinguish `NSStatusItem` and Input Method Kit hosts while retaining the same DragonKit Settings UI. KeyKey uses no Quit, launch-at-login, or Permissions pane; its input settings and uninstall configuration remain app-specific. | Host lifecycle and backend inputs differ, but that does not require a different Settings design system or unverified cleanup hook. |
| 5 | KeyKey guidance disagreed about its build system, IMK dispatch, and TIS/uninstall behavior. | Record the verified direct-`swiftc` product build plus nested SwiftPM test packages and SwiftPM-built DragonKit; retain KeyKey's selector-retarget IMK adapter; document Settings-only uninstall and the absence of automatic TIS deregistration. | Current source, executable configuration, and release workflow establish this topology; the previously described TIS hook does not exist. |

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
| Trait-driven omission of inapplicable panes | `no-permissions`; no launch-at-login; input-source removal remains a separate system/user step |

The resulting KeyKey order is **General → Backup & Restore → What's New → Updates → About →
Uninstall**. Omitting Permissions and Quit is supported host/capability topology, not an R11
exception and not permission to hand-roll the remaining shared UI. The implemented uninstall
clears KeyKey's configured defaults/files, moves the running bundle to Trash, conditionally clears
its Homebrew receipt, and terminates after success. It has no TIS deregistration or custom-operation
hook; removing the input source in System Settings and logging out when needed remain separate
steps.

## 5. Verified KeyKey integration and build topology

The current KeyKey product is not Xcode-owned and is not built by either nested SwiftPM manifest.
`tools/build-app.sh` compiles KeyKey with direct `swiftc`. It resolves the pinned DragonKit tag into
`vendor/dragon-kit`, builds the kit there with SwiftPM so its modules and resource bundle exist,
archives the emitted objects, links both DragonKit products, and assembles the LSUIElement IMK app.
The `KeyKeyEngine` and `KeyKeyApp` manifests serve unit-test and compile-check harnesses. Tagged CI
selects the shared release workflow's `script` front end, which generates the language model when
needed and invokes the same app-build script.

At runtime, KeyKey's `InputController.menu()` owns the flat contents supplied to macOS's IMK menu
host. It builds four KeyKey toggles, obtains About/Check for Updates/Settings from
`DragonAppMenu.items`, then retargets those kit-created items to selectors on `InputController`.
Those selectors forward to KeyKey's `AppMenuController`, which selects the correct shared Settings
pane and invokes `DragonUpdater` where applicable. This adapter is the verified DragonKit boundary;
guidance that appends the closure-backed items without preserving it is incomplete.

## Independent-review corrections

Before publication, an independent documentation-only review returned **REVISE BEFORE
CONTINUING**. This pull request also includes the resulting corrections:

- replaced remaining blanket “menu-bar app” language with explicit `NSStatusItem` and IMK hosts;
- made `DragonAppMenu` responsible for applicable lifecycle items rather than asserting every host
  has the same menu;
- limited shared uninstall guidance to presentation invariants and left cleanup targets/order to
  each app;
- first marked KeyKey's TIS cleanup integration point as unverified, then removed that proposed
  hook after the implementation review established that none exists;
- limited the KeyKey screenshot to evidence of Settings information architecture;
- corrected the About timestamp to UTC commit time with seconds and labeled obsolete visual
  guidance as previous guidance; and
- described `SyncBackupPane` as an R9 slot spelling rather than an R11 exception.

## Files in this review

Tracked in this pull-request change:

- `docs/ADOPT-DRAGONKIT-PROMPT.md`
- `docs/DOC-RULE-CONFLICT-CHANGELOG.md`
- `docs/images/doc-rule-conflicts/*.png`
- `README.md`
- `CONFORMANCE.md`

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
- Later audit findings are deliberately out of scope until these four decisions are accepted.
