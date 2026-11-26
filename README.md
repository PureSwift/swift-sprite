# swift-sprite

2D Swift Sprite Engine

Pure-Swift, prefix-free 2D rendering for Linux, macOS, and iOS. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design and roadmap.

## Modules

| Module | Description |
| --- | --- |
| `SpriteCore` | 2D math (`Matrix3x3`, `Transform2D`, `Rect`, `Color`), `Texture`, `TextureAtlas`, `SpriteBatcher`, and the `SpriteRenderBackend` protocol. No platform dependencies. |
| `SpriteGraph` | Scene tree: `Scene` (scale modes, `Duration`-driven update loop, `physicsWorld`), `Node` (`@Node2DBuilder`, `physicsBody`), `Sprite` (9-patch `centerRect`), `Label` (bitmap / SDF `BitmapFont`), `Camera`, `ParticleEmitter` (structure-of-arrays simulation, keyframe sequences), and composable value-type `Action`s. |
| `SpritePhysics` | Swift API over [Box2D](https://box2d.org) v3: `PhysicsWorld`, `PhysicsBody`, `PhysicsShape`, `PhysicsCategory` masks, contact/sensor notifications, ray casts, and pin / fixed / distance / spring joints. |
| `SpriteFormats` | PNG decoding via [swift-png](https://github.com/PureSwift/swift-png), SpriteKit `.atlas` / `.atlasc`, libGDX / Spine `.atlas`, and Aseprite JSON sprite sheets with tag animations and 9-patch slices. |
| `SpriteSDL` | SDL3 window, input events, and `SDLRenderBackend` batch renderer. |
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
