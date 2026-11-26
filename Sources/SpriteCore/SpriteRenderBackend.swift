//
//  SpriteRenderBackend.swift
//  SpriteCore
//

/// Platform renderer that owns GPU textures and draws ``SpriteFrame`` geometry.
///
/// Implementations (e.g. `SDLRenderBackend`) receive vertices already in
/// render-target pixel space with the origin at the top-left.
public protocol SpriteRenderBackend: AnyObject {

    /// Size in pixels of the current render target.
    var drawableSize: Vector2 { get }

    /// Uploads RGBA8 pixels and returns a handle to the new texture.
    func makeTexture(_ pixels: PixelBuffer, filtering: TextureFiltering) throws -> Texture

    /// Replaces the contents of an existing texture with pixels of the same size.
    func updateTexture(_ texture: Texture, with pixels: PixelBuffer) throws

    /// Releases the GPU resources backing a texture.
    func destroyTexture(_ texture: Texture)

    /// Clears the render target, draws the frame and presents it.
    func render(_ frame: SpriteFrame, clearColor: Color) throws
}
