# DragonKit technical debt

## Unify every app on DragonKit backup

**Status:** Approved target; app migration and machine enforcement deferred.

The shared Settings information architecture is:

```text
General → app-owned panes → Permissions (when applicable) → Backup & Restore → What's New → Updates → About → Uninstall
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
