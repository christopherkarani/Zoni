// swift-tools-version: 6.0
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
        // Server-side extensions (multi-tenancy, job system, shared abstractions)
        .library(
            name: "ZoniServer",
            targets: ["ZoniServer"]
        ),
        // Vapor framework integration
        .library(
            name: "ZoniVapor",
            targets: ["ZoniVapor"]
        ),
        // Hummingbird framework integration
        .library(
            name: "ZoniHummingbird",
            targets: ["ZoniHummingbird"]
        ),
        // Apple platform extensions (NaturalLanguage, Accelerate, etc.)
        .library(
            name: "ZoniApple",
            targets: ["ZoniApple"]
        ),
        // SwiftAgents integration layer
        .library(
            name: "ZoniAgents",
            targets: ["ZoniAgents"]
        ),
    ],
    dependencies: [
        // Core dependencies
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),

        // Phase 3: Vector Store dependencies
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.25.0"),

        // Phase 5A: Cryptography for JWT validation
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),

        // Phase 5A: Vapor integration
        .package(url: "https://github.com/vapor/vapor.git", from: "4.90.0"),
        .package(url: "https://github.com/vapor/jwt.git", from: "4.0.0"),

        // Phase 5A: Hummingbird integration
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird-auth.git", from: "2.0.0"),

        // Phase 5B: Apple Platform Extensions
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.18.0"),
        .package(url: "https://github.com/jkrukowski/swift-embeddings.git", from: "0.0.8"),
    ],
    targets: [
        // Core target with document loading
        .target(
            name: "Zoni",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/Zoni"
        ),

        // Server extensions (shared abstractions, multi-tenancy, job system)
        .target(
            name: "ZoniServer",
            dependencies: [
                "Zoni",
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/ZoniServer"
        ),

        // Vapor framework integration
        .target(
            name: "ZoniVapor",
            dependencies: [
                "ZoniServer",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "JWT", package: "jwt"),
            ],
            path: "Sources/ZoniVapor"
        ),

        // Hummingbird framework integration
        .target(
            name: "ZoniHummingbird",
            dependencies: [
                "ZoniServer",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdWebSocket", package: "hummingbird-websocket"),
                .product(name: "HummingbirdAuth", package: "hummingbird-auth"),
            ],
            path: "Sources/ZoniHummingbird"
        ),

        // Apple platform extensions (Phase 5B)
        .target(
            name: "ZoniApple",
            dependencies: [
                "Zoni",
                // MLX for GPU-accelerated embeddings (Apple Silicon only)
                .product(name: "MLX", package: "mlx-swift", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "MLXNN", package: "mlx-swift", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "MLXLinalg", package: "mlx-swift", condition: .when(platforms: [.macOS, .iOS])),
                // Swift Embeddings for fast Model2Vec
                .product(name: "Embeddings", package: "swift-embeddings"),
            ],
            path: "Sources/ZoniApple"
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

        // Vapor integration tests
        .testTarget(
            name: "ZoniVaporTests",
            dependencies: [
                "ZoniVapor",
                .product(name: "XCTVapor", package: "vapor"),
            ],
            path: "Tests/ZoniVaporTests"
        ),

        // Hummingbird integration tests
        .testTarget(
            name: "ZoniHummingbirdTests",
            dependencies: [
                "ZoniHummingbird",
                .product(name: "HummingbirdTesting", package: "hummingbird"),
            ],
            path: "Tests/ZoniHummingbirdTests"
        ),

        // Apple platform extension tests (Phase 5B)
        .testTarget(
            name: "ZoniAppleTests",
            dependencies: ["ZoniApple"],
            path: "Tests/ZoniAppleTests"
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
