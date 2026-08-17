# DragonKit technical debt

## Unify every app on DragonKit backup

**Status:** Approved target; app migration and machine enforcement deferred.

The shared Settings information architecture is the canon owned by `CONFORMANCE.md` §R9:

```text
General → (the app's own panes) → Permissions (when applicable) → Backup & Restore → What's New → Updates (when applicable) → About → Uninstall
```

The host controls its app-owned panes and whether its capabilities require
`PermissionsSettingsPane`. From **Backup & Restore** onward, every pane and its shared behavior come
from DragonKit. In particular, all apps must use `BackupSettingsPane` and `DragonBackup`; an
app-specific backup pane or engine is not the target architecture.

Two apps have not migrated:

| App | Current debt | Target |
|---|---|---|
| ClipMenu 2 | `SyncBackupPane` implements folder-based snippet/settings backup and sync. | Replace it with `BackupSettingsPane` backed by `DragonBackup`. |
| Ice 2 | `IceBackupSettingsPane` implements Ice-specific settings/layout backup. | Replace it with `BackupSettingsPane` backed by `DragonBackup`. |

`DragonBackup` currently snapshots a UserDefaults suite. Before replacing either pane, inventory
the data and user-visible workflows in the existing implementation and decide how each maps to the
shared model. If the shared model lacks a capability every app should have, add it once in
DragonKit rather than preserving an app-local exception. Do not claim folder, snippet, layout, or
sync behavior that `DragonBackup` does not implement.

### Deferred enforcement work

The current conformance rule recognizes `SyncBackupPane` and `IceBackupSettingsPane` as Backup-slot
spellings — as of 2026-08-14 it genuinely does. This document and `README.md` both asserted it
before `IceBackupSettingsPane` was in the slot list at all; ice-2 passed anyway because its
`paneOrder` file is an enum whose `case backup` matches, which left the claim true by accident and
the slot one refactor away from going unchecked. Leave that compatibility in place until the two
app migrations are complete. Then, in one coordinated follow-up:

1. Migrate ClipMenu 2 and Ice 2 to `BackupSettingsPane` + `DragonBackup` and verify backup/restore
   behavior and upgrade safety in each app.
2. Remove the legacy backup-pane spellings from the conformance implementation.
3. Update `CONFORMANCE.md`, `Scripts/dragon-conformance.py`, and
   `Scripts/test_conformance.py` together so the shared-pane requirement is machine-enforced.
4. Run the conformance checker against every affected app and verify the canonical sidebar order.

This debt record does not authorize changing application code, conformance scripts, or tests as
part of the Liquid Glass documentation repair.

## Move every app's bundle inputs into `App/` (§R16)

**Status:** rule accepted and implemented; enforcement gated until the apps migrate.

`CONFORMANCE.md` §R16 places the `Info.plist`, the icon and the entitlements in `App/` at the repo
root, with one directory per additional bundle. `Scripts/dragon-conformance.py` implements it and
`Scripts/test_conformance.py` covers it, but `R16_ENFORCED` is `False`: four of the five apps keep
these files elsewhere, and enforcing on merge would fail every open PR in four repositories over a
layout none of them has moved to. Until the flip, findings print as `pending R16 …` and change no
exit code.

**This entry is what the checker's `TODO(R16)` names.** Nothing else records the sequence.

Where the files are today (measured 2026-08-17 against each app's `origin/main`; re-measure before
acting):

