// swift-tools-version: 6.0
// iOSDocumentQA - Example iOS app demonstrating Zoni RAG capabilities

import PackageDescription

let package = Package(
    name: "iOSDocumentQA",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [
        .package(path: "../.."),  // Zoni
    ],
    targets: [
        .executableTarget(
            name: "iOSDocumentQA",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "ZoniApple", package: "zoni"),
            ],
            path: "Sources"
        ),
    ]
)
