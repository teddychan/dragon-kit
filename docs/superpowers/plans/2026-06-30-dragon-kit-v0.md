# dragon-kit v0 Implementation Plan — decision record

> [!WARNING]
> **Status: FULLY SUPERSEDED — HISTORICAL IMPLEMENTATION PLAN**
>
> **Implementation from this file is prohibited.** Do not execute its agent directive, task
> steps, API examples, commits, or publishing steps.
>
> Current authority:
>
> - [`README.md`](../../../README.md) — current package architecture, ownership, and entry points
> - [`CONFORMANCE.md`](../../../CONFORMANCE.md) — normative adoption and UI rules
> - [`STARTING-A-NEW-APP.md`](../../STARTING-A-NEW-APP.md) — current scaffolding and public API
> - [`MAC-APP-RELEASE-LIFECYCLE.md`](../../MAC-APP-RELEASE-LIFECYCLE.md) — canonical release and repository ownership
> - [Dragon Sample App](https://github.com/teddychan/dragon-sample-app) — current reference app in its own repository
>
> Known obsolete assumptions include the in-tree `Example/` app, hand-built lifecycle
> `NSMenuItem`s, free-form About links and credits, acknowledgements and typed link details,
> hardcoded version metadata, the v0 roadmap, and the original publishing workflow. Any status
> or imperative wording below describes the 2026-06-30 plan, not present-day instructions.
>
> **Reduced 2026-08-16 from 1,412 lines to this record.** What was cut was an *executable*
> checklist — shell commands, complete file bodies, commit and publish steps — for a package
> that now exists and is the better description of itself. The design decisions, the locked
> file structure, the per-task rationale and the self-review are kept in full below. The
> original is recoverable:
>
>     git show f2339d4 > /tmp/dragon-kit-v0-plan-full.md    # blob, at repo commit c6bb179
>     git log --follow -- docs/superpowers/plans/2026-06-30-dragon-kit-v0.md

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the open-source `dragon-kit` Swift package (DragonKit library: design primitives, settings shell + window controller, localization helper, About module) plus a runnable minimal menu-bar **Example** app that uses it.

**Architecture:** One SwiftPM library `DragonKit` (namespaced modules) consumed by an SPM-based Example app. DragonKit's primitives are **source-compatible ports** of ice-2's `IceForm`/`IceSection`/`.annotation` (same API surface + defaults), so later app migration is a near-mechanical rename. Settings is a data-driven `NavigationSplitView` shell with host-owned selection, opened via a reusable accessory-app `NSWindowController`. App-specific data (About content, app name) is injected by the host.

**Tech Stack:** Swift 6.1, SwiftUI + AppKit, SwiftPM, swift-testing, macOS 26 deployment target. Repo: `~/git/dragon-kit` (local; public `teddychan/dragon-kit` pushed only after v0 builds green).

**Reference spec:** `docs/superpowers/specs/2026-06-30-dragon-kit-v0-template-design.md`

**Conventions:** Commit as `teddychan <teddychan@gmail.com>` (repo already configured). End each commit message with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Run all `swift` commands from `~/git/dragon-kit` unless noted.

---

## File structure (locked)

```
dragon-kit/
  Package.swift
  Sources/DragonKit/
    DesignSystem/DragonForm.swift
    DesignSystem/DragonSection.swift
    DesignSystem/Annotation.swift
    Settings/SettingsPane.swift            # SettingsPane protocol + AnySettingsPane
    Settings/SettingsShell.swift           # SettingsShell + ManagedSettingsShell
    Settings/SettingsWindowController.swift # DragonSettingsWindowController
    Localization/L.swift
    About/AboutContent.swift               # AboutContent + AboutLink
    About/AboutPane.swift                  # AboutPane view + AboutSettingsPane
    Resources/en.lproj/DragonKit.strings
  Tests/DragonKitTests/
    LocalizationTests.swift
    AboutContentTests.swift
    SettingsPaneTests.swift
  Example/
    Package.swift
    Sources/DragonAppTemplate/App.swift          # @main entry
    Sources/DragonAppTemplate/AppDelegate.swift
    Sources/DragonAppTemplate/GeneralPane.swift
    Sources/DragonAppTemplate/AboutConfig.swift
    Resources/Info.plist
    scripts/run.sh
  LICENSE
  README.md
  .gitignore
  .github/workflows/ci.yml
```

---

## Tasks, and why each was shaped the way it was

The task bodies are gone; their titles and their design notes are what the plan was actually
deciding. Notes are quoted from the original.

**Task 1: Package skeleton that builds.** Its `DragonKit.ping` = `pong` fixture and
`SmokeTests.swift` were both removed on 2026-08-06 and must not be reintroduced. The reason lives
where it is enforced — [`Tests/DragonKitTests/LocalizationTests.swift`](../../../Tests/DragonKitTests/LocalizationTests.swift),
on `resolvesKeyFromModuleBundle()`: key parity forces every key into every locale, so a test-only
key shipped to users in seven languages. (`SmokeTests` asserted `#expect(Bool(true))`; if the
package didn't build, the test target wouldn't compile and every other test would fail first.)

**Task 2: Localization helper `L`.**

**Task 3: Design primitives (source-compatible ports of ice-2).**

> These mirror ice-2's `IceForm`/`IceSection`/`.annotation` **API surface and defaults**
> (compat params, `DragonSectionOptions`, the full init overload set, and an annotation
> with `.subheadline`/spacing-2 defaults), so later ice-2 migration is a rename, not a
> rewrite. Pure view wrappers — verified by `swift build`, exercised on screen in Task 8.

**Task 4: SettingsPane protocol + AnySettingsPane.**

**Task 5: SettingsShell (host-owned selection) + ManagedSettingsShell.**

> `SettingsShell` takes a `Binding<String?>` so the host can persist the selected pane
> and open directly to a pane; `ManagedSettingsShell` is the self-managed convenience for
> the simple template. SwiftUI views — verified by `swift build`, exercised in Task 8.

**Task 6: DragonSettingsWindowController (reliable accessory-app window).**

> The genuinely hard, reusable part for `LSUIElement` apps: the SwiftUI `Settings` scene
> doesn't open cleanly for accessory apps (clipmenu-2 ships its own `SettingsWindowController`
> for this). AppKit — verified by `swift build`, exercised in Task 8.

