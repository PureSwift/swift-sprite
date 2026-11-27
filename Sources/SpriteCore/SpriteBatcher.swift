//
//  SpriteBatcher.swift
//  SpriteCore
//

/// Color blending used when compositing a quad.
public enum BlendMode: Hashable, Comparable, Sendable {
    /// Standard alpha blending.
    case alpha
    /// Additive blending, useful for glows and particles.
    case add
    /// Multiplies source and destination colors.
    case multiply
    /// No blending; source replaces destination.
    case replace
    /// Screen composite: source plus destination times inverse source, weighted by source alpha.
    case screen
}

/// Fragment shading applied to a quad's texture.
public enum SpriteShader: Hashable, Sendable {
    /// Texture color multiplied by vertex color.
    case standard
    /// Texture alpha holds a signed distance field; the edge is reconstructed at
    /// `0.5` with the given smoothing width (in distance units).
    ///
    /// Backends without programmable shading may fall back to ``standard``.
    case distanceField(smoothing: Float)
}

/// Single textured quad submitted to a ``SpriteBatcher``.
public struct SpriteQuad: Sendable {

    public var texture: Texture

    /// Local-to-world transform of the quad.
    public var transform: Matrix3x3

    /// Size of the quad in local units.
    public var size: Vector2

    /// Normalized point of the quad placed at the transform's origin.
    public var anchorPoint: Vector2

    public var color: Color

    public var zPosition: Float

    public var blendMode: BlendMode

    public var shader: SpriteShader

    public init(
        texture: Texture = .none,
        transform: Matrix3x3 = .identity,
        size: Vector2? = nil,
        anchorPoint: Vector2 = Vector2(0.5, 0.5),
        color: Color = .white,
        zPosition: Float = 0,
        blendMode: BlendMode = .alpha,
        shader: SpriteShader = .standard
    ) {
        self.texture = texture
        self.transform = transform
        self.size = size ?? texture.size
        self.anchorPoint = anchorPoint
        self.color = color
        self.zPosition = zPosition
        self.blendMode = blendMode
        self.shader = shader
    }
}

/// Vertex emitted by the batcher, in render target pixel space.
public struct SpriteVertex: Equatable, Sendable {

    public var position: Vector2

    public var color: Color

    /// Texture coordinate with v = 0 at the top of the image.
    public var texCoord: Vector2

    public init(position: Vector2, color: Color, texCoord: Vector2) {
        self.position = position
        self.color = color
        self.texCoord = texCoord
    }
}

/// Contiguous range of indices drawn with a single texture, blend and shader state.
public struct DrawBatch: Equatable, Sendable {

    public var texture: TextureID

    public var blendMode: BlendMode

    public var shader: SpriteShader = .standard

    /// Range into ``SpriteFrame/indices``.
    public var indexRange: Range<Int>
}

/// Geometry for one frame, ready for submission to a ``SpriteRenderBackend``.
public struct SpriteFrame: Sendable {

    public var vertices: [SpriteVertex] = []

    public var indices: [UInt32] = []

    public var batches: [DrawBatch] = []

    public init() { }
}

/// Collects quads, sorts them by `zPosition` (and texture), and merges them into draw batches.
public struct SpriteBatcher: Sendable {

    public enum SortMode: Sendable {
        /// Sort by `zPosition`, preserving submission order for equal values.
        case preserveOrder
        /// Sort by `zPosition`, then group equal-z quads by texture and blend mode
        /// to minimize draw calls (equivalent to `ignoresSiblingOrder`).
        case textureGrouped
    }

    public var sortMode: SortMode

    private var quads: [SpriteQuad] = []

    public init(sortMode: SortMode = .preserveOrder) {
        self.sortMode = sortMode
    }

    public var count: Int {
        quads.count
    }

    public mutating func submit(_ quad: SpriteQuad) {
        quads.append(quad)
    }

    public mutating func removeAll() {
        quads.removeAll(keepingCapacity: true)
    }

    /// Builds frame geometry and clears submitted quads.
    ///
    /// - Parameter viewTransform: Applied to every vertex, e.g. camera * viewport.
    public mutating func makeFrame(viewTransform: Matrix3x3 = .identity) -> SpriteFrame {
        defer { removeAll() }
        var frame = SpriteFrame()
        frame.vertices.reserveCapacity(quads.count * 4)
        frame.indices.reserveCapacity(quads.count * 6)

        for index in sortedIndices() {
            let quad = quads[index]
            let world = viewTransform * quad.transform
            let lo = -quad.anchorPoint * quad.size
            let hi = lo + quad.size
            let uv = quad.texture.uvRect
            let base = UInt32(frame.vertices.count)

            // Corners in counter-clockwise order: bottom-left, bottom-right, top-right, top-left.
            // Local space is Y-up while UVs are Y-down, so the bottom edge samples maxY.
            frame.vertices.append(SpriteVertex(position: world.transform(point: Vector2(lo.x, lo.y)), color: quad.color, texCoord: Vector2(uv.minX, uv.maxY)))
            frame.vertices.append(SpriteVertex(position: world.transform(point: Vector2(hi.x, lo.y)), color: quad.color, texCoord: Vector2(uv.maxX, uv.maxY)))
            frame.vertices.append(SpriteVertex(position: world.transform(point: Vector2(hi.x, hi.y)), color: quad.color, texCoord: Vector2(uv.maxX, uv.minY)))
            frame.vertices.append(SpriteVertex(position: world.transform(point: Vector2(lo.x, hi.y)), color: quad.color, texCoord: Vector2(uv.minX, uv.minY)))

            let start = frame.indices.count
            frame.indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])

            if let last = frame.batches.indices.last,
               frame.batches[last].texture == quad.texture.id,
               frame.batches[last].blendMode == quad.blendMode,
               frame.batches[last].shader == quad.shader {
                frame.batches[last].indexRange = frame.batches[last].indexRange.lowerBound ..< frame.indices.count
            } else {
                frame.batches.append(DrawBatch(
                    texture: quad.texture.id,
                    blendMode: quad.blendMode,
                    shader: quad.shader,
                    indexRange: start ..< frame.indices.count
                ))
            }
        }
        return frame
    }

    private func sortedIndices() -> [Int] {
        // Sorting by an explicit index tiebreaker keeps the sort stable.
        switch sortMode {
        case .preserveOrder:
            return quads.indices.sorted {
                (quads[$0].zPosition, $0) < (quads[$1].zPosition, $1)
            }
        case .textureGrouped:
            return quads.indices.sorted {
                let a = quads[$0], b = quads[$1]
                if a.zPosition != b.zPosition { return a.zPosition < b.zPosition }
                if a.texture.id != b.texture.id { return a.texture.id < b.texture.id }
                if a.blendMode != b.blendMode { return a.blendMode < b.blendMode }
                return $0 < $1
            }
        }
    }
}
