import Testing
import Foundation
@testable import DragonKit

/// Covers `BackupFolder`, the part of the Backup pane that decides *which* folder is used.
///
/// The pane itself is SwiftUI and effectively untestable, which is exactly why this logic was
/// pulled out of it. What is under test is the thing that broke: outside a sandbox a stored path
/// string is enough, but under App Sandbox — which the kit supports, since clipmenu-2 ships a Mac
/// App Store build against the core product — the `NSOpenPanel` grant does not survive relaunch,
/// so a path alone means "Back Up Now" starts failing after a restart. A security-scoped bookmark
/// is what carries the grant across launches, and the precedence between it, the legacy path and
/// the default folder is what decides whether an existing user's chosen folder is kept or silently
/// reverted.
///
/// Nothing here renders SwiftUI or needs sandbox entitlements.
@Suite struct BackupPaneTests {
    /// A real directory to point a bookmark at, cleaned up by the caller's `defer`.
    private static func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "DragonKitBackupPaneTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Both sides are compared symlink-resolved. FileManager and bookmark resolution hand back
    /// `/private/var/...` while a freshly built temp URL says `/var/...`; comparing the raw paths
    /// fails on that alias alone and has already produced one flaky test in this work.
    private static func expectSameDirectory(_ lhs: URL, _ rhs: URL, _ note: Comment) {
        #expect(lhs.resolvingSymlinksInPath().path == rhs.resolvingSymlinksInPath().path, note)
    }

    @Test func bookmarkRoundTripsBackToTheSameFolder() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let bookmark = try #require(
            BackupFolder.makeBookmark(for: directory),
            "a plain readable directory must be bookmarkable; without this the grant can't be stored at all"
        )
        let resolved = try #require(BackupFolder.resolve(bookmark: bookmark))

        Self.expectSameDirectory(resolved.url, directory, "a bookmark must resolve to the folder it was made for")
        // Freshly minted, so nothing has moved yet. If this ever reports stale on creation the
        // pane would re-mint a bookmark on every single launch.
        #expect(!resolved.isStale)
    }

    /// Unusable bookmark data has to answer nil, not trap. `@AppStorage` hands over empty `Data`
    /// for a user who never picked a folder, and that value reaches `resolve` on every launch —
    /// a trap here would be a crash on launch for the default configuration.
    @Test func resolveReturnsNilForUnusableDataInsteadOfTrapping() {
        #expect(BackupFolder.resolve(bookmark: Data()) == nil, "empty is the never-chosen case")
        #expect(BackupFolder.resolve(bookmark: Data([0xDE, 0xAD, 0xBE, 0xEF])) == nil, "garbage bytes")
        #expect(BackupFolder.resolve(bookmark: Data(repeating: 0, count: 1024)) == nil, "plausible size, no content")
    }

    @Test func bookmarkOutranksTheLegacyPath() throws {
        let directory = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmark = try #require(BackupFolder.makeBookmark(for: directory))

        let resolution = BackupFolder.folder(
            bookmark: bookmark,
            legacyPath: "/tmp/some-other-folder-the-user-has-moved-on-from",
            appName: "Dragon Sample App"
        )

        Self.expectSameDirectory(
            resolution.url,
            directory,
            "the bookmark is the only source that still carries a sandbox grant, so it has to win"
        )
        #expect(!resolution.isStale)
    }

    /// The migration case: everyone upgrading has a path and no bookmark. If the path stopped
    /// being read they would silently land back on the default folder with their existing backups
    /// orphaned somewhere else.
    @Test func legacyPathOutranksTheDefaultFolder() {
        let resolution = BackupFolder.folder(
            bookmark: Data(),
            legacyPath: "/Users/someone/Backups/Dragon",
            appName: "Dragon Sample App"
        )

        Self.expectSameDirectory(
            resolution.url,
            URL(fileURLWithPath: "/Users/someone/Backups/Dragon"),
            "an upgrading user's stored path must still be honoured when there is no bookmark yet"
        )
        #expect(!resolution.isStale)
    }

    @Test func defaultFolderWhenNeitherIsStored() {
        let resolution = BackupFolder.folder(bookmark: Data(), legacyPath: "", appName: "Dragon Sample App")

        #expect(resolution.url == DragonBackup.defaultFolder(appName: "Dragon Sample App"))
        #expect(!resolution.isStale)
    }
}
