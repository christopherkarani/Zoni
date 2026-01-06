// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentWithRAG",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../.."),  // Zoni
    ],
    targets: [
        .executableTarget(
            name: "AgentWithRAG",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "ZoniAgents", package: "zoni"),
            ],
            path: "Sources"
        ),
    ]
)
