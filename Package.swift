// swift-tools-version: 6.4
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
]

let package = Package(
    name: "swift-sprite",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "SpriteCore",
            targets: ["SpriteCore"]
        ),
        .library(
            name: "SpriteGraph",
            targets: ["SpriteGraph"]
        ),
        .library(
            name: "SpritePhysics",
            targets: ["SpritePhysics"]
        ),
        .library(
            name: "SpriteFormats",
            targets: ["SpriteFormats"]
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
    dependencies: [
        .package(url: "https://github.com/PureSwift/swift-png.git", from: "0.2.0"),
        .package(url: "https://github.com/PureSwift/SDL.git", from: "3.3.0"),
    ],
    targets: [
        // Pure Swift: 2D math, textures, atlases, quad batching and render backend protocol.
        .target(
            name: "SpriteCore",
            swiftSettings: swiftSettings
        ),
        // System module map for the Box2D v3 C library.
        .systemLibrary(
            name: "CBox2D",
            pkgConfig: "box2d",
            providers: [
                .brew(["box2d"]),
            ]
        ),
        // 2D rigid-body physics backed by Box2D: bodies, shapes, joints, contacts and ray casts.
        .target(
            name: "SpritePhysics",
            dependencies: ["SpriteCore", "CBox2D"],
            swiftSettings: swiftSettings
        ),
        // Scene tree: Scene, Node, Sprite, Label, Camera, Action and ParticleEmitter.
        .target(
            name: "SpriteGraph",
            dependencies: ["SpriteCore", "SpritePhysics"],
            swiftSettings: swiftSettings
        ),
        // Asset codecs: PNG, texture atlases, sprite sheets, tile maps and scene archives.
        .target(
            name: "SpriteFormats",
            dependencies: [
                "SpriteCore",
                "SpriteGraph",
                .product(name: "PNG", package: "swift-png"),
            ],
            swiftSettings: swiftSettings
        ),
        // SDL3 windowing, input and batch renderer backend.
        .target(
            name: "SpriteSDL",
            dependencies: ["SpriteCore", .product(name: "SDL3Swift", package: "SDL")],
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "sprite-viewer",
            dependencies: ["SpriteCore", "SpriteGraph", "SpritePhysics", "SpriteSDL", "SpriteFormats",
                .product(name: "SDL3Swift", package: "SDL")],
            path: "Tools/sprite-viewer",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpriteCoreTests",
            dependencies: ["SpriteCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpritePhysicsTests",
            dependencies: ["SpritePhysics"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpriteFormatsTests",
            dependencies: ["SpriteFormats"],
            resources: [
                .copy("Fixtures"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpriteGraphTests",
            dependencies: ["SpriteGraph"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpriteSDLTests",
            dependencies: ["SpriteSDL", .product(name: "SDL3Swift", package: "SDL")],
            swiftSettings: swiftSettings
        ),
    ]
)