| App | Move |
|---|---|
| yahoo-keykey-2 | none — already `App/Info.plist`, `App/AppIcon.icns`, `App/YahooKeyKey2.entitlements` |
| clipmenu-2 | the package directory `app/` is RENAMED to `App/`, bundle inputs and all — `App/` cannot sit beside `app/` on a case-insensitive filesystem, and moving the three files alone produces an index git is happy with and a working tree that does not match it ([Incidents §R16](docs/CONFORMANCE-INCIDENTS.md#the-case-check-earned-its-keep-on-the-first-migration)) |
| spectacle-2 | `{Info.plist,AppIcon.icns}` → `App/…` |
| dragon-sample-app | `Info.plist` → `App/Info.plist` |
| ice-2 | `Ice/Resources/Info.plist` → `App/Info.plist`; `MenuBarItemService/Resources/Info.plist` → `App/MenuBarItemService/Info.plist` (its icon is an asset catalog and stays there — §R16 places `.icns` files, and ice-2 has none) |

Each move is a **path change in the app's build, not a file move on its own**, and three of them
reach outside the app repository:

1. `teddychan/dragon-release-ci`'s `release-macos.yml` assembles the SwiftPM bundle with
   `working-directory: <swiftpm_working_directory>` and then reads a bare `Info.plist` and
   `AppIcon.icns` — so it assumes the plist and `Package.swift` share one directory, which `App/`
   ends. That needs an input (a bundle-inputs directory, defaulting to the empty string so an
   unmigrated caller keeps reading from `swiftpm_working_directory` exactly as before) before any
   SwiftPM app can move. Shipped as `swiftpm_bundle_inputs_directory` in dragon-release-ci v6.5.0.
2. `clipmenu-2/.github/workflows/release-mas.yml` does the same inline, under
   `working-directory: app`.
3. ice-2's `Ice.xcodeproj` names both plists in `INFOPLIST_FILE`; keykey's `tools/build-app.sh`
   already reads `App/`; each app's local `scripts/run.sh` copies the plist by path.

Order that avoids a broken release: land the reusable-workflow input first, then migrate one app
per PR, then flip `R16_ENFORCED` here. **The flip is a dedicated PR in this repository, opened
after the app migrations have merged** — it cannot ride the last app's PR, which is in another
repository and cannot edit this file. An earlier draft of this paragraph said it could, which is
the kind of sequencing instruction that reads fine and cannot be carried out.

Conditions to check before opening that PR, none of which the checker can tell you:

1. Every app's **default branch** enumerates a directory named exactly `App` — read it with
   `os.listdir`, not `os.path.exists`, for the reason
   [Incidents §R16](docs/CONFORMANCE-INCIDENTS.md#the-case-check-earned-its-keep-on-the-first-migration)
   records.
2. The checker reports no pending R16 finding against those default branches, not against the
   migration branches.
3. Each app's release path has been exercised without publishing — `verify_only: true` on the
   reusable workflow, which is the only way to run it from a branch with no tag. clipmenu-2's Mac
   App Store workflow is self-contained and has no such route; whatever evidence stands in for one
   there should be recorded rather than assumed.
4. No app has declared an §R11 exception for §R16. Until the flip, such an entry names a rule that
   cannot fire — the phantom sanction
   [Incidents §R11](docs/CONFORMANCE-INCIDENTS.md#the-five-phantom-sanctions) records — and after
   it, one would need the reason and owner §R11 demands of any other.

`Scripts/test_conformance.py` covers the flip itself: it runs the CLI from a copy of the checker
with the constant rewritten and requires the same fixture to pass gated off and fail gated on, so
the driver wiring is tested rather than promised.

## Parked: §R4's prose is broader than its enforcement

**Status:** owner has parked the decision; do not act on it without them. Recorded here so the
facts are in one place when it is picked up.

`CONFORMANCE.md` §R4 says a violation is "a type named `*Form`/`*Section`/`*GroupBox` that isn't
from the kit". The checker's `LAYOUT_PRIMITIVE` is narrower on **two** axes, not one:

1. **`GroupBox` is excluded outright.** ice-2's `IceGroupBox` was a bordered box the kit has no
   equivalent for, so the rule offered no compliant path except inlining it or renaming it to dodge
   the check — the reasoning is at `Scripts/dragon-conformance.py`'s `LAYOUT_PRIMITIVE` comment.
   Since then ice-2 renamed it to `CalloutBox`, and **no app declares a `*GroupBox` type any more**,
   so widening the checker costs nothing today and narrowing the prose breaks nothing today.
2. **The pattern also requires the generic view-wrapper shape** `<…: View>`. So a plain
   `struct IceSection: View` is documented as a violation and is not one. This axis was never
   recorded in the audit and is not about GroupBox at all.

Whatever is decided should settle both, or the same finding comes back for the other half.

The cheapest route is doc-only, and §R3 already has the template — DragonKit 4.0.0's §R3 reads
"Top-level on both sides, and that is the rule, not a limitation of the checker." Applying that
wording to §R4 (naming the generic-wrapper shape as the rule, and stating why the kit ships no
bordered-box primitive to compare against) closes it with no checker change and no risk to five
apps. Adding a kit primitive so `GroupBox` *can* be enforced is the larger option: new public API,
a design decision about a bordered-box style, and ice-2's `CalloutBox` becomes a migration.
