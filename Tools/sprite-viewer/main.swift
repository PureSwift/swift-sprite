//
//  main.swift
//  sprite-viewer
//
//  Renders a SpriteGraph scene through SDLRenderBackend.
//
//  Controls:
//    click        spawn a burst of sprites
//    arrow keys   pan the camera
//    + / -        zoom the camera
//    space        toggle ignoresSiblingOrder (texture-grouped batching)
//    p            pause / resume
//    escape       quit
//

import CSDL3
import SpriteCore
import SpriteGraph
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

/// Generates a soft radial dot, useful for additive glows.
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

/// Generates a bordered panel suitable for 9-patch slicing (4 px border).
func panel(size: Int) -> PixelBuffer {
    var buffer = PixelBuffer(width: size, height: size, fill: Color(rgba: 0x10_12_18_D0))
    for y in 0 ..< size {
        for x in 0 ..< size {
            let edge = min(x, y, size - 1 - x, size - 1 - y)
            if edge < 2 {
                buffer[x, y] = Color(rgba: 0xF2_8C_28_FF)
            } else if edge < 4 {
                buffer[x, y] = Color(rgba: 0x5A_3A_1A_FF)
            }
        }
    }
    return buffer
}

final class DemoScene: Scene {

    let atlas: TextureAtlas
    let hud: Label
    let world = Node(name: "world")
    let cameraNode = Camera()
    let textureNames = ["orange", "teal", "violet"]

    private var fpsFrames = 0
    private var fpsElapsed: Double = 0
    private var fps = 0

    init(size: Vector2, atlas: TextureAtlas, font: BitmapFont) {
        self.atlas = atlas
        self.hud = Label(text: "", font: font, fontSize: 10)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = Color(rgba: 0x1B_1D_23_FF)

        addChild(world)
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.position = size * 0.5

        // HUD lives under the camera so it stays fixed on screen.
        let background = Sprite(texture: atlas["panel"]!)
        background.centerRect = Rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        background.anchorPoint = [0, 1]
        background.size = [300, 64]
        background.zPosition = 100
        background.name = "hud"
        hud.horizontalAlignmentMode = .left
        hud.verticalAlignmentMode = .top
        hud.position = [12, -12]
        hud.color = Color(rgba: 0xFF_E0_B0_FF)
        hud.lineSpacing = 4
        background.addChild(hud)
        cameraNode.addChild(background)
        didChangeSize(size)

        for _ in 0 ..< 150 {
            spawn(at: Vector2(Float.random(in: 0 ... size.x), Float.random(in: 0 ... size.y)), burst: false)
        }
    }

    /// Spawns a spinning sprite with a glow; bursts fade out and remove themselves.
    func spawn(at position: Vector2, burst: Bool) {
        let sprite = Sprite(texture: atlas[textureNames.randomElement()!]!)
        sprite.position = position
        sprite.zPosition = Float(Int.random(in: 0 ... 2))
        let glow = Sprite(texture: atlas["dot"]!)
        glow.scale = [2, 2]
        glow.color = Color(red: 1, green: 0.8, blue: 0.5, alpha: 0.25)
        glow.colorBlendFactor = 1
        glow.blendMode = .add
        glow.zPosition = 10
        sprite.addChild(glow)
        world.addChild(sprite)

        sprite.run(.repeatForever(.rotate(by: .pi * Float.random(in: -1 ... 1), duration: .seconds(1))))
        let drift = Vector2(Float.random(in: -1 ... 1), Float.random(in: -1 ... 1)) * 120
        if burst {
            sprite.scale = [0.2, 0.2]
            sprite.run(.sequence([
                .group([
                    .move(by: drift * 2, duration: .seconds(1.5)),
                    .scale(to: 1, duration: .milliseconds(300)).timingMode(.easeOut),
                    .sequence([.wait(for: .seconds(1)), .fadeOut(duration: .milliseconds(500))]),
                ]),
                .removeFromParent(),
            ]))
        } else {
            let wander = Action.sequence([
                .move(by: drift, duration: .seconds(2)),
                .move(by: -drift, duration: .seconds(2)),
            ]).timingMode(.easeInEaseOut)
            let pulse = Action.sequence([
                .scale(to: 1.25, duration: .milliseconds(400)),
                .scale(to: 1, duration: .milliseconds(400)),
            ]).timingMode(.easeInEaseOut)
            sprite.run(.repeatForever(wander))
            sprite.run(.repeatForever(.sequence([pulse, .wait(for: .seconds(1), withRange: .seconds(1))])))
        }
    }

