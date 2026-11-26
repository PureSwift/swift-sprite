//
//  SDLRenderBackend.swift
//  SpriteSDL
//

import CSDL3
import SpriteCore

/// ``SpriteRenderBackend`` drawing batched geometry with `SDL_RenderGeometry`.
///
/// SDL selects the GPU API (Metal, Vulkan, OpenGL, OpenGL ES, Direct3D) for the platform.
public final class SDLRenderBackend: SpriteRenderBackend {

    public let window: SDLWindow

    private var textures = [TextureID: UnsafeMutablePointer<SDL_Texture>]()

    private var nextTextureID: UInt32 = 1

    /// Reused per-frame conversion buffers.
    private var vertexBuffer = [SDL_Vertex]()
    private var indexBuffer = [Int32]()

    public init(window: SDLWindow) {
        self.window = window
    }

    deinit {
        for texture in textures.values {
            SDL_DestroyTexture(texture)
        }
    }

    private var renderer: OpaquePointer {
        window.renderer
    }

    public var drawableSize: Vector2 {
        window.drawableSize
    }

    public func makeTexture(_ pixels: PixelBuffer, filtering: TextureFiltering) throws -> Texture {
        guard let texture = SDL_CreateTexture(
            renderer,
            SDL_PIXELFORMAT_RGBA32,
            SDL_TEXTUREACCESS_STATIC,
            Int32(pixels.width),
            Int32(pixels.height)
        ) else {
            throw SDLError.last("SDL_CreateTexture")
        }
        SDL_SetTextureScaleMode(texture, filtering == .nearest ? SDL_SCALEMODE_NEAREST : SDL_SCALEMODE_LINEAR)
        let id = TextureID(rawValue: nextTextureID)
        nextTextureID += 1
        textures[id] = texture
        let handle = Texture(id: id, textureSize: pixels.size)
        try updateTexture(handle, with: pixels)
        return handle
    }

    public func updateTexture(_ texture: Texture, with pixels: PixelBuffer) throws {
        guard let sdlTexture = textures[texture.id] else { return }
        try pixels.pixels.withUnsafeBytes {
            try SDL_UpdateTexture(sdlTexture, nil, $0.baseAddress, Int32(pixels.pitch)).check("SDL_UpdateTexture")
        }
    }

    public func destroyTexture(_ texture: Texture) {
        if let sdlTexture = textures.removeValue(forKey: texture.id) {
            SDL_DestroyTexture(sdlTexture)
        }
    }

    public func render(_ frame: SpriteFrame, clearColor: Color) throws {
        try SDL_SetRenderDrawColorFloat(renderer, clearColor.red, clearColor.green, clearColor.blue, clearColor.alpha)
            .check("SDL_SetRenderDrawColorFloat")
        try SDL_RenderClear(renderer).check("SDL_RenderClear")

        vertexBuffer.removeAll(keepingCapacity: true)
        for v in frame.vertices {
            vertexBuffer.append(SDL_Vertex(
                position: SDL_FPoint(x: v.position.x, y: v.position.y),
                color: SDL_FColor(r: v.color.red, g: v.color.green, b: v.color.blue, a: v.color.alpha),
                tex_coord: SDL_FPoint(x: v.texCoord.x, y: v.texCoord.y)
            ))
        }
        indexBuffer.removeAll(keepingCapacity: true)
        indexBuffer.append(contentsOf: frame.indices.lazy.map { Int32(bitPattern: $0) })

        try vertexBuffer.withUnsafeBufferPointer { vertices in
            try indexBuffer.withUnsafeBufferPointer { indices in
                for batch in frame.batches where !batch.indexRange.isEmpty {
                    let texture = textures[batch.texture]
                    let blend = Self.sdlBlendMode(batch.blendMode)
                    if let texture {
                        SDL_SetTextureBlendMode(texture, blend)
                    } else {
                        SDL_SetRenderDrawBlendMode(renderer, blend)
                    }
                    try SDL_RenderGeometry(
                        renderer,
                        texture,
                        vertices.baseAddress,
                        Int32(vertices.count),
                        indices.baseAddress! + batch.indexRange.lowerBound,
                        Int32(batch.indexRange.count)
                    ).check("SDL_RenderGeometry")
                }
            }
        }

        try SDL_RenderPresent(renderer).check("SDL_RenderPresent")
    }

    private static func sdlBlendMode(_ mode: BlendMode) -> SDL_BlendMode {
        switch mode {
        case .alpha: SDL_BLENDMODE_BLEND
        case .add: SDL_BLENDMODE_ADD
        case .multiply: SDL_BLENDMODE_MUL
        case .replace: SDL_BLENDMODE_NONE
        }
    }
}
