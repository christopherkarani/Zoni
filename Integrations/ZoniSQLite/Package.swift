// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ZoniSQLite",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "ZoniSQLite",
            targets: ["ZoniSQLite"]
        ),
        .library(
            name: "ZoniSQLiteApple",
            targets: ["ZoniSQLiteApple"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../ZoniApple"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.0"),
    ],
    targets: [
        .target(
            name: "ZoniSQLite",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ]
        ),
        .target(
            name: "ZoniSQLiteApple",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "ZoniApple", package: "ZoniApple"),
                "ZoniSQLite",
            ]
        ),
        .testTarget(
            name: "ZoniSQLiteTests",
            dependencies: [
                "ZoniSQLite",
                .product(name: "ZoniCore", package: "zoni"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