**Task 7: About module (AboutContent + AboutPane + AboutSettingsPane).**

**Task 8: Example menu-bar app (the basic template).**

> An SPM executable assembled into a `.app` by `run.sh` (mirrors clipmenu-2). Uses
> `DragonSettingsWindowController` + `ManagedSettingsShell` so the template stays tiny and
> the hard window logic lives in the kit. `@main` + `@MainActor static main()` keeps Swift 6
> concurrency happy (no `main.swift`). Verified by building, then launching manually.

> Note: the parent package directory is `dragon-kit`, so `package:` is `"dragon-kit"`. If
> `swift build` reports a different expected package identifier, use the name SwiftPM prints.

Expected behaviour on launch: a resizable window with a sidebar (General, About). **About** shows
icon/name/version/links/credits like ice-2. Closing the window returns the app to accessory (no
Dock icon). **Quit** terminates the app.

**Task 9: OSS scaffolding (LICENSE, README, CI).**

**Task 10: Publish (only after v0 is green) — requires user confirmation.**

> Outward-facing. Do this only once Tasks 1–9 are green and the Example app runs, and only
> after confirming with the owner.

## Post-plan addition — Task 11: What's New module
Added after review at the owner's request ("we should have a section called 'What's New' …
add it as the basic info"). `DragonKit/WhatsNew/` — `WhatsNewContent` + `ChangeSection`
(`Kind`: added/changed/fixed/removed/improved/security, with uppercased `label` +
per-kind `systemImage`) + `WhatsNewPane` + `WhatsNewSettingsPane`. TDD: 4 tests
(`WhatsNewContentTests`) for label/symbol/storage/defaults; library now 12 tests. Wired
into the Example as a third pane (`WhatsNewConfig`). String `DragonKit.whatsNew.title`.

## Self-review notes
- **Spec coverage:** primitives as source-compatible ports (T3), SettingsPane (T4),
  host-owned shell + managed convenience (T5), reusable accessory window controller (T6),
  About (T7), localization (T2), Example template w/ window controller + About + General +
  Quit (T8), MIT+README+CI (T9), publish-after-green (T10), macOS 26 + SPM app (T1, T8).
  All §2 in-scope items covered; §2 out-of-scope (Backup/Updates/Uninstall, scaffolding,
  app migration, KeyKey) intentionally excluded. Review items #1 (T3), #2 (T5), #3 (T6,T8),
  #4 (spec §5), #5 (spec §8) addressed.
- **Type consistency:** `SettingsPane.paneBody` / `AnySettingsPane(_:)` used identically in
  T4–T8. `SettingsShell(...selection:)` / `ManagedSettingsShell(...initialSelection:)`
  consistent between T5 and T8. `DragonSettingsWindowController(title:rootView:)` matches
  between T6 and T8. `AboutContent`/`AboutLink`/`AboutSettingsPane` match T7↔T8.
- **Known risks:** (1) `Example/Package.swift` `package:` identifier (`dragon-kit`) — T8
  Step 8 has a fallback. (2) `List` optional-selection: rows use `.tag(pane.id as String?)`
  to match `Binding<String?>`; if selection still doesn't update, verify the tag type in T8
  Step 9. (3) SwiftUI module-bundle string localization deferred to the Localization module
  spec; v0 visible strings localize via the app bundle (`LocalizedStringKey`); `L()` covers
  module lookups. (4) macOS 26 / Swift 6.1 toolchain assumed present (Darwin 25 = macOS 26).
