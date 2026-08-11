# DragonKit

Shared SwiftUI foundations for [Dragon App](https://www.dragonapp.com) macOS
menu-bar apps (ice-2, clipmenu-2, spectacle-2, KeyKey) — built and updated once.

## Status — the About pane is canon, settings survive an upgrade, and the rules are machine-checked

**Current version:** whatever [the newest release](https://github.com/teddychan/dragon-kit/releases/latest)
says. This file deliberately names no version: §R10 fails an app whose pin is behind the newest
tag, so a hardcoded number here goes stale the day after a release and starts instructing a
violation.

Two products in one package:

- **`DragonKit`** (core, no external deps) and **`DragonKitUpdates`** (adds Sparkle) —
  so Mac App Store apps can link the core and skip Sparkle.

Modules:

- **Design primitives** — `DragonForm`, `DragonSection`, `.dragonAnnotation`
  (source-compatible ports of ice-2's grouped-`Form` look).
- **Menu** — `DragonAppMenu` builds the canonical status-item dropdown (About, Check for
  Updates, Settings, Quit) so every app's menu order, naming, and icons match. Uninstall is
  deliberately excluded — it lives in Settings.
- **Settings** — `SettingsShell` (host-owned selection) + `ManagedSettingsShell`;
  `DragonSettingsWindowController` opens it reliably for accessory apps; modules
  conform to `SettingsPane`. It also installs a minimal menu bar while the window is open —
  an accessory app going `.regular` with no `NSApp.mainMenu` shows an *empty* one, costing
  ⌘W, ⌘Q and every pasteboard shortcut in a settings text field. Pass
  `installsMainMenu: false` to opt out; an app that already owns a main menu keeps it. A
  system-managed input method passes `includeQuit: false` instead — same spelling and same
  reason as `DragonAppMenu.Config.includeQuit` — which drops Quit ⌘Q while keeping the Edit and
  Window menus, because an IME's settings still need Cut/Copy/Paste and ⌘W.
- **App Settings** — `DragonSettingsStore<Value>` (Codable persistence in a UserDefaults
  suite) + `LoginItem` (launch at login via `SMAppService`). `load()` **migrates** a blob
  written before the app's settings type gained a field, rather than resetting to defaults:
  Swift's synthesized `Decodable` throws on a missing key, so a strict decode meant adding one
  setting silently wiped every preference on upgrade. A blob that still can't be read is
  preserved under `<key>.unreadable` instead of being dropped.
- **About** — `AboutContent` + `AboutPane` / `AboutSettingsPane`. **Fixed slots**: an app supplies
  URLs and proper nouns, and the kit assembles every row title, SF Symbol and ordering —
  `Website` / `Support on GitHub` / `Original project`\* / `Open-source licenses`, then a
  **Credits** section of `Created by` / `Based on`\* / `Built with · DragonKit vX.Y.Z` /
  `License` / app attributions\* (`*` = optional). Attributions are `name → licence`
  (`Sparkle → MIT`), never a role label. Link detail text is derived from the URL
  rather than typed beside it, and `websiteMatchesSupportRepo` checks the website addresses the
  canonical `dragonapp.com/{app-name}-{major}` page. `AboutContent` took free-form
  `links`/`credits` arrays until five apps used them to ship five different panes. Two slots
  closed again in 4.0.0, after the same drift reappeared in the gaps between them: `licensesURL`
  is **required**, and the upstream repository lives **inside** `OriginalWork`, so the
  `Original project` link and the `Based on` credit are one value. The copyright names **one
  holder** — the app's own (CONFORMANCE §R13).
- **What's New** — release-notes pane: `WhatsNewContent` / `ChangeSection` (Added /
  Changed / Fixed …) + `WhatsNewPane` / `WhatsNewSettingsPane`. `version` is not public; the
  pane renders `displayVersion`, so every version in the UI carries exactly one `v`.
- **Permissions** — `DragonPermission` (+ `.accessibility()` / `.screenRecording()`) +
  `PermissionsSettingsPane` (Open System Settings; status refreshes on a ~1s cadence **while
  the app is active**, and immediately on becoming active — the grant happens over in System
  Settings, so polling in the background was pure TCC traffic nobody was looking at). The two
  kit factories supply localization keys, so their titles and details render in all 7
  languages; an app-supplied literal still works, because `L()` falls back to the key.
- **Backup & Restore** — `DragonBackup` (snapshot/restore a UserDefaults suite) +
  `BackupSettingsPane` (`BackupConfig`). `writeBackupIfChanged` returns `.unchanged` rather
  than writing a duplicate when nothing has changed since the newest backup — the pane says so
  instead of silently no-opping, and ten redundant files can't push the last genuinely
  different snapshot out of the retention window. `restore` refuses a file that isn't a backup,
  or one taken from another suite; both used to *erase* the suite instead. The pane keeps the
  chosen folder as a security-scoped bookmark so it survives relaunch under App Sandbox.
- **Uninstall** — `DragonUninstaller` + `UninstallView` / `UninstallSettingsPane`
  (`UninstallConfig`) — incl. an optional, default-off "also delete user data" toggle
  (`optionalDataToggle`) and always-removed `extraCleanupPaths` (caches, support files). A
  failed Trash move is reported to the user instead of quitting as though it had worked — the
  settings teardown before it is irreversible. An app shipped as a Homebrew cask passes
  `homebrewCask:` so the post-exit cleanup clears brew's receipt too: Homebrew never watches the
  filesystem, so an app that deletes itself leaves a receipt still claiming it is installed and a
  dangling `Caskroom` symlink, and `brew install` then refuses outright for an app that isn't
  there. Direct-download only — a sandboxed build can't spawn processes. That cleanup is spawned
  **only after the Trash move succeeds**: it ends in `brew uninstall --cask --force`, which quits
  the app and deletes the bundle, so on the failure path it would delete an app the user was just
  told is still installed. Build the token with
  `UninstallConfig.caskToken("token", ifBundleIs: releaseBundleID)` rather than passing it flat —
  a cask token is not bundle-scoped, so a re-id'd debug build's uninstall would otherwise remove
  the *release* app; the helper fails closed on a debug id, another app's id and a missing one.
- **Updates** (`DragonKitUpdates`) — `DragonUpdater` (Sparkle wrapper) +
  `UpdatesSettingsPane`. `DragonUpdaterConfig` opts an app into Sparkle's gentle scheduled
  reminders and an `onUpdateFoundInBackground` callback (fires only for *scheduled* checks —
  someone who just clicked "Check for Updates…" is already looking at the answer);
  `DragonUpdater.start()` schedules background checks explicitly instead of relying on a
  property read to initialize the updater.
- **Localization** — `L(_:)` (module bundle → app bundle → key) with a runtime
  `LocalizationManager` + `LanguagePicker` and `.dragonLocalized()`. Ships **7 languages**
  (en, es, fr, ja, ko, zh-Hans, zh-Hant); switches **live, no restart**. Apps add their own
  `Localizable.strings` per language and drop in `LanguagePicker`. An app translated into fewer
  languages than the kit passes its own set — `LanguagePicker(languages: [.en, .zhHans])` — so it
  never offers a language its own strings don't have; `onChange:` covers apps whose strings can't
  switch live (a SwiftUI String Catalog resolves at launch, so it needs a relaunch).
- **[dragon-sample-app](https://github.com/teddychan/dragon-sample-app)** — the **Dragon Sample
  App**, a runnable, installable **reference app** in its own repository, wiring up every module
  end-to-end: General (real persisted toggles), Permissions, Backup & Restore, What's New,
  Updates, About, Uninstall — plus About, Check-for-Updates, Settings and Quit in the menu.

## Requirements
macOS 26+, Swift 6.1.

## Use it

```swift
// Pin the NEWEST tag. Get it with:
//   gh release view --repo teddychan/dragon-kit --json tagName -q '.tagName | ltrimstr("v")'
.package(url: "https://github.com/teddychan/dragon-kit", from: "X.Y.Z")
```

Pin the **newest** `vX.Y.Z` tag, not the oldest one that resolves — [CONFORMANCE.md](CONFORMANCE.md)
§R10 fails an app whose pin is behind, because a stale pin is how an app silently misses a
shared fix. `2.0.0` was breaking (`DragonAppMenu.Config` lost `onUninstall`), so a `from: "1.x"`
pin never picks any of this up.

```swift
import DragonKit

let panes = [
    AnySettingsPane(MyGeneralPane()),
    AnySettingsPane(AboutSettingsPane(content: myAboutContent)),
]
let controller = DragonSettingsWindowController(
    title: "My App Settings",
    rootView: ManagedSettingsShell(appName: "My App", panes: panes)
)
controller.show()
```

## Settings pane order

Every Dragon app lists its settings panes in the same sidebar order, so the apps
feel like one family. The order is **host-owned** — `SettingsShell` renders panes in
the order the app puts them in its `settingsPanes` list, so each app is responsible
for following this convention:

```
General → (the app's own panes) → Permissions → Backup & Restore → What's New → Updates → About → Uninstall
```

[Dragon Sample App](https://github.com/teddychan/dragon-sample-app) wires its panes up in this
order — mirror it in new apps.

## Menu-bar dropdown order

Every Dragon app builds its status-item dropdown from **`DragonAppMenu`** — one source of
truth for order, naming, and icon, so the menus can't drift the way hand-rolled `NSMenu`s did.
The canonical form (macOS title-case, leading SF Symbol on every item, ellipsis on items that
open a window/dialog, app name appended to About / Quit):

```
info.circle        About <App>
arrow.down.circle  Check for Updates…   (omit for Mac App Store builds — pass onCheckForUpdates: nil)
gearshape          Settings…       ⌘,
──────────
power              Quit <App>      ⌘Q   (omit for an IME — pass includeQuit: false)
```

The symbols are fixed in the kit, not per-app config — the design spec is "lead every item
with an SF Symbol … only the name string differs".

**Uninstall is deliberately not in this menu.** It lives in Settings as `UninstallSettingsPane`:
a rarely-used destructive action doesn't belong one click away in the everyday dropdown, right
next to Quit. Every app ships that pane in its sidebar, so uninstalling is still one click from
`Settings…`. There is no flag to put it back — that's the point.

Apps whose dropdown is only these items use `DragonAppMenu.menu(_:)`; apps with their own
content above (clipboard history, input-method toggles, …) build that and append
`DragonAppMenu.items(_:)` after their own separator.
[Dragon Sample App](https://github.com/teddychan/dragon-sample-app) uses `DragonAppMenu.menu(_:)`
— mirror it in new apps.

## Try it: the Dragon Sample App

**Dragon Sample App** is a real, installable reference app that wires up every module (Settings,
Permissions, Backup & Restore, Updates, Uninstall, About, What's New, live localization). Install
the released build with Homebrew:

```bash
brew install --cask teddychan/tap/dragon-sample-app
```

Or build and run it from source. `run.sh` produces a separate **Dragon Sample App Debug** build
(`com.dragonapp.dragon-sample-app.debug`) so it won't collide with an installed copy's permissions
or settings:

```bash
git clone https://github.com/teddychan/dragon-sample-app && cd dragon-sample-app && ./scripts/run.sh
```

It lives in [its own repository](https://github.com/teddychan/dragon-sample-app), not in this one.
It is a normal app, so its public tag is exactly `vX.Y.Z` — and a repository owns only one public
`vX.Y.Z` series, which here belongs to the Swift package. So the app owns its source, appcast,
artifacts and cask, and this repository builds no app at all. The `sample-v*` tags left here are
historical migration data.

## Start a new app on DragonKit
See [`docs/STARTING-A-NEW-APP.md`](docs/STARTING-A-NEW-APP.md) — a self-contained guide
(API cheat-sheet + complete starter files) for scaffolding a new menu-bar app on this kit.

## For AI agents: how to use this template

DragonKit is a **published SwiftPM package** — the one place the shared parts of every
Dragon menu-bar app live. **Depend on it; never copy its code into your app.**

1. Read [`docs/STARTING-A-NEW-APP.md`](docs/STARTING-A-NEW-APP.md) (self-contained) and
   [dragon-sample-app](https://github.com/teddychan/dragon-sample-app) — the reference wiring for
   every module.
2. Create an SPM executable app that depends on `dragon-kit` at a version tag
   (pin the **newest** tag; §R10 fails a stale pin). Link `DragonKit`; add
   `DragonKitUpdates` **only** for direct-download (non-Mac-App-Store) apps.
3. Build settings screens as `SettingsPane` conformers using `DragonForm` /
   `DragonSection` / `.dragonAnnotation`.
4. Supply your app's **content/config** — `AboutContent`, `WhatsNewContent`, a settings
   model (`DragonSettingsStore`), a `[DragonPermission]`, `BackupConfig`,
   `UninstallConfig`, `DragonUpdater` — and wire them into `ManagedSettingsShell` +
   `DragonSettingsWindowController`.

## Single source of truth

Two layers, deliberately separated:

- **Shared behavior lives here, once.** Pane layouts, the settings shell, backup logic,
  the updater, and the uninstall flow are owned by this repo. Fix or improve them **in
  `dragon-kit`**, tag a new version, and every app picks the change up by bumping its
  dependency (`swift package update`). Apps must not fork or re-implement these — and since
  v2.1.0 that is **machine-checked**, not review-enforced: [CONFORMANCE.md](CONFORMANCE.md)
  states the rules, `Scripts/dragon-conformance.py` implements them, and each app calls
  [`.github/workflows/conformance.yml`](.github/workflows/conformance.yml) from its own CI so
  a violation fails the PR. Every rule is a drift that actually happened.
- **App-specific content is injected by each app.** Your About text, What's New entries,
  settings shape, permission list, and configs are yours — DragonKit renders them but does
  not own them.

So, for example, to change the **About pane's layout for every app**, edit `AboutPane` in
`dragon-kit` and release a new tag. To change **one app's About content** (name, links),
edit that app's `AboutConfig`. And the **version** is itself a single source of truth: read
it from the app's `Info.plist` (`CFBundleShortVersionString`) — never hardcode it (see
[dragon-sample-app's `AboutConfig.swift`](https://github.com/teddychan/dragon-sample-app/blob/main/Sources/DragonAppTemplate/AboutConfig.swift))
— so About, backups, and update checks all report the same value.

The development-to-release boundary is specified in
[`docs/MAC-APP-RELEASE-LIFECYCLE.md`](docs/MAC-APP-RELEASE-LIFECYCLE.md). In particular, Debug
is only a local build-and-test configuration; it is not another version or release channel.
Every public tag gates current What's New content, and marketing-site refreshes are asynchronous
and non-blocking.

For the cross-repository rollout, use the ready-to-paste
[`docs/IMPLEMENT-MAC-APP-RELEASE-LIFECYCLE-PROMPT.md`](docs/IMPLEMENT-MAC-APP-RELEASE-LIFECYCLE-PROMPT.md).

## Roadmap
Done: App Settings, Permissions, Backup & Restore, Check for Update, Uninstall, What's New,
7-language live localization, the canonical `DragonAppMenu` dropdown, and the machine-checked
conformance spec (all demonstrated in
[dragon-sample-app](https://github.com/teddychan/dragon-sample-app)). The migration phase is over:
all five apps — ice-2, clipmenu-2, spectacle-2, KeyKey and Dragon Sample App — depend on the kit
from their own repository and run [`conformance.yml`](.github/workflows/conformance.yml) in their
own CI, so re-implementing a kit module now fails a PR instead of passing review.

Deferred, deliberately: a generalized **folder-based versioned backup** pane
(versioned snapshot files of arbitrary app data, retention, restore list — the shape
clipmenu-2 ships app-side). Generalize it here only when a second app (KeyKey / ice-2)
needs that same shape; until then `DragonBackup` stays UserDefaults-suite-only.

The settings pane's *own* user-picked folder now carries a security-scoped bookmark, so the
folder it already had survives relaunch under App Sandbox. That is not this deferral being
reversed: `DragonBackup` still snapshots one UserDefaults suite and still knows nothing about
folders-as-a-shape.

## License
MIT.
