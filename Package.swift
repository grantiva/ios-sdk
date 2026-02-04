// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Grantiva",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Grantiva",
            targets: ["Grantiva"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Grantiva",
            dependencies: [],
            path: "Sources/Grantiva"
        ),
        .testTarget(
            name: "GrantivaTests",
            dependencies: ["Grantiva"],
            path: "Tests/GrantivaTests"
        ),
    ]
)
