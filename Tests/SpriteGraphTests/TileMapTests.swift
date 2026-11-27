import Testing
import SpriteCore
@testable import SpriteGraph

@MainActor @Suite struct TileMapTests {
    let texture = Texture(id: TextureID(rawValue: 1), textureSize: [20, 10])

    @Test func coordinatesAndBounds() {
        let map = TileMap(tileSet: TileSet(textures: [1: texture]), columns: 2, rows: 3, tileSize: [20, 10])
        map.anchorPoint = [0.5, 0.5]
        #expect(map.localBounds == Rect(x: -20, y: -15, width: 40, height: 30))
        #expect(map.centerOfTile(column: 0, row: 0) == [-10, -10])
        #expect(map.tileCoordinates(at: [-20, -15])?.column == 0)
        #expect(map.tileCoordinates(at: [19, 14])?.row == 2)
        #expect(map.tileCoordinates(at: [20, 0]) == nil)
        #expect(map.tileCoordinates(at: [.nan, 0]) == nil)
        #expect(map[-1, 0] == nil)
    }

    @Test func editsInvalidateChunksAndInheritState() {
        let map = TileMap(tileSet: TileSet(textures: [1: texture]), columns: 17, rows: 17, tileSize: [20, 10])
        map[0, 0] = Tile(id: 1)
        map[16, 16] = Tile(id: 1)
        func frame() -> SpriteFrame {
            var context = RenderContext()
            context.transform = .translation([5, 7])
            context.alpha = 0.5
            map.draw(in: &context)
            return context.batcher.makeFrame()
        }
        #expect(frame().vertices.count == 8)
        map[0, 0] = nil
        map.anchorPoint = [0.5, 0.5]
        let changed = frame()
        #expect(changed.vertices.count == 4)
        #expect(changed.vertices[0].position == [155, 82])
        #expect(changed.vertices[0].color.alpha == 0.5)
        #expect(changed.batches.count == 1)
        map[16, 16] = nil
        #expect(frame().vertices.isEmpty)
    }

    @Test(arguments: 0..<8) func allFlipCombinations(flags: Int) {
        let map = TileMap(tileSet: TileSet(textures: [1: texture]), columns: 1, rows: 1, tileSize: [20, 10])
        map[0, 0] = Tile(id: 1, flipHorizontally: flags & 1 != 0,
            flipVertically: flags & 2 != 0, flipDiagonally: flags & 4 != 0)
        var context = RenderContext()
        map.draw(in: &context)
        let frame = context.batcher.makeFrame()
        for vertex in frame.vertices {
            // Independently map each source UV corner through Tiled's image-space operations.
            var point = vertex.texCoord
            if flags & 4 != 0 { point = [point.y, point.x] }
            if flags & 1 != 0 { point.x = 1 - point.x }
            if flags & 2 != 0 { point.y = 1 - point.y }
            #expect(vertex.position == Vector2(point.x * 20, (1 - point.y) * 10))
        }
    }
}
