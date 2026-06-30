import AppKit
import SwiftUI

/// Opens the settings window reliably for `LSUIElement` (accessory) menu-bar apps. Owns
/// one resizable window with a content minimum size, created once and reused; flips the
/// app to `.regular` + activates on show, and back to `.accessory` when the window closes
/// (an accessory app otherwise can't make a window key).
@MainActor
public final class DragonSettingsWindowController: NSWindowController, NSWindowDelegate {
    public init(
        title: String,
        minSize: NSSize = NSSize(width: 720, height: 480),
        defaultSize: NSSize = NSSize(width: 800, height: 560),
        rootView: some View
    ) {
        let hosting = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.contentMinSize = minSize
        window.setContentSize(defaultSize)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Bring settings to front. Accessory apps can't key a window, so temporarily become
    /// a regular app while the window is open.
    public func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
