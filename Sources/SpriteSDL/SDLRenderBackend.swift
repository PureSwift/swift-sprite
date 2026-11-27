import SDL3Swift
import SpriteCore

/// Batched geometry rendered through PureSwift/SDL's SDL3Swift product.
/// SDL selects the GPU API for the platform.
public final class SDLRenderBackend: SpriteRenderBackend {
    public let window: SDLWindow
    private var textures: [TextureID: SDLTexture] = [:]
    private var nextTextureID: UInt32 = 1
    private var vertexBuffer: [SDLRenderer.Vertex] = []
    private var indexBuffer: [Int32] = []

    public init(window: SDLWindow) {
        self.window = window
    }

    deinit {
        // Textures must be destroyed before the window releases its renderer.
        textures.removeAll()
    }

    public var drawableSize: Vector2 { window.drawableSize }

    public func makeTexture(_ pixels: PixelBuffer, filtering: TextureFiltering) throws -> Texture {
        let texture = try SDLTexture(renderer: window.renderer, format: .rgba32, access: .static,
            width: pixels.width, height: pixels.height)
        try texture.setScaleMode(filtering == .nearest ? .nearest : .linear)
        try upload(pixels, to: texture)
        let id = TextureID(rawValue: nextTextureID)
        nextTextureID += 1
        textures[id] = texture
        return Texture(id: id, textureSize: pixels.size)
    }

    private func upload(_ pixels: PixelBuffer, to texture: SDLTexture) throws {
        try pixels.pixels.withUnsafeBytes { bytes in
            guard let address = bytes.baseAddress else { return }
            // SDL_UpdateTexture reads this memory; the wrapper currently takes a mutable pointer.
            try texture.update(pixels: UnsafeMutableRawPointer(mutating: address), pitch: pixels.pitch)
        }
    }

    public func updateTexture(_ texture: Texture, with pixels: PixelBuffer) throws {
        guard let sdlTexture = textures[texture.id] else { return }
        guard pixels.size == texture.textureSize else {
            throw SDLError("updateTexture", message: "Pixel dimensions must match the backing texture")
        }
        try upload(pixels, to: sdlTexture)
    }

    public func destroyTexture(_ texture: Texture) {
        textures.removeValue(forKey: texture.id)
    }

    public func render(_ frame: SpriteFrame, clearColor: Color) throws {
        let renderer = window.renderer
        try renderer.setDrawColorFloat(red: clearColor.red, green: clearColor.green,
            blue: clearColor.blue, alpha: clearColor.alpha)
        try renderer.clear()
        vertexBuffer.removeAll(keepingCapacity: true)
        for vertex in frame.vertices {
            vertexBuffer.append(SDLRenderer.Vertex(x: vertex.position.x, y: vertex.position.y,
                color: .init(red: vertex.color.red, green: vertex.color.green,
                    blue: vertex.color.blue, alpha: vertex.color.alpha),
                textureX: vertex.texCoord.x, textureY: vertex.texCoord.y))
        }
        for batch in frame.batches where !batch.indexRange.isEmpty {
            let texture = textures[batch.texture]
            let blend = Self.blendMode(batch.blendMode)
            if let texture { try texture.setBlendMode(blend) }
            else { try renderer.setDrawBlendMode(blend) }
            indexBuffer.removeAll(keepingCapacity: true)
            indexBuffer.append(contentsOf: frame.indices[batch.indexRange].map { Int32(bitPattern: $0) })
            try renderer.drawGeometry(texture: texture, vertices: vertexBuffer, indices: indexBuffer)
        }
        renderer.present()
    }

    private static func blendMode(_ mode: BlendMode) -> BitMaskOptionSet<SDLBlendMode> {
        switch mode {
        case .alpha: [.alpha]
        case .add: [.additive]
        case .multiply: [.multiply]
        case .replace: []
        }
    }
}
