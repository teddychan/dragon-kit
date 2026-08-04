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
        // 2.9.0, not 2.6.0: DragonKitUpdates overrides `showUpdateNotFoundWithError(_:) async`,
        // which Sparkle only exposes from 2.9 (2.8 has the acknowledgement-block form). An app
        // resolving 2.6–2.8 failed to compile the kit itself — ice-2 hit this.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
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
