// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DragonAppTemplate",
    platforms: [.macOS("26")],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "DragonAppTemplate",
            dependencies: [.product(name: "DragonKit", package: "dragon-kit")]
        ),
    ]
)
