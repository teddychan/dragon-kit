// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DragonKit",
    defaultLocalization: "en",
    platforms: [.macOS("26")],
    products: [
        .library(name: "DragonKit", targets: ["DragonKit"]),
        // Sparkle-backed updates, isolated so Mac App Store apps don't link Sparkle.
        .library(name: "DragonKitUpdates", targets: ["DragonKitUpdates"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "DragonKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "DragonKitUpdates",
            dependencies: [
                "DragonKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ]
        ),
        .testTarget(
            name: "DragonKitTests",
            dependencies: ["DragonKit"]
        ),
    ]
)
