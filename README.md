# swift-sprite

2D Swift Sprite Engine

Pure-Swift, prefix-free 2D rendering for Linux, macOS, and iOS. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design and roadmap.

## Modules

| Module | Description |
| --- | --- |
| `SpriteCore` | 2D math (`Matrix3x3`, `Transform2D`, `Rect`, `Color`), `Texture`, `TextureAtlas`, `SpriteBatcher`, and the `SpriteRenderBackend` protocol. No platform dependencies. |
| `SpriteGraph` | Scene tree: `Scene` (scale modes, `Duration`-driven update loop), `Node` (`@Node2DBuilder`), `Sprite` (9-patch `centerRect`), `Label` (bitmap / SDF `BitmapFont`), `Camera`, and composable value-type `Action`s. |
| `SpriteSDL` | SDL3 window, input events, and `SDLRenderBackend` batch renderer. |
| `sprite-viewer` | SDL3 demo and inspector for scenes and the batch renderer. |

## Requirements

- Swift 6.4
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
