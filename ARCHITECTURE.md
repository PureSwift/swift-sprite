# Pure-Swift 3D & 2D Engine Architecture (`swift-scene` & `swift-sprite`)

## Overview

Two decoupled, 100% pure-Swift repositories provide modern, prefix-free, idiomatic Swift APIs for 3D and 2D rendering, physics, and asset codecs across Linux, macOS, and iOS—while serving as the underlying engines for **Perry**'s `SceneKit`, `QuickDraw 3D`, and `SpriteKit` compatibility layers.

- **`swift-scene`**: Unified 3D monorepo porting `PerryUIKit/SceneKit.swift` and **Quesa** (`jwwalker/quesa`) into pure Swift, paired with a RealityKit-inspired ECS (`SceneReality`) and pure-Swift OpenUSD/USDZ support (`SceneUSD`).
- **`swift-sprite`**: Standalone 2D monorepo providing batch-rendered sprites, tile maps, particle systems, and 2D rigid-body physics with zero coupling to `swift-scene`.
- **`Perry` Integration**: Thin Objective-C/Swift ABI shims (`PerrySceneKit`, `PerrySpriteKit`, and QD3D symbol exports) that delegate to `swift-scene` and `swift-sprite` and handle cross-engine FBO texture interop locally inside Perry.

---

## 1. `swift-scene` (3D Monorepo)

### Repository Structure

```text
swift-scene/
├── Package.swift
├── README.md
├── Sources/
│   ├── SceneCore/            # Pure Swift: simd math, sparse-set ECS, FrameGraph, PBR/Phong shaders, RenderBackend
│   ├── SceneGraph/           # Idiomatic 3D scene tree (Scene, Node, Mesh, Material, Light, Camera, Action, ImmediateContext)
│   ├── SceneReality/         # Idiomatic ECS API (World, Entity, Component, System, ModelEntity, WorldRenderer)
│   ├── SceneFormats/         # Pure-Swift codecs: 3DMF (ported from Quesa), .scn, .dae, .obj, .glTF 2.0
│   ├── SceneUSD/             # Pure-Swift .usda / .usdc / .usdz stage parser, writer & MaterialX bridge
│   ├── ScenePhysics/         # Pure-Swift rigid-body dynamics & BVH collision detection
│   └── SceneSDL/             # SDL3 windowing, input, and OpenGL 3.3 / GLES 3.0 / Vulkan backend
├── Tools/
│   ├── scene-convert/        # CLI converter: .3dmf <-> .scn <-> .gltf <-> .usdz
│   └── scene-viewer/         # Cross-platform SDL3 scene & format inspector
└── Tests/
    ├── SceneCoreTests/
    ├── SceneGraphTests/
    ├── SceneRealityTests/
    ├── SceneFormatsTests/
    └── SceneUSDTests/
```

### Module Responsibilities

| Module | Role & Key Types | Origin / Porting Notes |
| --- | --- | --- |
| **`SceneCore`** | `EntityID`, `ComponentStorage`, `Transform`, `BoundingBox`, `MeshBuffer`, `MaterialDescriptor`, `RenderBackend`, `FrameCommandBuffer` | Data-oriented core shared by `SceneGraph` and `SceneReality`. Standardizes on right-handed Y-up `simd` math with row/column-major adapters. |
| **`SceneGraph`** | `Scene`, `Node`, `Mesh`, `Box`, `Sphere`, `NURBSPatch`, `TriMesh`, `Material`, `Light`, `Camera`, `Action`, `Transaction`, `ImmediateContext`, `SceneRenderer` | Pure-Swift port of `PerryUIKit/SceneKit.swift` (prefix-free) combined with Quesa's immediate-mode `TQ3View` state stack and NURBS tessellators. |
| **`SceneReality`** | `World`, `Entity`, `ModelEntity`, `AnchorEntity`, `Component` (`@Component`), `System`, `SimpleMaterial`, `PhysicallyBasedMaterial`, `EnvironmentResource`, `WorldRenderer` | Native ECS API mapped 1:1 onto `SceneCore`'s sparse-set component storage and PBR/IBL pipeline. |
| **`SceneFormats`** | `Metafile3D` (`.3dmf`), `SceneArchive` (`.scn`), `ColladaDecoder` (`.dae`), `GLTFDecoder` (`.gltf`/`.glb`), `WavefrontDecoder` (`.obj`) | Pure-Swift port of Quesa's `E3FFR_3DMF_Bin` and `E3FFR_3DMF_Text` parsers/writers alongside modern asset decoders. |
| **`SceneUSD`** | `USDStage`, `USDPrim`, `USDLayer`, `USDZipArchive` (`.usda`, `.usdc`, `.usdz`) | Pure-Swift ASCII lexer, Crate binary reader, and uncompressed ZIP package codec populating `SceneReality` or `SceneGraph`. |
| **`ScenePhysics`** | `PhysicsWorld`, `PhysicsBody`, `CollisionShape`, `PhysicsJoint` | Pure-Swift rigid-body solver and raycast engine backing both `SceneGraph` and `SceneReality`. |
| **`SceneSDL`** | `SDLWindow`, `SDLRenderBackend` | Thin SDL3 host rendering `SceneRenderer` / `WorldRenderer` framebuffers via OpenGL/GLES or Vulkan. |

