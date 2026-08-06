import AppKit
import Combine
import SwiftUI

/// Renders an app-supplied list of ``DragonPermission``s: per-permission status, a Request
/// and/or "Open System Settings" button, and a manual Refresh. Status re-checks about once
/// a second *while the app is active*, plus immediately on becoming active, so it updates
/// after the user grants access in System Settings. Generalized from ice-2's hardcoded
/// permissions pane.
public struct PermissionsPane: View {
    private let permissions: [DragonPermission]

    public init(permissions: [DragonPermission]) {
        self.permissions = permissions
    }

    public var body: some View {
        PermissionsPaneView(permissions: permissions)
    }

    /// Every permission's current status, keyed by ``DragonPermission/id``. Each entry is a
    /// TCC round trip (`AXIsProcessTrusted()` and friends), which is why the pane calls this
    /// on a deliberate cadence instead of reading `isGranted` from `body`. Factored out so
    /// the read step is testable without rendering SwiftUI.
    @MainActor
    static func currentStatuses(of permissions: [DragonPermission]) -> [String: Bool] {
        permissions.reduce(into: [:]) { $0[$1.id] = $1.isGranted }
    }
}

private struct PermissionsPaneView: View {
    let permissions: [DragonPermission]

    /// Cached status per ``DragonPermission/id``; only ``refreshStatuses()`` writes it.
    ///
    /// This used to be a counter bumped once a second and applied as `.id(refreshToken)`,
    /// which changed the whole form's explicit identity every tick: SwiftUI discarded and
    /// rebuilt the entire subtree, and the rebuilt `body` re-read `permission.isGranted` —
    /// one TCC IPC round trip per permission per second, on the main actor, for the life of
    /// a resident menu-bar app. Nothing obviously stopped it either, since
    /// ``DragonSettingsWindowController`` sets `isReleasedWhenClosed = false`, so closing the
    /// settings window keeps the hosting controller (and this view) alive.
    @State private var statuses: [String: Bool]

    @MainActor
    init(permissions: [DragonPermission]) {
        self.permissions = permissions
        // Seed from live values: `.task` only runs after the first render, so without this
        // the pane would flash a red "Not granted" for an already-granted permission.
        _statuses = State(initialValue: PermissionsPane.currentStatuses(of: permissions))
    }

    var body: some View {
        DragonForm {
            ForEach(permissions) { permission in
                DragonSection(LocalizedStringKey(L(permission.title))) {
                    statusRow(permission)
                    actionRow(permission)
                }
            }
            DragonSection {
                Button(L("DragonKit.permissions.refresh")) { refreshStatuses() }
                    .dragonAnnotation(LocalizedStringKey(L("DragonKit.permissions.refreshHint")))
            }
        }
        .task { await pollForChanges() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // The grant happens in System Settings, i.e. while we are in the background and
            // not polling. Re-read the moment the user switches back, so the row flips
            // instantly rather than up to a poll interval later.
            refreshStatuses()
        }
    }

    @ViewBuilder
    private func statusRow(_ permission: DragonPermission) -> some View {
        let granted = statuses[permission.id] ?? false
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.red)
            Text(granted ? L("DragonKit.permissions.granted") : L("DragonKit.permissions.notGranted"))
            Spacer()
        }
        .dragonAnnotation {
            VStack(alignment: .leading, spacing: 2) {
                // `Text(String)` is verbatim — it does no table lookup — so the kit's own
                // detail lines rendered in English in all seven languages until `L()` was
                // put back in front of them.
                ForEach(permission.details, id: \.self) { Text(L($0)) }
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ permission: DragonPermission) -> some View {
        HStack {
            if permission.canRequest {
                Button(L("DragonKit.permissions.request")) {
                    permission.performRequest()
                    refreshStatuses()
                }
            }
            Button(L("DragonKit.permissions.openSettings")) { permission.openSettings() }
        }
    }

    /// Re-check on a ~1s cadence, but only while the app is frontmost. A status can change
    /// while we are in the background — that is exactly where the user grants it — but nobody
    /// is looking at this window then, and `didBecomeActiveNotification` re-reads on the way
    /// back, so background ticks would be pure TCC traffic for an unseen redraw.
    private func pollForChanges() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard NSApp.isActive else { continue }
            refreshStatuses()
        }
    }

    /// Write only on an actual change: assigning an equal value to `@State` still invalidates
    /// the view, and a steady state — which is the normal case, forever — must cost nothing.
    private func refreshStatuses() {
        let latest = PermissionsPane.currentStatuses(of: permissions)
        if latest != statuses { statuses = latest }
    }
}

/// Drop-in Permissions pane for the settings shell. The app supplies the permission list
/// (e.g. `[.accessibility()]`).
public struct PermissionsSettingsPane: SettingsPane {
    public let id = "permissions"
    public let title = "DragonKit.pane.permissions"
    public let systemImage = "lock.shield"
    private let permissions: [DragonPermission]

    public init(permissions: [DragonPermission]) {
        self.permissions = permissions
    }

    public var paneBody: some View { PermissionsPane(permissions: permissions) }
}