    override func didChangeSize(_ oldSize: Vector2) {
        // Keep the HUD pinned to the top-left of the visible area.
        childNode(withName: "//hud")?.position = Vector2(-size.x / 2 + 12, size.y / 2 - 12)
    }

    override func update(_ deltaTime: Duration) {
        let (seconds, attoseconds) = deltaTime.components
        fpsElapsed += Double(seconds) + Double(attoseconds) * 1e-18
        fpsFrames += 1
        if fpsElapsed >= 1 {
            fps = fpsFrames
            fpsFrames = 0
            fpsElapsed = 0
        }
    }

    override func didFinishUpdate() {
        let sorting = ignoresSiblingOrder ? "GROUPED" : "ORDERED"
        hud.text = "\(fps) FPS  \(world.children.count) SPRITES\nZOOM \(Int(100 / cameraNode.xScale))%  \(sorting)\(isPaused ? "  PAUSED" : "")"
    }

    func handle(_ event: InputEvent) {
        switch event {
        case let .mouseDown(_, point):
            let position = convertPoint(fromView: point)
            for _ in 0 ..< 20 { spawn(at: position, burst: true) }
        case .keyDown(.space, isRepeat: false):
            ignoresSiblingOrder.toggle()
        case .keyDown(.character("p")!, isRepeat: false):
            isPaused.toggle()
        case .keyDown(.left, _):
            cameraNode.run(.move(by: [-80 * cameraNode.xScale, 0], duration: .milliseconds(150)))
        case .keyDown(.right, _):
            cameraNode.run(.move(by: [80 * cameraNode.xScale, 0], duration: .milliseconds(150)))
        case .keyDown(.up, _):
            cameraNode.run(.move(by: [0, 80 * cameraNode.xScale], duration: .milliseconds(150)))
        case .keyDown(.down, _):
            cameraNode.run(.move(by: [0, -80 * cameraNode.xScale], duration: .milliseconds(150)))
        case .keyDown(.character("=")!, _), .keyDown(.character("+")!, _):
            cameraNode.run(.scale(to: max(cameraNode.xScale / 1.25, 0.25), duration: .milliseconds(150)), withKey: "zoom")
        case .keyDown(.character("-")!, _):
            cameraNode.run(.scale(to: min(cameraNode.xScale * 1.25, 4), duration: .milliseconds(150)), withKey: "zoom")
        default:
            break
        }
    }
}

let window = try SDLWindow(title: "sprite-viewer", width: 960, height: 640)
let backend = SDLRenderBackend(window: window)

let atlas = try TextureAtlas.make(
    images: [
        "orange": checkerboard(size: 64, cell: 8, Color(rgba: 0xF2_8C_28_FF), Color(rgba: 0xFF_D1_66_FF)),
        "teal": checkerboard(size: 48, cell: 12, Color(rgba: 0x1F_9E_89_FF), Color(rgba: 0x9A_E3_D5_FF)),
        "violet": checkerboard(size: 32, cell: 4, Color(rgba: 0x6A_4C_93_FF), Color(rgba: 0xC9_B6_E4_FF)),
        "dot": radialDot(size: 32),
        "panel": panel(size: 16),
    ],
    backend: backend,
    filtering: .nearest
)

let scene = DemoScene(size: backend.drawableSize, atlas: atlas, font: try .debug(backend: backend))
var running = true
var lastTicks = SDL_GetTicksNS()

while running {
    for event in window.pollEvents() {
        if case .quit = event { running = false }
        if case .keyDown(.escape, _) = event { running = false }
        scene.handle(event)
    }
    let now = SDL_GetTicksNS()
    let deltaTime = Duration.nanoseconds(Int64(now - lastTicks))
    lastTicks = now
    try scene.present(on: backend, deltaTime: deltaTime)
    // Paused scenes skip `update`, so refresh the HUD directly.
    if scene.isPaused { scene.didFinishUpdate() }
}
