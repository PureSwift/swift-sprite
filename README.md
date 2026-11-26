# swift-sprite

2D Swift Sprite Engine

Pure-Swift, prefix-free 2D rendering for Linux, macOS, and iOS. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full design and roadmap.

## Modules

| Module | Description |
| --- | --- |
| `SpriteCore` | 2D math (`Matrix3x3`, `Transform2D`, `Rect`, `Color`), `Texture`, `TextureAtlas`, `SpriteBatcher`, and the `SpriteRenderBackend` protocol. No platform dependencies. |
| `SpriteSDL` | SDL3 window, input events, and `SDLRenderBackend` batch renderer. |
| `sprite-viewer` | SDL3 demo and inspector for the batch renderer. |

## Requirements

- Swift 6.4
- SDL3 for `SpriteSDL` and `sprite-viewer`
  - macOS: `brew install sdl3`
  - Linux: `apt install libsdl3-dev`

## Usage

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
