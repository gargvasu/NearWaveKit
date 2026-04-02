// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NearWaveKit",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "NearWaveKit",
            targets: ["NearWaveKit"]
        ),
    ],
    targets: [
        .target(
            name: "NearWaveKit"
        ),
    ],
    swiftLanguageModes: [.v5]
)
