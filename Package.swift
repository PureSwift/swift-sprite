// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
]

let package = Package(
    name: "swift-sprite",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "SpriteCore",
            targets: ["SpriteCore"]
        ),
        .library(
            name: "SpriteSDL",
            targets: ["SpriteSDL"]
        ),
        .executable(
            name: "sprite-viewer",
            targets: ["sprite-viewer"]
        ),
    ],
    targets: [
        // Pure Swift: 2D math, textures, atlases, quad batching and render backend protocol.
        .target(
            name: "SpriteCore",
            swiftSettings: swiftSettings
        ),
        // System module map for the SDL3 C library.
        .systemLibrary(
            name: "CSDL3",
            pkgConfig: "sdl3",
            providers: [
                .brew(["sdl3"]),
                .apt(["libsdl3-dev"]),
            ]
        ),
        // SDL3 windowing, input and batch renderer backend.
        .target(
            name: "SpriteSDL",
            dependencies: ["SpriteCore", "CSDL3"],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "sprite-viewer",
            dependencies: ["SpriteCore", "SpriteSDL"],
            path: "Tools/sprite-viewer",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpriteCoreTests",
            dependencies: ["SpriteCore"],
            swiftSettings: swiftSettings
        ),
    ]
)
