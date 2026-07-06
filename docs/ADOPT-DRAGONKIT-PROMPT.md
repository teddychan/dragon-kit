# Adopt-DragonKit prompt

A ready-to-paste prompt for a **new chat session inside one of the app repos** (ClipMenu,
KeyKey, Ice, …). It tells the agent to depend on DragonKit and move the app's common
menu-bar features and UI onto the shared modules — without copying kit code.

Paste the block below, then apply the per-app tweaks noted underneath.

---

```
Adopt the shared DragonKit template for this app's common menu-bar features and UI.

DragonKit is our published SwiftPM package that owns the shared parts of every Dragon
menu-bar app, so each app builds them once and updates them centrally.
- Repo: https://github.com/teddychan/dragon-kit  (local clone: ~/git/dragon-kit)
- Depend on it at a version tag — DO NOT copy its source into this app:
      .package(url: "https://github.com/teddychan/dragon-kit", from: "1.1.0")
- Two products:
    • DragonKit         — core, no external deps
    • DragonKitUpdates  — adds Sparkle; link ONLY in a direct-download build,
                          NOT in a Mac App Store build.

FIRST, before writing code, read these (they are the source of truth):
  1. ~/git/dragon-kit/docs/STARTING-A-NEW-APP.md  — self-contained guide + starter files
  2. ~/git/dragon-kit/Example/  — a runnable reference app wiring up EVERY module
     end-to-end (esp. Example/Sources/DragonAppTemplate/AppDelegate.swift and the
     *Config.swift files). Mirror its patterns.
  3. ~/git/dragon-kit/README.md  — module list

GOAL: replace this app's bespoke implementations of these features with DragonKit
modules, supplying only this app's own content/config. Use:
  • Design primitives — DragonForm, DragonSection, .dragonAnnotation (grouped-Form look)
  • Settings shell    — SettingsShell (host-owned selection) + DragonSettingsWindowController;
                        each screen conforms to SettingsPane.
                        NOTE: SettingsPane.title is a localization KEY (String), rendered via L().
  • App Settings      — DragonSettingsStore<Value> (Codable persistence in a UserDefaults
                        suite) + LoginItem (launch at login)
  • About             — AboutContent + AboutSettingsPane
  • What's New        — WhatsNewContent / ChangeSection + WhatsNewSettingsPane
  • Permissions       — DragonPermission (.accessibility() / .screenRecording()) +
                        PermissionsSettingsPane
  • Backup & Restore  — DragonBackup + BackupSettingsPane (BackupConfig)
  • Uninstall         — DragonUninstaller + UninstallSettingsPane (UninstallConfig);
                        it confirms INLINE in the pane (no popup window)
  • Updates           — (DragonKitUpdates) DragonUpdater + UpdatesSettingsPane
  • Localization      — L(_:), LocalizationManager, LanguagePicker, .dragonLocalized().
                        Ships 7 languages (en, es, fr, ja, ko, zh-Hans, zh-Hant) and
                        switches language LIVE, no restart. This app supplies its own
                        Localizable.strings per language and drops in LanguagePicker.

Settings pane (sidebar) order — list panes in settingsPanes in this order, so every
Dragon app's Settings sidebar matches (the order is host-owned; the shell just renders
what you give it):
  General → (this app's own panes) → Permissions → Sync & Backup → What's New → Updates → About → Uninstall

Menu-bar wiring to copy from Example/AppDelegate.swift:
  • NSStatusItem menu with localized titles, rebuilt on .dragonLanguageChanged.
  • Host-owned selection so a menu item can open Settings directly on a specific pane
    (e.g. About).
  • Apply .dragonLocalized() at the settings root so the window switches language live;
    rebuild the panes on language change so injected content (About/What's New) re-localizes.
  • Version is single-sourced from Info.plist (CFBundleShortVersionString /
    CFBundleVersion) — never hardcode it. Use DragonAbout.versionString() for the About
    pane; it formats as "v<short> (<build>) · <UTC build time>".

CONSTRAINTS:
  • Depend on DragonKit; never fork or re-implement its shared behavior. If a shared
    layout/behavior needs changing, that change belongs in dragon-kit (new tag), not here.
  • Only this app's content/config lives here: About text, What's New entries, settings
    model, permission list, BackupConfig, UninstallConfig, DragonUpdater, and the app's
    own Localizable.strings.
  • Keep this app's existing feature logic intact — only swap the settings/About/What's New/
    Permissions/Backup/Uninstall/Updates/Localization UI over to DragonKit.

Start by reading the docs + Example, then propose a short migration plan (which screens map
to which modules, what config each needs) before changing code.
```

---

## Per-app tweaks (edit before pasting)

- **Sparkle / `DragonKitUpdates`** — for an app with both a Mac App Store build and a free
  build (e.g. ClipMenu), link `DragonKitUpdates` **only** in the direct-download target; the
  MAS target links `DragonKit` only. For a direct-download-only app, link both everywhere.
- **Permission type** — name the permission the app actually needs (e.g. `.accessibility()`
  for KeyKey/Ice) instead of the generic placeholder.
- **Version pin** — bump `from: "1.1.0"` to whatever the latest DragonKit tag is.
