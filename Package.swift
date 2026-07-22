// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Zoni",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        // Core RAG library with document loading capabilities
        .library(
            name: "Zoni",
            targets: ["Zoni"]
        ),
        // Lightweight contracts and value types for custom integrations
        .library(
            name: "ZoniCore",
            targets: ["ZoniCore"]
        ),
        // Server-side extensions (multi-tenancy, job system, shared abstractions)
        .library(
            name: "ZoniServer",
            targets: ["ZoniServer"]
        ),
        // SwiftAgents integration layer
        .library(
            name: "ZoniAgents",
            targets: ["ZoniAgents"]
        ),
    ],
    dependencies: [
        // Phase 5A: Cryptography for JWT validation
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),

        // Phase 5A: Logging for production deployments
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        // Lightweight contracts and value types
        .target(
            name: "ZoniCore",
            path: "Sources/ZoniCore"
        ),

        // Core target with document loading
        .target(
            name: "Zoni",
            dependencies: [
                "ZoniCore",
            ],
            path: "Sources/Zoni"
        ),

        // Server extensions (shared abstractions, multi-tenancy, job system)
        .target(
            name: "ZoniServer",
            dependencies: [
                "Zoni",
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/ZoniServer"
        ),

        // SwiftAgents integration layer
        .target(
            name: "ZoniAgents",
            dependencies: ["Zoni"],
            path: "Sources/ZoniAgents"
        ),

        // Core tests
        .testTarget(
            name: "ZoniTests",
            dependencies: ["Zoni"],
            path: "Tests/ZoniTests"
        ),

        // Server tests
        .testTarget(
            name: "ZoniServerTests",
            dependencies: ["ZoniServer"],
            path: "Tests/ZoniServerTests"
        ),
        // SwiftAgents integration tests
        .testTarget(
            name: "ZoniAgentsTests",
            dependencies: ["ZoniAgents", "Zoni"],
            path: "Tests/ZoniAgentsTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
