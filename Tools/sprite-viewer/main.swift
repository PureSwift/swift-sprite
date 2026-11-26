//
//  main.swift
//  sprite-viewer
//
//  Phase 1 smoke test: renders a procedurally generated atlas through
//  `SpriteBatcher` and `SDLRenderBackend`.
//
//  Controls: click to spawn sprites, space toggles texture-grouped sorting, escape quits.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import CSDL3
import SpriteCore
import SpriteSDL

/// Generates a checkerboard tile with the given colors.
func checkerboard(size: Int, cell: Int, _ a: Color, _ b: Color) -> PixelBuffer {
    var buffer = PixelBuffer(width: size, height: size)
    for y in 0 ..< size {
        for x in 0 ..< size {
            buffer[x, y] = ((x / cell) + (y / cell)).isMultiple(of: 2) ? a : b
        }
    }
    return buffer
}

/// Generates a soft radial dot, useful for additive particles.
func radialDot(size: Int) -> PixelBuffer {
    var buffer = PixelBuffer(width: size, height: size)
    let center = Float(size) / 2
    for y in 0 ..< size {
        for x in 0 ..< size {
            let d = (Vector2(Float(x) + 0.5, Float(y) + 0.5) - center) / center
            let falloff = max(0, 1 - (d * d).sum().squareRoot())
            buffer[x, y] = Color(white: 1, alpha: falloff * falloff)
        }
    }
    return buffer
}

struct Spinner {
    var position: Vector2
    var velocity: Vector2
    var rotation: Float
    var spin: Float
    var textureName: String
    var zPosition: Float
}

let window = try SDLWindow(title: "sprite-viewer", width: 960, height: 640)
let backend = SDLRenderBackend(window: window)

let atlas = try TextureAtlas.make(
    images: [
        "orange": checkerboard(size: 64, cell: 8, Color(rgba: 0xF2_8C_28_FF), Color(rgba: 0xFF_D1_66_FF)),
        "teal": checkerboard(size: 48, cell: 12, Color(rgba: 0x1F_9E_89_FF), Color(rgba: 0x9A_E3_D5_FF)),
        "violet": checkerboard(size: 32, cell: 4, Color(rgba: 0x6A_4C_93_FF), Color(rgba: 0xC9_B6_E4_FF)),
        "dot": radialDot(size: 32),
    ],
    backend: backend,
    filtering: .nearest
)

var batcher = SpriteBatcher()
var spinners = [Spinner]()
let names = ["orange", "teal", "violet"]

@MainActor func spawn(at position: Vector2) {
    spinners.append(Spinner(
        position: position,
        velocity: Vector2(Float.random(in: -120 ... 120), Float.random(in: -120 ... 120)),
        rotation: 0,
        spin: Float.random(in: -3 ... 3),
        textureName: names.randomElement()!,
        zPosition: Float(Int.random(in: 0 ... 2))
    ))
}

let initialSize = backend.drawableSize
for _ in 0 ..< 200 {
    spawn(at: Vector2(Float.random(in: 0 ... initialSize.x), Float.random(in: 0 ... initialSize.y)))
}

var running = true
var lastTicks = SDL_GetTicksNS()
var frameCount = 0
var fpsTimer: Float = 0

while running {
    let size = backend.drawableSize

    for event in window.pollEvents() {
        switch event {
        case .quit, .keyDown(.escape, _):
            running = false
        case .keyDown(.space, isRepeat: false):
            batcher.sortMode = batcher.sortMode == .preserveOrder ? .textureGrouped : .preserveOrder
        case let .mouseDown(_, point):
            // Event coordinates are Y-down; the world is Y-up.
            let world = Vector2(point.x, size.y - point.y)
            for _ in 0 ..< 20 { spawn(at: world) }
        default:
            break
        }
    }

    let now = SDL_GetTicksNS()
    let dt = Float(now - lastTicks) / 1_000_000_000
    lastTicks = now

    for i in spinners.indices {
        spinners[i].position += spinners[i].velocity * dt
        spinners[i].rotation += spinners[i].spin * dt
        // Bounce off the edges.
        for axis in 0 ..< 2 where spinners[i].position[axis] < 0 || spinners[i].position[axis] > size[axis] {
            spinners[i].velocity[axis] = -spinners[i].velocity[axis]
            spinners[i].position[axis] = min(max(spinners[i].position[axis], 0), size[axis])
        }
    }

    for spinner in spinners {
        let transform = Transform2D(position: spinner.position, rotation: spinner.rotation)
        batcher.submit(SpriteQuad(
            texture: atlas[spinner.textureName]!,
            transform: transform.matrix,
            zPosition: spinner.zPosition
        ))
        // Additive glow drawn above every sprite.
        batcher.submit(SpriteQuad(
            texture: atlas["dot"]!,
            transform: Transform2D(position: spinner.position, scale: Vector2(2, 2)).matrix,
            color: Color(red: 1, green: 0.8, blue: 0.5, alpha: 0.25),
            zPosition: 10,
            blendMode: .add
        ))
    }

    let frame = batcher.makeFrame(viewTransform: .viewport(size: size))
    try backend.render(frame, clearColor: Color(rgba: 0x1B_1D_23_FF))

    frameCount += 1
    fpsTimer += dt
    if fpsTimer >= 1 {
        let mode = batcher.sortMode == .preserveOrder ? "preserveOrder" : "textureGrouped"
        window.title = "sprite-viewer — \(spinners.count) sprites, \(frame.batches.count) batches, \(frameCount) fps, \(mode)"
        frameCount = 0
        fpsTimer = 0
    }
}
