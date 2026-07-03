import OSLog
import ServiceManagement

/// "Launch at login" via `SMAppService.mainApp` (macOS 13+): registers or unregisters the
/// running app as a login item. Ported from ice-2; app-agnostic. Failures are logged, not
/// thrown, so a settings toggle never crashes the app.
public enum LoginItem {
    private static let logger = Logger(subsystem: "com.dragonapp.DragonKit", category: "LoginItem")

    /// Whether the app is currently registered to launch at login.
    public static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Register (`true`) or unregister (`false`) the app as a login item.
    public static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            logger.error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
