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
        // Server-side extensions (Vapor integration, OpenAI client, etc.)
        .library(
            name: "ZoniServer",
            targets: ["ZoniServer"]
        ),
        // Apple platform extensions (NaturalLanguage, Accelerate, etc.)
        .library(
            name: "ZoniApple",
            targets: ["ZoniApple"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0"),
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.20.0"),
    ],
    targets: [
        // Core target with document loading
        .target(
            name: "Zoni",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
            ],
            path: "Sources/Zoni"
        ),
        // Server extensions
        .target(
            name: "ZoniServer",
            dependencies: ["Zoni"],
            path: "Sources/ZoniServer"
        ),
        // Apple platform extensions
        .target(
            name: "ZoniApple",
            dependencies: ["Zoni"],
            path: "Sources/ZoniApple"
        ),
        // Tests
        .testTarget(
            name: "ZoniTests",
            dependencies: ["Zoni"],
            path: "Tests/ZoniTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
