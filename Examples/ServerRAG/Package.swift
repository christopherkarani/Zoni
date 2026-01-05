// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ServerRAG",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),  // Zoni
        .package(url: "https://github.com/vapor/vapor.git", from: "4.90.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "ZoniServer", package: "zoni"),
                .product(name: "ZoniVapor", package: "zoni"),
                .product(name: "Vapor", package: "vapor"),
            ],
            path: "Sources/App"
        ),
    ]
)
