import Testing
@testable import DragonKit

/// The kit's two convenience permissions must supply localization **keys**, not English prose.
/// They shipped as literals until it was noticed that neither could ever localize:
/// `PermissionsPane` rendered `details` with `Text(String)` (verbatim, no table lookup), and
/// re-wrapped `title` as a `LocalizedStringKey`, which resolves against the *host app's* bundle
/// rather than the kit's. These tests are the guard against regressing to literals — a literal
/// silently "works" (`L()` falls back to the key), so nothing else would catch it.
@MainActor
@Suite struct PermissionLocalizationTests {
    @Test func accessibilityFactorySuppliesResolvableKeys() {
        let permission = DragonPermission.accessibility()
        #expect(L(permission.title) != permission.title, "title is not a DragonKit localization key")
        #expect(!permission.details.isEmpty)
        for detail in permission.details {
            #expect(L(detail) != detail, "detail is not a DragonKit localization key: \(detail)")
        }
    }

    @Test func screenRecordingFactorySuppliesResolvableKeys() {
        let permission = DragonPermission.screenRecording()
        #expect(L(permission.title) != permission.title, "title is not a DragonKit localization key")
        #expect(!permission.details.isEmpty)
        for detail in permission.details {
            #expect(L(detail) != detail, "detail is not a DragonKit localization key: \(detail)")
        }
    }

    /// Apps pass their own permissions with plain literal copy. `L()` falls back to the key
    /// itself, so a literal renders unchanged — which is why the factories could be switched to
    /// keys without a signature change or an app-side edit.
    @Test func appSuppliedLiteralsRoundTripUnchanged() {
        let permission = DragonPermission(
            id: "fullDisk",
            title: "Full Disk Access",
            details: ["Read files the app is otherwise denied."],
            check: { false }
        )
        #expect(L(permission.title) == "Full Disk Access")
        #expect(permission.details.map { L($0) } == ["Read files the app is otherwise denied."])
    }

    /// The pane now reads status through this helper on a poll instead of calling `isGranted`
    /// from `body` once per permission per second. It must report exactly what `check()` says,
    /// for every permission, at the moment it is called.
    @Test func currentStatusesReportsEachPermissionsCheck() {
        var accessibilityGranted = false
        let a = DragonPermission(id: "a", title: "A", check: { accessibilityGranted })
        let b = DragonPermission(id: "b", title: "B", check: { true })

        #expect(PermissionsPane.currentStatuses(of: [a, b]) == ["a": false, "b": true])

        accessibilityGranted = true
        #expect(PermissionsPane.currentStatuses(of: [a, b]) == ["a": true, "b": true])
    }
}
