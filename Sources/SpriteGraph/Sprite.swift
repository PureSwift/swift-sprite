//
//  Sprite.swift
//  SpriteGraph
//

import SpriteCore

/// Node that draws a textured or solid-color rectangle.
open class Sprite: Node {

    public var texture: Texture?

    /// Size in the node's coordinate space, before `scale`.
    public var size: Vector2

    /// Normalized point of the sprite placed at `position`.
    public var anchorPoint = Vector2(0.5, 0.5)

    public var color: Color

    /// Strength of the ``color`` tint applied to the texture (0 = untinted).
    ///
    /// Tinting is multiplicative: the texture is multiplied by
    /// `white.mix(with: color, fraction: colorBlendFactor)`.
    public var colorBlendFactor: Float = 0

    public var blendMode: BlendMode = .alpha

    /// Stretchable region of the texture for 9-patch scaling, in unit coordinates
    /// of the texture with the origin at the top-left. `Rect.unit` disables slicing.
    public var centerRect: Rect = .unit

    public init(texture: Texture?, color: Color = .white, size: Vector2? = nil) {
        self.texture = texture
        self.color = color
        self.size = size ?? texture?.size ?? .zero
        super.init()
    }

    public convenience init(texture: Texture) {
        self.init(texture: texture, color: .white, size: nil)
    }

    /// Creates an untextured, solid-color sprite.
    public convenience init(color: Color, size: Vector2) {
        self.init(texture: nil, color: color, size: size)
        colorBlendFactor = 1
    }

    /// Resets ``size`` to the texture's pixel size.
    public func scaleToTextureSize() {
        if let texture {
            size = texture.size
        }
    }

    open override var localBounds: Rect? {
        Rect(origin: -anchorPoint * size, size: size)
    }

    /// Vertex color combining tint for textured sprites, or the fill for untextured ones.
    var vertexColor: Color {
        texture == nil ? color : Color.white.mix(with: color, fraction: colorBlendFactor)
    }

    open override func draw(in context: inout RenderContext) {
        guard let texture else {
            context.submit(size: size, anchorPoint: anchorPoint, color: color, blendMode: blendMode)
            return
        }
        if centerRect == .unit {
            context.submit(texture: texture, size: size, anchorPoint: anchorPoint, color: vertexColor, blendMode: blendMode)
        } else {
            for slice in nineSliceQuads(texture: texture) {
                context.submit(
                    texture: slice.texture,
                    size: slice.rect.size,
                    offset: .translation(slice.rect.origin),
                    anchorPoint: .zero,
                    color: vertexColor,
                    blendMode: blendMode
                )
            }
        }
    }

    /// Splits the sprite into up to nine quads in local coordinates (Y-up).
    ///
    /// Corners keep their texture pixel size, shrinking proportionally when the
    /// sprite is smaller than the fixed borders; edges and center stretch.
    func nineSliceQuads(texture: Texture) -> [(texture: Texture, rect: Rect)] {
        let pixelSize = texture.size
        // Unit-space boundaries of the three columns and rows (rows are top-down in texture space).
        let uCuts: [Float] = [0, centerRect.minX, centerRect.maxX, 1]
        let vCuts: [Float] = [0, centerRect.minY, centerRect.maxY, 1]

        func spans(_ cuts: [Float], texturePixels: Float, length: Float) -> [Float] {
            let start = cuts[1] * texturePixels
            let end = (1 - cuts[2]) * texturePixels
            let fixed = start + end
            let shrink = fixed > length && fixed > 0 ? length / fixed : 1
            return [start * shrink, max(length - fixed, 0), end * shrink]
        }

        let widths = spans(uCuts, texturePixels: pixelSize.x, length: abs(size.x))
        // Texture rows run top-down; local Y runs bottom-up, so reverse the heights.
        let heightsTopDown = spans(vCuts, texturePixels: pixelSize.y, length: abs(size.y))
        let origin = -anchorPoint * size
        let sign = Vector2(size.x < 0 ? -1 : 1, size.y < 0 ? -1 : 1)

        var quads = [(texture: Texture, rect: Rect)]()
        var top = abs(size.y)
        for row in 0 ..< 3 {
            let height = heightsTopDown[row]
            top -= height
            var x: Float = 0
            for column in 0 ..< 3 {
                let width = widths[column]
                defer { x += width }
                guard width > 0, height > 0 else { continue }
                let region = Rect(
                    x: uCuts[column],
                    y: vCuts[row],
                    width: uCuts[column + 1] - uCuts[column],
                    height: vCuts[row + 1] - vCuts[row]
                )
                guard region.width > 0, region.height > 0 else { continue }
                let rect = Rect(origin: origin + Vector2(x, top) * sign, size: Vector2(width, height) * sign)
                quads.append((texture.subtexture(inUnitRect: region), rect))
            }
        }
        return quads
    }
}
