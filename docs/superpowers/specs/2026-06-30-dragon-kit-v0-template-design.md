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
      SettingsPane.swift        # protocol: id, title, systemImage, body
      SettingsShell.swift       # NavigationSplitView + data-driven sidebar
    About/
      AboutContent.swift        # config the app supplies
      AboutPane.swift           # view reproducing ice-2's About
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

### 4.1 Design primitives
- `DragonForm { ... }` → `Form { content }.formStyle(.grouped)` with `.focusSection()`
  and `accessibilityElement(children: .contain)`. Direct port of `IceForm`.
- `DragonSection(_ title:) { ... }` (and header/footer overloads) → system `Section`.
  Direct port of `IceSection`.
- `.dragonAnnotation(_ text:)` → renders a caption (`.font(.caption)`,
  `.foregroundStyle(.secondary)`) beneath a row's control, matching ice-2's
  `.annotation(...)`.

### 4.2 Settings shell
- `protocol SettingsPane: Identifiable`: `var id: String`, `var title: LocalizedStringKey`,
  `var systemImage: String`, `@ViewBuilder var body: some View` (type-erased via a small
  `AnySettingsPane` wrapper for the array).
- `SettingsShell(appName: String, panes: [AnySettingsPane])` renders a `NavigationSplitView`:
  sidebar = big app-name header + a `List` of panes (Label with `systemImage` + `title`),
  detail = the selected pane's `body`. Mirrors ice-2's `SettingsView`, but data-driven
  instead of a hardcoded enum switch.

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

### 4.4 Localization
- `func L(_ key: String) -> String` — looks up `key` in DragonKit's bundle table, then
  `Bundle.main`, else returns `key`. Each module ships its own `.strings`; the app can
  override by defining the same key.

## 5. Engine-protocol pattern (future modules — documented, not built in v0)

Modules with per-app behavior (Backup, Uninstall) follow one shape: **DragonKit owns the
SwiftUI pane + orchestration; the app injects a small protocol implementation.** Example
for the next module:

```swift
public protocol BackupEngine {
    var folderDisplayPath: String { get }
    var retentionLimit: Int { get }
    func chooseFolder()
    func revealInFinder()
    func listBackups() throws -> [BackupItem]   // id, date, optional subtitle
    func backUpNow() throws
    func restore(_ item: BackupItem) throws     // app decides relaunch vs in-place
    func delete(_ item: BackupItem) throws
}
```

ice-2 implements it over `SettingsBackup` (settings plist + relaunch); clipmenu-2 over
`BackupManager`/`FolderBackupStore` (snapshot + rollback + security-scoped bookmark).
Same `BackupRestorePane`, different engine. v0 only documents this so the Backup spec can
build it.

## 6. Open questions for spec review

1. **Template build system** — *recommend* an **SPM-based app** mirroring clipmenu-2's
   proven structure (Package executable + Info.plist + run script), for tooling/CI
   consistency with DragonKit. Alternative: a minimal Xcode project (matches ice-2,
   better for MAS/signing UI). Either consumes DragonKit identically.
2. **Minimum macOS version** — *recommend* **macOS 14**, with `@available` gating for
   newer (Liquid Glass / macOS 26) APIs, so all three apps can adopt the kit.
3. **GitHub publish timing** — create/push the public `dragon-kit` repo during
   implementation (after the plan), or keep local until v0 is built? *Recommend* push
   once v0 builds green.

## 7. Testing strategy
- DragonKit unit tests (swift-testing): `L` fallback order; `AboutContent` defaults; the
  `SettingsPane` → shell list construction (logic, not pixels).
- Example app must build (`swift build` / app target compiles).
- Manual: launch the Example app — Settings shows About (real) + General (placeholder),
  looks like ice-2, Quit works. Screenshot-compare About against ice-2's About.

## 8. Success criteria
- `swift build` and `swift test` green in `dragon-kit`.
- Example/template app launches as a menu-bar app; Settings window renders via the
  DragonKit shell with a working **About** pane + a **General** placeholder; **Quit** works.
- The look matches ice-2 (grouped form, sidebar, About layout).
- `LICENSE` (MIT), `README.md`, and CI present; no secrets; no app-specific identifiers
  inside `DragonKit`.

## 9. Roadmap (post-v0, each its own spec → plan → PR)
1. **Backup & Restore** module — build `BackupEngine` + `BackupRestorePane`; migrate
   **ice-2** and **clipmenu-2** onto it (this also makes clipmenu's UI identical to ice-2).
2. **Check for Update** (Sparkle wrapper for direct builds).
3. **Uninstall** (standardize the recently-unified flow).
4. **Settings shell hardening** (sizing, sidebar polish) once 3+ panes exist.
5. **App-template polish / optional scaffolding**.
6. **KeyKey** onboarding onto the kit.

Localization rides along with each module.
