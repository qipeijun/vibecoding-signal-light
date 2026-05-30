// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SignalLightMac",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .library(name: "SignalLightShared", targets: ["SignalLightShared"]),
        .executable(name: "signal-light-mac", targets: ["SignalLightMac"]),
        .executable(name: "signal-light-cli", targets: ["SignalLightCLI"])
    ],
    targets: [
        .target(
            name: "SignalLightShared",
            path: "Sources/SignalLightShared"
        ),
        .executableTarget(
            name: "SignalLightMac",
            dependencies: ["SignalLightShared"],
            path: "Sources/SignalLightMac"
        ),
        .executableTarget(
            name: "SignalLightCLI",
            dependencies: ["SignalLightShared"],
            path: "Sources/SignalLightCLI"
        ),
        .testTarget(
            name: "SignalLightSharedTests",
            dependencies: ["SignalLightShared"],
            path: "tests/SignalLightSharedTests"
        )
    ]
)
