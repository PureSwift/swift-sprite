import Testing
import SpriteCore
@testable import SpriteGraph

@MainActor @Suite struct TileMapTests {
    let texture = Texture(id: TextureID(rawValue: 1), textureSize: [20, 10])

    @Test func validatesAnimation() {
        #expect(TileAnimation(textures: [], timePerFrame: .seconds(1)) == nil)
        #expect(TileAnimation(textures: [texture], timePerFrame: .zero) == nil)
        #expect(TileAnimation(textures: [texture], timePerFrame: .seconds(-1)) == nil)
    }

    @Test func animationLoopsWithoutRebuildingGeometry() throws {
        let second = Texture(id: TextureID(rawValue: 2), textureSize: [20, 10])
            .subtexture(inUnitRect: Rect(x: 0.5, y: 0, width: 0.5, height: 1))
        let animation = try #require(TileAnimation(textures: [texture, second], timePerFrame: .milliseconds(250)))
        let set = TileSet(textures: [2: texture], animations: [1: animation])
        let map = TileMap(tileSet: set, columns: 3, rows: 1, tileSize: [20, 10])
        map[0, 0] = Tile(id: 1)
        map[1, 0] = Tile(id: 1)
        map[2, 0] = Tile(id: 2)
        func frame(_ node: TileMap) -> SpriteFrame {
            var context = RenderContext()
            node.draw(in: &context)
            return context.batcher.makeFrame()
        }
        let initial = frame(map)
        map.evaluateActions(seconds: 0.125)
        #expect(frame(map).vertices == initial.vertices)
        map.evaluateActions(seconds: 0.125)
        let changed = frame(map)
        #expect(changed.batches.map(\.texture) == [second.id, texture.id])
        #expect(changed.vertices.map(\.position) == initial.vertices.map(\.position))
        #expect(changed.vertices[0].texCoord.x == 0.5)
        #expect(changed.vertices[4].texCoord.x == 0.5)
        #expect(changed.vertices[8].texCoord.x == 0)
        map[1, 0] = nil
        #expect(frame(map).vertices.count == 8)
        map[1, 0] = Tile(id: 1)
        #expect(frame(map).vertices == changed.vertices)
        let fresh = TileMap(tileSet: set, columns: 1, rows: 1, tileSize: [20, 10])
        fresh[0, 0] = Tile(id: 1)
        #expect(frame(fresh).batches.first?.texture == texture.id)
        map.evaluateActions(seconds: 1000.25)
        #expect(frame(map).vertices == initial.vertices)
    }

    @Test func animationInheritsPauseAndSpeed() throws {
        let second = Texture(id: TextureID(rawValue: 2), textureSize: [20, 10])
        let animation = try #require(TileAnimation(textures: [texture, second], timePerFrame: .seconds(1)))
        let map = TileMap(tileSet: TileSet(textures: [:], animations: [1: animation]),
            columns: 1, rows: 1, tileSize: [20, 10])
        map[0, 0] = Tile(id: 1)
        let parent = Node()
        let scene = Scene(size: [100, 100])
        scene.addChild(parent)
        parent.addChild(map)
        func displayed() -> TextureID? { scene.makeFrame(viewportSize: [100, 100]).batches.first?.texture }
        scene.speed = 2
        parent.speed = 2
        map.speed = 0.5
        scene.advance(by: .milliseconds(500))
        #expect(displayed() == second.id)
        for node in [scene as Node, parent, map] {
            node.isPaused = true
            scene.advance(by: .milliseconds(500))
            #expect(displayed() == second.id)
            node.isPaused = false
        }
        map.speed = 0
        scene.advance(by: .seconds(1))
        #expect(displayed() == second.id)
        map.speed = 0.5
        scene.advance(by: .milliseconds(500))
        #expect(displayed() == texture.id)
    }

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
