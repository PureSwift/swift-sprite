import SDL3Swift
import SpriteCore

/// Batched geometry rendered through PureSwift/SDL's SDL3Swift product.
/// SDL selects the GPU API for the platform.
public final class SDLRenderBackend: SpriteRenderBackend {
    public let window: SDLWindow
    private var textures: [TextureID: SDLTexture] = [:]
    // Retain source pixels to lazily build premultiplied textures for screen blending.
    private var texturePixels: [TextureID: PixelBuffer] = [:]
    private var textureFiltering: [TextureID: TextureFiltering] = [:]
    private var screenTextures: [TextureID: SDLTexture] = [:]
    private var whiteTexture: SDLTexture?
    private var nextTextureID: UInt32 = 1
    private var vertexBuffer: [SDLRenderer.Vertex] = []
    private var indexBuffer: [Int32] = []

    public init(window: SDLWindow) {
        self.window = window
    }

    deinit {
        // Textures must be destroyed before the window releases its renderer.
        screenTextures.removeAll()
        whiteTexture = nil
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
        texturePixels[id] = pixels
        textureFiltering[id] = filtering
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
        texturePixels[texture.id] = pixels
        screenTextures.removeValue(forKey: texture.id)
    }

    public func destroyTexture(_ texture: Texture) {
        textures.removeValue(forKey: texture.id)
        texturePixels.removeValue(forKey: texture.id)
        textureFiltering.removeValue(forKey: texture.id)
        screenTextures.removeValue(forKey: texture.id)
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
        var screenVertices: [SDLRenderer.Vertex]?
        for batch in frame.batches where !batch.indexRange.isEmpty {
            let texture: SDLTexture?
            let vertices: [SDLRenderer.Vertex]
            if batch.blendMode == .screen {
                texture = try screenTexture(for: batch.texture)
                try texture?.setBlendMode(Self.screenBlendMode)
                if screenVertices == nil {
                    screenVertices = frame.vertices.map { vertex in
                        let color = vertex.color
                        return SDLRenderer.Vertex(x: vertex.position.x, y: vertex.position.y,
                            color: .init(red: color.red * color.alpha, green: color.green * color.alpha,
                                blue: color.blue * color.alpha, alpha: color.alpha),
                            textureX: vertex.texCoord.x, textureY: vertex.texCoord.y)
                    }
                }
                vertices = screenVertices ?? []
            } else {
                texture = textures[batch.texture]
                let blend = Self.blendMode(batch.blendMode)
                if let texture { try texture.setBlendMode(blend) }
                else { try renderer.setDrawBlendMode(blend) }
                vertices = vertexBuffer
            }
            indexBuffer.removeAll(keepingCapacity: true)
            indexBuffer.append(contentsOf: frame.indices[batch.indexRange].map { Int32(bitPattern: $0) })
            try renderer.drawGeometry(texture: texture, vertices: vertices, indices: indexBuffer)
        }
        renderer.present()
    }

    static var screenBlendMode: SDLCustomBlendMode {
        // Premultiplied S + D * (1 - S), with source-over alpha.
        SDLCustomBlendMode(sourceColorFactor: .oneMinusDestinationColor, destinationColorFactor: .one,
            sourceAlphaFactor: .one, destinationAlphaFactor: .oneMinusSourceAlpha)
    }

    static func premultiplied(_ pixels: PixelBuffer) -> PixelBuffer {
        var result = pixels
        for offset in stride(from: 0, to: result.pixels.count, by: 4) {
            let alpha = UInt16(result.pixels[offset + 3])
            for channel in 0..<3 {
                result.pixels[offset + channel] = UInt8((UInt16(result.pixels[offset + channel]) * alpha + 127) / 255)
            }
        }
        return result
    }

    private func screenTexture(for id: TextureID) throws -> SDLTexture {
        if let texture = screenTextures[id] { return texture }
        guard let pixels = texturePixels[id] else {
            if let whiteTexture { return whiteTexture }
            let texture = try SDLTexture(renderer: window.renderer, format: .rgba32, access: .static, width: 1, height: 1)
            try upload(PixelBuffer(width: 1, height: 1, fill: .white), to: texture)
            whiteTexture = texture
            return texture
        }
        let texture = try SDLTexture(renderer: window.renderer, format: .rgba32, access: .static,
            width: pixels.width, height: pixels.height)
        try texture.setScaleMode(textureFiltering[id] == .nearest ? .nearest : .linear)
        try upload(Self.premultiplied(pixels), to: texture)
        screenTextures[id] = texture
        return texture
    }

    private static func blendMode(_ mode: BlendMode) -> BitMaskOptionSet<SDLBlendMode> {
        switch mode {
        case .alpha: [.alpha]
        case .add: [.additive]
        case .multiply: [.multiply]
        case .replace: []
        case .screen: preconditionFailure("Screen uses a custom blend mode")
        }
    }
}
