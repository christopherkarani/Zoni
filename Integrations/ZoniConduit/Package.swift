// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ZoniConduit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "ZoniConduit",
            targets: ["ZoniConduit"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/christopherkarani/Conduit.git", from: "1.0.1"),
    ],
    targets: [
        .target(
            name: "ZoniConduit",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "Conduit", package: "Conduit"),
                .product(name: "ConduitAdvanced", package: "Conduit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