### `swift-scene` Execution Phases

1. **Phase 1 — Bootstrap & `SceneCore`**: Set up Swift 6 package manifest, `simd` math, row/column-major transform adapters, sparse-set ECS storage, and `RenderBackend` protocols.
2. **Phase 2 — `SceneGraph` Extraction**: Migrate `PerryUIKit/SceneKit.swift` into `SceneGraph` without `SCN` prefixes; convert `PerryUIKit` into a thin `@objc` ABI shim.
3. **Phase 3 — Quesa Pure-Swift Port**: Port Quesa's `ImmediateContext` state stack, `AttributeSet` overrides, `NURBSPatch` / `Ellipsoid` evaluators, and binary/text `3DMF` codec (`SceneFormats/ThreeDMF`).
4. **Phase 4 — Standard Codecs & `SceneSDL`**: Implement `.obj`, `.gltf`/`.glb`, `.dae`, and `.scn` decoders plus `SDLRenderBackend` and `scene-viewer`.
5. **Phase 5 — `SceneReality` & `SceneUSD`**: Implement the ECS API (`Entity`, `Component`, `System`, `WorldRenderer`), `.usda`/`.usdc`/`.usdz` support, and `scene-convert`.

---

## 2. `swift-sprite` (2D Monorepo)

### Repository Structure

```text
swift-sprite/
├── Package.swift
├── README.md
├── Sources/
│   ├── SpriteCore/           # Pure Swift: 2D simd math, SpriteBatcher, Texture, TextureAtlas, SpriteRenderBackend
│   ├── SpriteGraph/          # Idiomatic 2D scene tree: Scene, Node, Sprite, Shape, Label, TileMap, Camera, Action, ParticleEmitter
│   ├── SpritePhysics/        # Pure-Swift 2D impulse rigid-body solver, joints, raycasts & OptionSet collision masks
│   ├── SpriteFormats/        # Pure-Swift codecs: .atlas, Tiled (.tmx / .tsx), Aseprite (.json), .sks archives
│   └── SpriteSDL/            # SDL3 windowing, touch/gamepad/mouse input, OpenGL/GLES/Vulkan 2D batch renderer
├── Tools/
│   └── sprite-viewer/        # Cross-platform SDL3 2D scene, atlas & particle inspector
└── Tests/
    ├── SpriteCoreTests/
    ├── SpriteGraphTests/
    ├── SpritePhysicsTests/
    └── SpriteFormatsTests/
```

### Idiomatic API Mapping

