import SpriteCore

/// A looping tile animation with uniformly timed frames.
public struct TileAnimation: Sendable {
    public let textures: [Texture]
    public let timePerFrame: Duration
    let secondsPerFrame: Double

    public init?(textures: [Texture], timePerFrame: Duration) {
        let parts = timePerFrame.components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        guard !textures.isEmpty, seconds > 0, seconds.isFinite,
              (seconds * Double(textures.count)).isFinite else { return nil }
        self.textures = textures
        self.timePerFrame = timePerFrame
        secondsPerFrame = seconds
    }
}

/// Immutable tile definitions shared by maps. IDs are application-defined.
public struct TileSet: Sendable {
    /// Static textures and the first frame of each animation.
    public let textures: [UInt32: Texture]
    public let animations: [UInt32: TileAnimation]

    /// An animation overrides a static texture with the same ID.
    public init(textures: [UInt32: Texture], animations: [UInt32: TileAnimation] = [:]) {
        var firstFrames = textures
        for (id, animation) in animations { firstFrames[id] = animation.textures[0] }
        self.textures = firstFrames
        self.animations = animations
    }

    public subscript(id: UInt32) -> Texture? { textures[id] }
}

/// A tile reference with Tiled-compatible flip flags.
public struct Tile: Equatable, Sendable {
    public let id: UInt32
    public var flipHorizontally: Bool
    public var flipVertically: Bool
    public var flipDiagonally: Bool

    public init(id: UInt32, flipHorizontally: Bool = false, flipVertically: Bool = false, flipDiagonally: Bool = false) {
        self.id = id
        self.flipHorizontally = flipHorizontally
        self.flipVertically = flipVertically
        self.flipDiagonally = flipDiagonally
    }

    func transform(size: Vector2) -> Matrix3x3 {
        // Swap axes in image space (Y-down), then reflect horizontally/vertically.
        let diagonal = flipDiagonally
            ? Matrix3x3(rows: [0, -1, 0], [-1, 0, 0], [0, 0, 1]) : .identity
        return Matrix3x3.scale(size)
            * .scale([flipHorizontally ? -1 : 1, flipVertically ? -1 : 1])
            * diagonal * .scale([1 / size.x, 1 / size.y])
    }
}

/// Fixed grid with row zero at the bottom. Caches quads in 16×16 chunks.
/// Animations start at frame zero, share a clock per definition within this map,
/// and follow inherited pause/speed. Other maps maintain independent clocks.
open class TileMap: Node {
    public let columns: Int
    public let rows: Int
    public let tileSize: Vector2
    public let tileSet: TileSet
    public var anchorPoint: Vector2 = .zero
    public var color: Color = .white
    public var blendMode: BlendMode = .alpha
    private var cells: [Tile?]
    private var chunks: [Int: [(id: UInt32, quad: SpriteQuad)]] = [:]
    private var animationTimes: [UInt32: Double] = [:]
    private var chunkColumns: Int { (columns - 1) / 16 + 1 }

    public init(tileSet: TileSet, columns: Int, rows: Int, tileSize: Vector2) {
        precondition(columns > 0 && rows > 0 && columns <= Int.max / rows)
        precondition(tileSize.x.isFinite && tileSize.y.isFinite && tileSize.x > 0 && tileSize.y > 0)
        self.tileSet = tileSet
        self.columns = columns
        self.rows = rows
        self.tileSize = tileSize
        cells = Array(repeating: nil, count: columns * rows)
        super.init()
    }

    public var size: Vector2 { Vector2(Float(columns), Float(rows)) * tileSize }

    public subscript(column: Int, row: Int) -> Tile? {
        get {
            guard contains(column: column, row: row) else { return nil }
            return cells[row * columns + column]
        }
        set {
            precondition(contains(column: column, row: row), "Tile coordinate outside map")
            if let tile = newValue { precondition(tileSet[tile.id] != nil, "Unknown tile ID") }
            cells[row * columns + column] = newValue
            chunks.removeValue(forKey: (row / 16) * chunkColumns + column / 16)
        }
    }

    private func contains(column: Int, row: Int) -> Bool {
        column >= 0 && column < columns && row >= 0 && row < rows
    }

    public func centerOfTile(column: Int, row: Int) -> Vector2 {
        (Vector2(Float(column), Float(row)) + 0.5) * tileSize - anchorPoint * size
    }

    public func tileCoordinates(at point: Vector2) -> (column: Int, row: Int)? {
        let grid = (point + anchorPoint * size) / tileSize
        guard grid.x >= 0, grid.y >= 0, grid.x < Float(columns), grid.y < Float(rows) else { return nil }
        return (Int(grid.x), Int(grid.y))
    }

    open override var localBounds: Rect? { Rect(origin: -anchorPoint * size, size: size) }

    // Node action evaluation supplies elapsed time after applying inherited speed/pause.
    override func simulate(seconds: Double) {
        guard seconds > 0, seconds.isFinite else { return }
        for (id, animation) in tileSet.animations {
            let period = animation.secondsPerFrame * Double(animation.textures.count)
            animationTimes[id] = ((animationTimes[id] ?? 0) + seconds.truncatingRemainder(dividingBy: period))
                .truncatingRemainder(dividingBy: period)
        }
    }

    private func texture(for id: UInt32, fallback: Texture) -> Texture {
        guard let animation = tileSet.animations[id] else { return fallback }
        let frame = Int((animationTimes[id] ?? 0) / animation.secondsPerFrame)
        return animation.textures[min(frame, animation.textures.count - 1)]
    }

    open override func draw(in context: inout RenderContext) {
        for chunkRow in 0 ... (rows - 1) / 16 {
            for chunkColumn in 0 ..< chunkColumns {
                let key = chunkRow * chunkColumns + chunkColumn
                if chunks[key] == nil {
                    var quads: [(id: UInt32, quad: SpriteQuad)] = []
                    for row in chunkRow * 16 ..< min(rows, (chunkRow + 1) * 16) {
                        for column in chunkColumn * 16 ..< min(columns, (chunkColumn + 1) * 16) {
                            guard let tile = self[column, row], let texture = tileSet[tile.id] else { continue }
                            let center = (Vector2(Float(column), Float(row)) + 0.5) * tileSize
                            quads.append((tile.id, SpriteQuad(texture: texture,
                                transform: .translation(center) * tile.transform(size: tileSize), size: tileSize)))
                        }
                    }
                    chunks[key] = quads
                }
                for (id, quad) in chunks[key] ?? [] {
                    context.submit(texture: texture(for: id, fallback: quad.texture), size: quad.size,
                        offset: .translation(-anchorPoint * size) * quad.transform,
                        color: color, blendMode: blendMode)
                }
            }
        }
    }
}
