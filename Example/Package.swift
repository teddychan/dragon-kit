// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DragonAppTemplate",
    defaultLocalization: "en",
    platforms: [.macOS("26")],
    dependencies: [
        // Pin the identity so the product reference (`package: "dragon-kit"`) resolves
        // regardless of the checkout directory name (e.g. a git worktree).
        .package(name: "dragon-kit", path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "DragonAppTemplate",
            dependencies: [
                .product(name: "DragonKit", package: "dragon-kit"),
                .product(name: "DragonKitUpdates", package: "dragon-kit"),
            ],
            // Bundle the app's own localizations (Resources/<lang>.lproj) into
            // DragonAppTemplate_DragonAppTemplate.bundle so both run.sh and the release CI
            // ship them via the standard SwiftPM resource-bundle copy. Resolved at runtime
            // through LocalizationManager.appStringsBundle = .module (set in AppDelegate).
            resources: [.process("Resources")]
        ),
    ]
)