| Legacy SpriteKit | `swift-sprite` (`SpriteGraph` / `SpritePhysics`) | Notes |
| --- | --- | --- |
| `SKScene` | `Scene` | Value-based `ScaleMode` (`.aspectFill`, `.aspectFit`, `.resizeFill`) and `Duration`-driven update loop. |
| `SKNode` | `Node` | Declarative `@Node2DBuilder` composition, `zPosition` sorting, and `SIMD2<Float>` transforms. |
| `SKSpriteNode` | `Sprite` | 9-patch `centerRect` slicing, anchor points, color blending, and 2D normal-map lighting. |
| `SKTexture` / `SKTextureAtlas` | `Texture`, `TextureAtlas` | `Sendable` texture handles with UV sub-rects and async atlas loading. |
| `SKAction` | `Action` | Value-type composable animations (`.sequence`, `.group`, `.repeatForever`) with `Duration` timing. |
| `SKTileMapNode` / `SKTileSet` | `TileMap`, `TileSet` | Chunked quad-buffer tile rendering supporting `.tmx` and `.sks` tile maps. |
| `SKEmitterNode` | `ParticleEmitter` | Contiguous Structure-of-Arrays (SOA) particle simulation with configurable emission ramps. |
| `SKPhysicsWorld` / `SKPhysicsBody` | `PhysicsWorld`, `PhysicsBody` | Type-safe `OptionSet` collision categories and closure/async contact notifications. |
| `SKLabelNode` | `Label` | Signed-distance-field (SDF) / bitmap glyph batching for resolution-independent text. |

### `swift-sprite` Execution Phases

1. **Phase 1 — `SpriteCore` + `SpriteSDL` Batch Renderer**: Build the `zPosition`/texture-sorted quad batcher, `simd_float3x3` transform hierarchy, and `TextureAtlas` loader.
2. **Phase 2 — `SpriteGraph` Core**: Implement `Scene`, `Node`, `Sprite` (with 9-patch slicing), `Camera`, `Action`, and SDF/bitmap `Label`.
3. **Phase 3 — `SpritePhysics` & `ParticleEmitter`**: Implement the 2D rigid-body impulse solver, joints, raycasts, and SOA particle simulator.
4. **Phase 4 — `SpriteFormats`**: Implement `.atlas`, Tiled `.tmx`/`.tsx`, Aseprite `.json`, and binary plist `.sks` archive decoders.

---

## 3. Perry Compatibility & Cross-Engine Interop

`swift-scene` and `swift-sprite` remain completely independent of each other. All Objective-C/C ABI compatibility and 2D/3D texture sharing live inside **Perry**:

```text
┌──────────────────────────────────────────────────────────────────────┐
│                         Perry (Mach-O Loader)                        │
│                                                                      │
│  ┌──────────────────────────────┐  ┌──────────────────────────────┐  │
│  │   PerrySceneKit & C-QD3D     │  │       PerrySpriteKit         │  │
│  │ (SCNNode, SCNScene, Q3* ABI) │  │ (SKNode, SKScene, SKView)    │  │
│  └──────────────┬───────────────┘  └──────────────┬───────────────┘  │
│                 │         ▲              ▲        │                  │
│                 │         └──────┬───────┘        │                  │
│                 │     (Perry-only FBO/texture     │                  │
│                 │      interop: SKScene inside    │                  │
│                 │      SCNMaterial & SK3DNode)    │                  │
└─────────────────┼────────────────┼────────────────┼──────────────────┘
                  ▼                │                ▼
        ┌───────────────────┐      │      ┌───────────────────┐
        │    swift-scene    │      │      │   swift-sprite    │
        └───────────────────┘      │      └───────────────────┘
                                   └─ Zero cross-repo dependency
```

- **`PerrySceneKit`**: Exposes `@objc` `SCN*` classes and `Q3*` C ABI entry points backed by `SceneGraph` and `SceneFormats`.
- **`PerrySpriteKit`**: Exposes `@objc` `SK*` classes backed by `SpriteGraph`, `SpritePhysics`, and `SpriteFormats`.
- **Perry-Local Interop**:
  - `SCNMaterialProperty.contents = skScene`: Renders the `SpriteGraph.Scene` to an offscreen FBO texture and binds that texture ID to `SceneGraph.Material`.
  - `SK3DNode`: Renders a `SceneGraph.Scene` to an offscreen FBO texture and displays it as a `SpriteGraph.Sprite` quad in the 2D scene tree.
