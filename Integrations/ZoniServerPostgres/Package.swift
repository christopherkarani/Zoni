// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ZoniServerPostgres",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ZoniServerPostgres",
            targets: ["ZoniServerPostgres"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "ZoniServerPostgres",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
