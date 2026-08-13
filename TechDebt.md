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
spellings. Leave that compatibility in place until the two app migrations are complete. Then, in
one coordinated follow-up:

1. Migrate ClipMenu 2 and Ice 2 to `BackupSettingsPane` + `DragonBackup` and verify backup/restore
   behavior and upgrade safety in each app.
2. Remove the legacy backup-pane spellings from the conformance implementation.
3. Update `CONFORMANCE.md`, `Scripts/dragon-conformance.py`, and
   `Scripts/test_conformance.py` together so the shared-pane requirement is machine-enforced.
4. Run the conformance checker against every affected app and verify the canonical sidebar order.

This debt record does not authorize changing application code, conformance scripts, or tests as
part of the Liquid Glass documentation repair.
