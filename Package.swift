// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SignalLightMac",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "signal-light-mac", targets: ["SignalLightMac"]),
        .executable(name: "signal-light-cli", targets: ["SignalLightCLI"])
    ],
    targets: [
        .executableTarget(
            name: "SignalLightMac",
            path: "Sources/SignalLightMac"
        ),
        .executableTarget(
            name: "SignalLightCLI",
            path: "Sources/SignalLightCLI"
        )
    ]
)
