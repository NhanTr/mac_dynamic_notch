// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DynamicNotch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DynamicNotch", targets: ["DynamicNotch"])
    ],
    targets: [
        // Pure, AppKit-free logic (geometry, layout, state). Fully unit-testable.
        .target(
            name: "NotchCore",
            path: "Sources/NotchCore"
        ),
        // The macOS agent app: windows, SwiftUI views, services.
        .executableTarget(
            name: "DynamicNotch",
            dependencies: ["NotchCore"],
            path: "Sources/DynamicNotch"
        ),
        .testTarget(
            name: "NotchCoreTests",
            dependencies: ["NotchCore"],
            path: "Tests/NotchCoreTests"
        ),
    ]
)
