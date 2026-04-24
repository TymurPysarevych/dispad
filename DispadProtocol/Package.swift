// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DispadProtocol",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "DispadProtocol", targets: ["DispadProtocol"])
    ],
    targets: [
        .target(name: "DispadProtocol"),
        .testTarget(
            name: "DispadProtocolTests",
            dependencies: ["DispadProtocol"]
        )
    ]
)
