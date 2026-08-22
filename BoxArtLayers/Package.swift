// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BoxArtLayers",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
    ],
    products: [
        .library(name: "BoxArtLayers", targets: ["BoxArtLayers"]),
        .executable(name: "boxart-layers", targets: ["BoxArtLayersCLI"]),
    ],
    targets: [
        .target(
            name: "BoxArtLayers",
            path: "Sources/BoxArtLayers"
        ),
        .executableTarget(
            name: "BoxArtLayersCLI",
            dependencies: ["BoxArtLayers"],
            path: "Sources/BoxArtLayersCLI"
        ),
        .testTarget(
            name: "BoxArtLayersTests",
            dependencies: ["BoxArtLayers"],
            path: "Tests/BoxArtLayersTests"
        ),
    ]
)
