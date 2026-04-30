// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ZoniHTTP",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "ZoniHTTP",
            targets: ["ZoniHTTP"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
    ],
    targets: [
        .target(
            name: "ZoniHTTP",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ]
        ),
        .testTarget(
            name: "ZoniHTTPTests",
            dependencies: ["ZoniHTTP"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
