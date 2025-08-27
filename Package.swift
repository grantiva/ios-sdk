// swift-tools-version: 5.4

import PackageDescription

let package = Package(
    name: "Grantiva",
    platforms: [
        .iOS(.v14),
        .macOS(.v11)
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
