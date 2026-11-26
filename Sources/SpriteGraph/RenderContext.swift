//
//  RenderContext.swift
//  SpriteGraph
//

import SpriteCore

/// Accumulated render state passed to ``Node/draw(in:)`` during scene traversal.
public struct RenderContext {

    /// Quads collected for the current frame.
    public var batcher: SpriteBatcher

    /// Node-to-scene transform of the node currently drawing.
    public internal(set) var transform: Matrix3x3 = .identity

    /// Accumulated alpha of the node currently drawing.
    public internal(set) var alpha: Float = 1

    /// Accumulated z position of the node currently drawing.
    public internal(set) var zPosition: Float = 0

    public init(batcher: SpriteBatcher = SpriteBatcher()) {
        self.batcher = batcher
    }

    /// Submits a quad positioned by `offset` in the current node's coordinate space.
    public mutating func submit(
        texture: Texture = .none,
        size: Vector2,
        offset: Matrix3x3 = .identity,
        anchorPoint: Vector2 = Vector2(0.5, 0.5),
        color: Color = .white,
        blendMode: BlendMode = .alpha,
        shader: SpriteShader = .standard
    ) {
        var tint = color
        tint.alpha *= alpha
        guard tint.alpha > 0, size.x != 0, size.y != 0 else { return }
        batcher.submit(SpriteQuad(
            texture: texture,
            transform: transform * offset,
            size: size,
            anchorPoint: anchorPoint,
            color: tint,
            zPosition: zPosition,
            blendMode: blendMode,
            shader: shader
        ))
    }
}
