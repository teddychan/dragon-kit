// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DragonAppTemplate",
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
            ]
        ),
    ]
)
