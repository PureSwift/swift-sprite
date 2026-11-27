# swift-sprite

2D Swift Sprite Engine

Pure-Swift, prefix-free 2D rendering for Linux, macOS, and iOS. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design and roadmap.

## Modules

| Module | Description |
| --- | --- |
| `SpriteCore` | 2D math (`Matrix3x3`, `Transform2D`, `Rect`, `Color`), `Texture`, `TextureAtlas`, `SpriteBatcher`, and the `SpriteRenderBackend` protocol. No platform dependencies. |
| `SpriteGraph` | Scene tree: `Scene` (scale modes, `Duration`-driven update loop, `physicsWorld`), `Node` (`@Node2DBuilder`, `physicsBody`), `Sprite` (9-patch `centerRect`), `Label` (bitmap / SDF `BitmapFont`), `Camera`, `ParticleEmitter` (structure-of-arrays simulation, keyframe sequences), `TileMap` / `TileSet` (editable grids with cached quad chunks), and composable value-type `Action`s. |
| `SpritePhysics` | Swift API over [Box2D](https://box2d.org) v3: `PhysicsWorld`, `PhysicsBody`, `PhysicsShape`, `PhysicsCategory` masks, contact/sensor notifications, ray casts, and pin / fixed / distance / spring joints. |
| `SpriteFormats` | PNG decoding via [swift-png](https://github.com/PureSwift/swift-png), SpriteKit `.atlas` / `.atlasc`, libGDX / Spine `.atlas`, Aseprite JSON sprite sheets with tag animations and 9-patch slices, finite orthogonal Tiled `.tmx` / `.tsx` maps, and an initial SpriteKit `.sks` scene archive reader using Foundation. |
| `SpriteSDL` | SDL3 window, input events, and batch rendering through [PureSwift/SDL](https://github.com/PureSwift/SDL)'s `SDL3Swift` product (3.3.0+). |
| `sprite-viewer` | SDL3 demo and inspector for scenes and the batch renderer. |

## Requirements

- Swift 6.4, macOS 15 / iOS 18 or Linux (the primary target)
- zlib for PNG decoding (swift-png's default `SystemZlib` trait; `apt install zlib1g-dev` on Linux)
- Box2D 3.x for `SpritePhysics` (and `SpriteGraph`)
  - macOS: `brew install box2d`
  - Linux: build Box2D 3.x from source (distribution packages are still 2.4)
- SDL3 for `SpriteSDL` and `sprite-viewer`
  - macOS: `brew install sdl3`
  - Linux: `apt install libsdl3-dev`

## Usage

### Scene graph

```swift
import SpriteGraph
import SpriteSDL

let window = try SDLWindow(title: "Demo", width: 800, height: 600)
let backend = SDLRenderBackend(window: window)
let font = try BitmapFont.debug(backend: backend)

let scene = Scene(size: [800, 600])
scene.scaleMode = .aspectFit
scene.addChildren {
    Label(text: "HELLO", font: font, fontSize: 40)
    Sprite(color: .red, size: [64, 64])
}
scene.children[1].run(.repeatForever(.sequence([
    .move(by: [200, 0], duration: .seconds(1)),
    .move(by: [-200, 0], duration: .seconds(1)),
]).timingMode(.easeInEaseOut)))

try scene.present(on: backend, deltaTime: .milliseconds(16))
```

### Physics & particles

```swift
scene.physicsBody = PhysicsBody(edgeLoopFrom: Rect(x: 0, y: 0, width: 800, height: 600))

let crate = Sprite(texture: crateTexture)
crate.physicsBody = PhysicsBody(rectangleOf: crate.size)
crate.physicsBody?.contactTestBitMask = .all
scene.addChild(crate)

scene.physicsWorld.onContactBegin = { contact in
    let sparks = ParticleEmitter()
    sparks.position = contact.contactPoint
    sparks.particleTexture = sparkTexture
    sparks.particleBirthRate = 1000
    sparks.numParticlesToEmit = 20
    sparks.emissionAngleRange = 2 * .pi
    sparks.particleSpeed = 200
    sparks.particleAlphaSequence = KeyframeSequence([(0, 1), (1, 0)])
    scene.addChild(sparks)
}
```

### Asset loading

```swift
import SpriteFormats

// Decoding runs off the main actor; uploading uses the backend.
let atlases = try await SpriteKitAtlas.decode(at: url.appending(path: "Characters.atlasc"))
    .makeTextureAtlases(backend: backend)
let hero = Sprite(texture: atlases[texture: "hero"]!)

let (sheet, decoded) = try await AsepriteSheet.decode(at: url.appending(path: "hero.json"))
let atlas = try decoded.makeTextureAtlases(backend: backend)[0]
hero.run(.repeatForever(sheet.animation(tag: "walk", atlas: atlas)!))
```

### Tile maps

```swift
import SpriteFormats

let map = try await TiledMap.decode(at: mapURL)
let root = try map.makeNode(backend: backend)
scene.addChild(root)

// TileMap coordinates are Y-up, with row zero at the bottom.
if let ground = root.children.first as? TileMap {
    ground[0, 0] = nil
    let center = ground.centerOfTile(column: 1, row: 1)
}
```

The initial Tiled loader supports finite orthogonal maps with right-down render order,
uncompressed CSV layers, inline or external TSX tilesets, PNG sheets, margin/spacing,
all eight flip combinations, and layer names, visibility, opacity, and pixel offsets.
Tileset tile dimensions must match the map grid. Infinite maps, other orientations,
compressed/base64 data, groups, object/image layers, per-tile metadata/animation,
tile offsets, transparency keys, and layer tint/parallax are not supported and produce errors.
Editor metadata and custom properties are ignored.

Each map caches local quads in 16×16 chunks; editing a cell invalidates its chunk.
The existing batcher still constructs frame vertices each frame; viewport culling and
persistent GPU chunk buffers are future work. Textures remain owned by the backend.

Preview the included fixture from the repository root:

```sh
swift run sprite-viewer --tmx Tests/SpriteFormatsTests/Fixtures/Tiled/sample.tmx
```

### SpriteKit scene archives

```swift
let archive = try await SpriteKitSceneArchive.decode(at: sceneURL)
let root = try archive.makeNode(
    textureResolver: { reference in textures[reference.imageName] },
    fontResolver: { name in fonts[name] }
)
```

Foundation's `PropertyListSerialization` reads binary and XML keyed archives.
The loader maps `SKScene`, `SKNode`, `SKSpriteNode`, `SKCameraNode`, `SKLabelNode`, `SKEmitterNode`, and `SKTileMapNode`
to engine nodes, preserving child order, transforms, opacity, visibility, scene settings,
camera identity, sprite geometry/tint, and label layout. A root `Scene` can be presented
directly; other root nodes can be attached to an existing scene.

Applications supply named texture and bitmap/SDF font resolvers; missing resources throw
explicit errors. Texture references include image, atlas, subtexture, and filtering information.
Resolvers return the named image or atlas entry before the archive's unit-rectangle crop.
Returned textures remain owned by the application's backend.

Named `SKReferenceNode` instances use an explicit archive resolver:

```swift
let root = try archive.makeNode(
    textureResolver: { textures[$0.imageName] },
    referenceResolver: { archivesByReferenceName[$0] }
)
```

`referenceNames` lists direct references. Names are passed through unchanged (some
include `.sks`); the loader never opens referenced files automatically. Each instance
gets independent nodes and actions. Referenced scene roots become plain nodes under
the reference wrapper; their scene-only background, camera selection, and physics-world
settings do not replace the containing scene's settings. Resource caches are shared
across the expanded tree. Missing references, cycles, more than 31 nested reference
levels, and expansions beyond 100,000 nodes throw errors. URL-based references and
physics bodies under scaled reference hierarchies remain unsupported.

This is an initial archive subset tested against fixtures generated with macOS SpriteKit,
not a guarantee of compatibility with every Xcode editor or OS archive version.
Custom/unknown node classes, constraints, effects, lighting,
attributed labels, embedded image data, and rotated/trimmed textures are unsupported.
User data is omitted with entries in `diagnostics`.
Circle, rectangle, convex counterclockwise polygon, and compound physics bodies are restored with
local centers, mass, friction, restitution, damping, velocity, dynamic/gravity/rotation
flags, and all 32 bits of collision/contact masks. Scene gravity and simulation speed
are imported. SpriteKit density is converted from kilograms per square meter to the
engine's per-square-point density using SpriteKit's 150 points per meter; gravity is
converted to points per second squared using the same scale. Linear velocity remains
in points per second. Imported scenes use the existing Box2D solver and fixed timestep;
this does not promise identical SpriteKit simulation results.

Compound bodies support archived circles and convex polygon components, including their
local offsets; polygon components are converted from meters to points. Loading is limited
to 256 components and 4,096 polygon vertices per compound body.

Edge segments, chains, and loops load as static, two-sided collision boundaries, even
when the archive's dynamic flag is set. Edge paths support up to 1,025 straight-line
points and may be concave; zero-length segments are rejected. Loops connect the final
point to the first, while chains preserve their archived endpoints.

The archived precise-collision flag maps to `PhysicsBody.usesContinuousCollisionDetection`.
This enables Box2D bullet sweeps against non-bullet dynamic bodies and can be changed
while a body is in a world. Static collisions already use continuous detection; sensors
and bullet-to-bullet pairs are excluded. This reduces tunneling without guaranteeing
SpriteKit's collision timing or preventing every missed collision.

Unsupported texture-derived geometry, curved paths, nonconvex volume polygons, joints, pinned bodies,
charged bodies, and physics bodies under scaled nodes are
currently rejected. Field masks and internal collision skin radii are not imported;
field nodes are unsupported and the engine uses its own collision geometry. Physics
fixtures cover binary/XML decoding and simulation without requiring SpriteKit at test time.

Archived actions support relative/absolute movement (including single-axis movement),
Z rotation, two-axis scaling, fading, waits, hide/unhide, removal, sequences, groups,
finite repeats, repeat-forever, `SKAnimate` texture flipbooks, and `SKPlaySound` callbacks. The ordered action list and keys are restored without
duplicating keyed actions. Each `makeNode()` creates independent playback state, and
standard timing modes use the engine's easing curves.

Actions start from their archived descriptions. Reversed actions, detectable partially
executed state, retimed composites/flipbooks, single-axis/size-based scaling, color/resize
animations, paths, archived executable callbacks, and custom classes are unsupported. Native fixtures
do not encode action speed; omitted runtime state cannot be recovered. Node speed and
pause settings still apply. This is not a snapshot/resume mechanism for running games.

Texture flipbooks resolve every frame through the scene texture resolver and shared
cache, including atlas subrects. They support uniform frame timing, optional resizing,
and restoration on completion or cancellation, including keyed replacement and nested
actions. Only animations that have started and are still active restore their texture.
Editor archives may save scenes and sprites paused; unpause the desired
nodes explicitly to start playback.

Sound actions require an explicit host playback resolver:

```swift
let root = try archive.makeNode(
    textureResolver: { textures[$0.imageName] },
    soundResolver: { playbackCallbacks[$0] } // [String: Action.Block]
)
```

The resolver prepares a main-actor playback callback; it does not start audio. The
callback receives the running node when the action begins and is called once per
repeat. Missing callbacks throw `missingSound`. Resolution is cached by filename
across the expanded scene. Named action libraries accept the same `soundResolver`.
Waiting actions use their archived duration; nonwaiting actions complete immediately.
This is action-clock timing, not an audio-device completion signal. Node/action speed
can change that timing without changing audio playback speed. The host owns audio
loading, output, and already-started playback; cancelling an action does not stop audio.
Nonzero archived sound positions are currently unsupported.

Standalone editor `Actions.sks` libraries can be loaded independently of a scene:

```swift
let library = try await SpriteKitActionArchive.decode(at: actionsURL)
if let pulse = try library.makeAction(named: "Pulse") {
    node.run(pulse, withKey: "pulse")
}
```

`actionNames` returns sorted names. `makeAction(named:textureResolver:)` returns nil
for an unknown name and resolves flipbook textures when needed, caching repeated
references within that call. Running the same action on different nodes creates
independent playback state. Libraries use the same supported action types and limits
as scene archives; unsupported entries reject the library during decoding.

Particle emitters restore birth rate/count, lifetime, spawn position/range, speed and
emission angle, acceleration, rotation, scale, opacity, color/blend factor, size, blend
mode, and particle Z position. Named particle textures use the same cached resolver as
sprites. Targets must reference a node in the imported tree. Alpha/scale keyframes
support linear interpolation with clamping. Standalone emitter archives are supported.

Linear, clamped color keyframes support archived `NSColor` RGB and grayscale values,
including alpha. The importer uses the stored RGB/white fallback directly; custom ICC
profiles are not color-managed. Other color classes and color spaces are unsupported.

A zero archived particle size uses the resolved texture dimensions, including atlas
subrects. Explicit sizes are preserved; zero size without a texture stays invisible.

Starting color-blend variance is supported: each particle samples the base factor
plus a random offset within half the range, then clamps it to `0...1`. The sampled
factor stays fixed for its lifetime; changes to the emitter affect future particles.

Per-channel color ranges/speeds, color-blend speeds/sequences, particle
actions, speed/rotation keyframes, fields, emission distance, and Z ranges/speeds are
currently unsupported. Imported emitters start with no live particles and retain the
engine's 10,000-live-particle cap; simulation is not intended to reproduce SpriteKit's
random particle stream exactly.

Grid tile maps restore dimensions, cell size, anchor, tint, transforms, and saved cell
placement. Empty cells, shared tile definitions, and definitions selected from multiple
rules are preserved. Embedded tile sets are decoded directly. For editor scenes that
reference a set by name, decode the companion archive and provide a resolver:

```swift
let sets = try await SpriteKitTileSetArchive.decode(at: tileSetsURL)
let root = try archive.makeNode(
    textureResolver: { reference in textures[reference.imageName] },
    tileSetResolver: { name in sets.first { $0.name == name } }
)
```

Tile definitions support static textures and looping texture arrays with a uniform
frame duration. Each map starts animations at frame zero; cells sharing a definition
stay synchronized, including newly placed cells. Playback follows scene and ancestor
pause/speed settings, and maps sharing a tile set maintain independent clocks. Native
maps can use `TileSet(textures:animations:)` with `TileAnimation` values as well.
Animated frames preserve texture subrects without rebuilding cached tile geometry.

Tile definitions must have no orientation flags or normal maps and the same size as
their map cells. Non-grid layouts are unsupported. The importer
uses the archived definition selection; it does not implement SpriteKit automatic
adjacency updates, weighted selection, or editor stamps. Tile-set metadata and custom
properties are not imported. The viewer accepts an explicit companion archive:

```sh
swift run sprite-viewer --sks Tests/SpriteFormatsTests/Fixtures/SceneArchives/tiles-external.sks --tilesets Tests/SpriteFormatsTests/Fixtures/SceneArchives/tilesets.sks
```

Other editor metadata is ignored. Binary UIDs are normalized through Foundation's XML
serialization without using private UID APIs or instantiating archived classes.

```sh
swift run sprite-viewer --sks Tests/SpriteFormatsTests/Fixtures/SceneArchives/scene.sks
```

The viewer loads loose PNGs relative to the archive and substitutes its built-in bitmap font.
The fixture generator is `Tests/SpriteFormatsTests/Fixtures/make_scene_fixtures.swift`
(macOS only); tests consume the checked-in archives and require no SpriteKit runtime.

### Tutorial compatibility assets

Download and extract **2D Apple Games by Tutorials, edition 3.0** from
[Kodeco's deprecated books](https://github.com/kodecocodes/deprecated-books):

```sh
python3 Scripts/download-tutorial.py
```

The script requires Python 3.8 or later. It caches the approximately 632 MiB ZIP in
`.build/tutorials/` and extracts it into `.build/tutorials/2d-apple-games-3/`.
It verifies a pinned SHA-256 checksum and checks key tile-map and particle archives.
Use `--archive PATH` to select the ZIP cache or `--destination PATH` to change the
extraction directory. Repeated runs reuse verified downloads and extracted samples.
The downloaded material remains outside version control and retains
[Kodeco's license](https://github.com/kodecocodes/deprecated-books/blob/master/LICENSE).

The **Tutorial assets** GitHub Actions workflow runs the script on pushes, pull
requests, and manual dispatches, including cache hits. This checks asset retrieval
and archive integrity; it does not claim that every tutorial scene is supported by
the engine.

### Batch renderer

```swift
import SpriteCore
import SpriteSDL

let window = try SDLWindow(title: "Demo", width: 800, height: 600)
let backend = SDLRenderBackend(window: window)
let texture = try backend.makeTexture(PixelBuffer(width: 32, height: 32, fill: .white), filtering: .nearest)

var batcher = SpriteBatcher(sortMode: .textureGrouped)
batcher.submit(SpriteQuad(
    texture: texture,
    transform: Transform2D(position: [400, 300], rotation: .pi / 4).matrix,
    color: .red
))
try backend.render(batcher.makeFrame(viewTransform: .viewport(size: backend.drawableSize)), clearColor: .black)
```

```sh
swift run sprite-viewer
swift test
```

### Screen blending

`BlendMode.screen` is supported for sprites and particles, including archived
SpriteKit screen blend modes. The SDL backend uses a custom blend mode with
premultiplied textures and vertex colors to preserve source transparency. It retains
CPU texture pixels and lazily caches a premultiplied GPU copy when a texture is first
used for screen blending; texture updates invalidate that copy. Renderers without
support for the custom blend factors throw an SDL error. The Metal path has been
checked locally; the software backend is not guaranteed to support this mode.
