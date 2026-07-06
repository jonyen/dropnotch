// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DropNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DropNotchCore", path: "Sources/DropNotchCore"),
        .executableTarget(
            name: "DropNotch",
            dependencies: ["DropNotchCore"],
            path: "Sources/DropNotch"
        ),
        .testTarget(
            name: "DropNotchTests",
            dependencies: ["DropNotchCore"],
            path: "Tests/DropNotchTests"
        ),
    ]
)
