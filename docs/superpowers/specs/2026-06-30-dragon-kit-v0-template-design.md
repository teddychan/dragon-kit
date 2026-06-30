# dragon-kit v0 — shared kit + basic app template (design)

- **Date:** 2026-06-30
- **Status:** Approved in brainstorm; pending spec review
- **Owner:** Teddy Chan
- **Related apps:** `ice-2`, `clipmenu-2`, `yahoo-keykey-2`

## 1. Purpose & vision

`dragon-kit` is an open-source Swift Package that gives every Dragon menu-bar app
the same foundations, built and updated **once** instead of re-implemented per app.

End-state feature set shared across all apps:

1. About
2. Check for Update
3. Backup & Restore
4. Multiple Languages (localization)
5. Uninstall
6. Settings (window/shell)
7. Quit

**ice-2's settings UI is the canonical look.** DragonKit reproduces it so every app
that adopts the kit looks the same.

This is delivered **incrementally**, one module at a time, starting from a minimal
runnable **app template**. This document specifies **v0 only**.

## 2. v0 scope

### In scope
- New public mono-repo **`teddychan/dragon-kit`**, **MIT** licensed, containing:
  - the `DragonKit` SwiftPM library (single product, namespaced modules),
  - an `Example/` app that **is** the basic template (and doubles as the kit's demo),
  - `LICENSE`, `README.md`, and a `swift build` + `swift test` GitHub Actions CI.
- **DragonKit foundation:**
  - **Design primitives** reproducing ice-2's look: `DragonForm`, `DragonSection`,
    and a `.dragonAnnotation(_:)` modifier. These are thin wrappers over the system
    **grouped `Form`/`Section`** (exactly how ice-2's `IceForm`/`IceSection` work), so
    the look is identical by construction and low-risk.
  - **Settings shell** — a `NavigationSplitView` window whose sidebar is built from an
    ordered `[any SettingsPane]`, plus the `SettingsPane` protocol modules implement.
  - **Localization helper** `L(_:)` that resolves a key from the module bundle, then
    the app bundle, then falls back to the key (mirrors clipmenu-2's `L`).
  - **About module** (`DragonKit.About`) — an `AboutContent` value the app supplies and
    an `AboutPane` view reproducing ice-2's About pane.
  - **What's New module** (`DragonKit.WhatsNew`) — a `WhatsNewContent` value the app
    supplies (version, date, summary, and grouped `ChangeSection`s: Added/Changed/Fixed/…)
    and a `WhatsNewPane` view rendering a release-notes screen. Added as basic info
    alongside About.
- **Example/template app** — a runnable menu-bar app skeleton:
  - `LSUIElement` SwiftUI app, an `NSStatusItem` with a menu → **Settings…** and **Quit**.
  - Settings window via the DragonKit shell, hosting a **real About pane** + a
    **placeholder "General" pane**.
  - Pre-wired Info.plist, entitlements skeleton, `en.lproj` scaffold, app-name /
    bundle-id placeholders, and a dependency on the local `DragonKit`.

### Explicitly out of scope (later specs)
- Backup & Restore, Check for Update, and Uninstall **modules** (each its own spec).
- Migrating `ice-2` / `clipmenu-2` onto the kit — v0 proves the foundation in the
  Example app only. **Real app migration begins with the Backup & Restore module spec.**
- A scaffolding CLI / "new app" generator (copy-and-rename the Example for now).
- KeyKey onboarding.

## 3. Repository structure

```
dragon-kit/
  Package.swift                 # DragonKit library (+ test target)
  Sources/DragonKit/
    DesignSystem/
      DragonForm.swift          # grouped Form wrapper (port of IceForm)
      DragonSection.swift       # grouped Section wrapper (port of IceSection)
      Annotation.swift          # .dragonAnnotation(_:) caption modifier
    Settings/
      SettingsPane.swift            # protocol + AnySettingsPane eraser
      SettingsShell.swift           # NavigationSplitView + ManagedSettingsShell
      SettingsWindowController.swift # reusable accessory-app window opener
    About/
      AboutContent.swift        # config the app supplies
      AboutPane.swift           # view reproducing ice-2's About
    WhatsNew/
      WhatsNewContent.swift     # WhatsNewContent + ChangeSection(+Kind)
      WhatsNewPane.swift        # release-notes view + WhatsNewSettingsPane
    Localization/
      L.swift                   # module-bundle -> app-bundle string lookup
    Resources/
      en.lproj/DragonKit.strings
  Tests/DragonKitTests/
  Example/                      # the basic app template (see §6 open question)
    ...
  LICENSE                       # MIT
  README.md
  .github/workflows/ci.yml
```

DragonKit contains **no app-specific identifiers** (no bundle ids, no app names baked
in) — everything app-specific is injected by the host.

## 4. Component designs

### 4.1 Design primitives (source-compatible ports of ice-2)
These mirror ice-2's `IceForm` / `IceSection` / `.annotation` **API surface and
defaults**, not just their look, so migrating ice-2 later is a near-mechanical rename
(`Ice*` → `Dragon*`, `.annotation` → `.dragonAnnotation`). All are thin wrappers over
the system grouped `Form` / `Section`.
- `DragonForm` → `Form { }.formStyle(.grouped)` + `.focusSection()` +
  `accessibilityElement(children: .contain)`. Keeps ice's source-compat init params
  (`alignment`, `padding` as `EdgeInsets` **or** `CGFloat`, `spacing`) as
  accepted-but-layout-inert, plus `EdgeInsets.dragonFormDefaultPadding` and
  `CGFloat.dragonFormDefaultSpacing`.
- `DragonSection` — port of `IceSection`: a `DragonSectionOptions` `OptionSet`
  (`isBordered`, `hasDividers`, `plain`, `default`), a `spacing` param, and the full set
  of init overloads (header+content+footer, header+content, content+footer, content-only,
  and `(_ title:)`), each mapping to the system `Section`.
- `.dragonAnnotation(...)` — port of ice's `.annotation`: **both** a `(_ titleKey:)`
  string variant and a `@ViewBuilder content:` variant, with `alignment` (`.leading`),
  `spacing` (`2`), `font` (`.subheadline`), and `foregroundStyle` (`.secondary`) —
  **matching ice's defaults so the look is identical**, not the narrower caption-only
  version.

### 4.2 Settings shell + window
- `protocol SettingsPane: Identifiable where ID == String`: `id`, `title`
  (`LocalizedStringKey`), `systemImage`, and `@MainActor @ViewBuilder var paneBody`
  (named `paneBody`, not `body`, so a type can be both a `SettingsPane` and a `View`).
  Type-erased by `AnySettingsPane` for a homogeneous array.
- `SettingsShell(appName:panes:selection: Binding<String?>)` — the controlled, reusable
  form: a `NavigationSplitView` (app-name header + a `List` of panes; detail = selection).
  The **host owns `selection`**, so it can **persist the selected pane** (e.g.
  `@AppStorage`) and **open directly to a pane** (e.g. About) — matching how clipmenu-2
  persists `settingsSelectedTab` and ice-2 drives selection from an external state object.
- `ManagedSettingsShell(appName:panes:initialSelection:)` — convenience that owns its own
  `@State` selection and renders `SettingsShell`; used by the basic template when no
  persistence is needed.
- `DragonSettingsWindowController` — a reusable `NSWindowController` that opens the
  settings window **reliably for `LSUIElement` (accessory) apps**, where the SwiftUI
  `Settings` scene does not open cleanly (clipmenu-2 ships its own `SettingsWindowController`
  for exactly this reason). It owns a single **resizable** `NSWindow` with a content
  **minimum size** hosting the shell, switches the app to `.regular` + activates on show
  and back to `.accessory` on window close, and is created once and reused.

### 4.3 About module
- `AboutContent`:
  - `appName: String`
  - `versionString: String` (defaults to `CFBundleShortVersionString (CFBundleVersion)`)
  - `copyright: String`
  - `appIcon: NSImage?` (defaults to `NSImage(named: NSImage.applicationIconName)`)
  - `links: [AboutLink]` where `AboutLink { title, detail, systemImage, url }`
  - `credits: [(label: String, value: String)]`
  - `acknowledgementsURL: URL?`
- `AboutPane(content:)` reproduces ice-2's About: centered icon + name + version +
  copyright, a links section (Website / Support / Acknowledgements), and a credits
  section. App supplies its own `AboutContent`.

### 4.4 What's New module
- `ChangeSection`: a `Kind` enum (`added`, `changed`, `fixed`, `removed`, `improved`,
  `security`) with `label` (uppercased header) + `systemImage` (SF Symbol per kind), plus
  `entries: [String]`.
- `WhatsNewContent`: `version`, `date`, `summary` (optional), `sections: [ChangeSection]`.
- `WhatsNewPane(content:)` renders a release-notes screen — title ("What's new in this
  version"), `version · date`, summary, then one grouped section per `ChangeSection` with
  bulleted, icon-tagged entries. `WhatsNewSettingsPane(content:)` is the `SettingsPane`
  wrapper (id `whatsnew`, `sparkles` icon). App supplies its own `WhatsNewContent`.

### 4.5 Localization
- `func L(_ key: String) -> String` — looks up `key` in DragonKit's bundle table, then
  `Bundle.main`, else returns `key`. Each module ships its own `.strings`; the app can
  override by defining the same key.

## 5. Engine-protocol pattern (future modules — documented, not built in v0)

Modules with per-app behavior (Backup, Uninstall) follow one shape: **DragonKit owns the
SwiftUI pane + orchestration; the app injects a small protocol implementation.** Example
for the next module:

```swift
@MainActor
public protocol BackupEngine {
    var folderDisplayPath: String { get }
    var retentionLimit: Int { get }
    func chooseFolder()
    func revealInFinder()
    func listBackups() async throws -> [BackupItem]   // id, date, optional subtitle
    func backUpNow() async throws
    func restore(_ item: BackupItem) async throws     // app decides relaunch vs in-place
    func delete(_ item: BackupItem) async throws
}
```

`@MainActor` + `async` from the start: clipmenu-2's real backup path (`BackupManager`) is
already `@MainActor` and async (it reads/writes a `ModelContext` and does file I/O off the
main actor), so a synchronous protocol would force an immediate redesign. ice-2's
`SettingsBackup` is synchronous today but adapts trivially to async. ice-2 implements the
engine over `SettingsBackup` (settings plist + relaunch); clipmenu-2 over
`BackupManager`/`FolderBackupStore` (snapshot + rollback + security-scoped bookmark). Same
`BackupRestorePane`, different engine. v0 only documents this so the Backup spec can build it.

## 6. Resolved decisions

1. **Template build system → SPM-based app.** The Example/template mirrors clipmenu-2's
   proven structure (Package executable + Info.plist + run/build script), for tooling/CI
   consistency with DragonKit. (Only affects *new* apps started from the template; ice-2
   and clipmenu-2 consume DragonKit as a normal SPM dependency regardless.)
2. **Minimum macOS version → macOS 26.** Matches clipmenu-2's SDK; newest APIs available
   without `@available` gating. (Trade-off: apps deploying below macOS 26 can't adopt the
   kit until/unless the floor is lowered later.)
3. **GitHub publish timing → after v0 builds green.** Keep `dragon-kit` local while
   building; create and push the public repo once `swift build`/`swift test` pass and the
   Example app runs.

## 7. Testing strategy
- DragonKit unit tests (swift-testing): `L` fallback order; `AboutContent` defaults; the
  `SettingsPane` → shell list construction (logic, not pixels).
- Example app must build (`swift build` / app target compiles).
- Manual: launch the Example app — Settings shows About (real) + General (placeholder),
  looks like ice-2, Quit works. Screenshot-compare About against ice-2's About.

## 8. Success criteria
- `swift build` and `swift test` green in `dragon-kit`.
- Example/template app launches as a menu-bar app; Settings window renders via the
  DragonKit shell with a working **About** pane, a **What's New** pane, and a **General**
  placeholder; **Quit** works.
- The look matches ice-2 (grouped form, sidebar, About layout).
- `LICENSE` (MIT), `README.md`, and CI present; no secrets; no app-specific identifiers
  inside `DragonKit`.
- **Non-goal (explicit):** v0 does **not** improve clipmenu-2's or ice-2's actual
  Backup & Restore UI. No shipping app changes; nothing user-visible in those apps. The
  real Backup UI fix (and clipmenu matching ice-2) lands in the **Backup & Restore module
  spec** that follows. v0 is "foundation green," not "clipmenu looks fixed."

## 9. Roadmap (post-v0, each its own spec → plan → PR)
1. **Backup & Restore** module — build `BackupEngine` + `BackupRestorePane`; migrate
   **ice-2** and **clipmenu-2** onto it (this also makes clipmenu's UI identical to ice-2).
2. **Check for Update** (Sparkle wrapper for direct builds).
3. **Uninstall** (standardize the recently-unified flow).
4. **Settings shell hardening** (sizing, sidebar polish) once 3+ panes exist.
5. **App-template polish / optional scaffolding**.
6. **KeyKey** onboarding onto the kit.

Localization rides along with each module.
