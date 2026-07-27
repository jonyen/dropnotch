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
        // Icon artwork lives outside DropNotchCore: it is build-time tooling
        // and has no business in the shipping app binary.
        .target(name: "IconArt", path: "Sources/IconArt"),
        .executableTarget(
            name: "IconGen",
            dependencies: ["IconArt"],
            path: "Sources/IconGen"
        ),
        .testTarget(
            name: "DropNotchTests",
            dependencies: ["DropNotchCore", "IconArt"],
            path: "Tests/DropNotchTests"
        ),
    ]
)
