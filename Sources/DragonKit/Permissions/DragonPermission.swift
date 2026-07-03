import AppKit
import ApplicationServices
import CoreGraphics

/// A single system permission the app can check, request, and deep-link into System
/// Settings. Generalized from ice-2's `Permission`: the app supplies the check/request
/// closures (or uses a convenience factory), so the pane is not hardcoded to a fixed set.
@MainActor
public final class DragonPermission: Identifiable {
    public let id: String
    public let title: String
    public let details: [String]
    public let isRequired: Bool
    public let mayRequireRelaunch: Bool
    private let settingsURLs: [URL]
    private let check: () -> Bool
    private let request: (() -> Void)?

    public init(
        id: String,
        title: String,
        details: [String] = [],
        isRequired: Bool = false,
        mayRequireRelaunch: Bool = false,
        settingsURLs: [URL] = [],
        check: @escaping () -> Bool,
        request: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.isRequired = isRequired
        self.mayRequireRelaunch = mayRequireRelaunch
        self.settingsURLs = settingsURLs
        self.check = check
        self.request = request
    }

    /// Whether the app currently holds this permission.
    public var isGranted: Bool { check() }

    /// Whether this permission can be actively requested (vs only opened in Settings).
    public var canRequest: Bool { request != nil }

    /// Trigger the system request prompt (if any), then open the relevant Settings pane.
    public func performRequest() {
        request?()
        openSettings()
    }

    /// Open the first System Settings pane that accepts the URL.
    public func openSettings() {
        for url in settingsURLs where NSWorkspace.shared.open(url) { return }
    }
}

public extension DragonPermission {
    /// Accessibility (AX) — required to observe and control other apps' interface elements.
    static func accessibility(isRequired: Bool = true) -> DragonPermission {
        DragonPermission(
            id: "accessibility",
            title: "Accessibility",
            details: ["Observe and control other apps' interface elements."],
            isRequired: isRequired,
            settingsURLs: [
                URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"),
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            ].compactMap { $0 },
            check: { AXIsProcessTrusted() },
            request: {
                // The CFString value of `kAXTrustedCheckOptionPrompt` (using the literal
                // avoids referencing the non-Sendable global under strict concurrency).
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            }
        )
    }

    /// Screen Recording — required to capture the contents of the screen.
    static func screenRecording(isRequired: Bool = false) -> DragonPermission {
        DragonPermission(
            id: "screenRecording",
            title: "Screen Recording",
            details: ["Capture the contents of the screen."],
            isRequired: isRequired,
            mayRequireRelaunch: true,
            settingsURLs: [
                URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"),
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            ].compactMap { $0 },
            check: { CGPreflightScreenCaptureAccess() },
            request: { _ = CGRequestScreenCaptureAccess() }
        )
    }
}
