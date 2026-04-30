// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ZoniApple",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "ZoniApple",
            targets: ["ZoniApple"]
        ),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.18.0"),
        .package(url: "https://github.com/jkrukowski/swift-embeddings.git", from: "0.0.8"),
    ],
    targets: [
        .target(
            name: "ZoniApple",
            dependencies: [
                .product(name: "Zoni", package: "zoni"),
                .product(name: "MLX", package: "mlx-swift", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "MLXNN", package: "mlx-swift", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "MLXLinalg", package: "mlx-swift", condition: .when(platforms: [.macOS, .iOS])),
                .product(name: "Embeddings", package: "swift-embeddings"),
            ]
        ),
        .testTarget(
            name: "ZoniAppleTests",
            dependencies: [
                "ZoniApple",
                .product(name: "Zoni", package: "zoni"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
