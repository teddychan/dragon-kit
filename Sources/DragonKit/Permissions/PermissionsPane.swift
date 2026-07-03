import SwiftUI

/// Renders an app-supplied list of ``DragonPermission``s: per-permission status, a Request
/// and/or "Open System Settings" button, and a manual Refresh. Status re-checks about once
/// a second while visible, so it updates after the user grants access in System Settings.
/// Generalized from ice-2's hardcoded permissions pane.
public struct PermissionsPane: View {
    private let permissions: [DragonPermission]

    public init(permissions: [DragonPermission]) {
        self.permissions = permissions
    }

    public var body: some View {
        PermissionsPaneView(permissions: permissions)
    }
}

private struct PermissionsPaneView: View {
    let permissions: [DragonPermission]
    // Mutating this re-invokes `body`, which re-reads each permission's live status.
    @State private var refreshToken = 0

    var body: some View {
        DragonForm {
            ForEach(permissions) { permission in
                DragonSection(LocalizedStringKey(permission.title)) {
                    statusRow(permission)
                    actionRow(permission)
                }
            }
            DragonSection {
                Button(L("DragonKit.permissions.refresh")) { refreshToken &+= 1 }
                    .dragonAnnotation(LocalizedStringKey(L("DragonKit.permissions.refreshHint")))
            }
        }
        .id(refreshToken)
        .task { await pollForChanges() }
    }

    @ViewBuilder
    private func statusRow(_ permission: DragonPermission) -> some View {
        let granted = permission.isGranted
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.red)
            Text(granted ? L("DragonKit.permissions.granted") : L("DragonKit.permissions.notGranted"))
            Spacer()
        }
        .dragonAnnotation {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(permission.details, id: \.self) { Text($0) }
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ permission: DragonPermission) -> some View {
        HStack {
            if permission.canRequest {
                Button(L("DragonKit.permissions.request")) {
                    permission.performRequest()
                    refreshToken &+= 1
                }
            }
            Button(L("DragonKit.permissions.openSettings")) { permission.openSettings() }
        }
    }

    private func pollForChanges() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            refreshToken &+= 1
        }
    }
}

/// Drop-in Permissions pane for the settings shell. The app supplies the permission list
/// (e.g. `[.accessibility()]`).
public struct PermissionsSettingsPane: SettingsPane {
    public let id = "permissions"
    public let title: LocalizedStringKey = "Permissions"
    public let systemImage = "lock.shield"
    private let permissions: [DragonPermission]

    public init(permissions: [DragonPermission]) {
        self.permissions = permissions
    }

    public var paneBody: some View { PermissionsPane(permissions: permissions) }
}
