import Foundation
import Testing
import SpriteCore
import SpriteGraph
@testable import SpriteFormats

@Suite struct SceneArchiveTileMapTests {
    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresNativeGrid(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/tiles." + format)))
        var requests = 0
        let map = try #require(archive.makeNode(textureResolver: { reference in
            requests += 1
            #expect(reference.imageName == "../SpriteKit/sample.atlas/wide.png")
            return Texture(id: TextureID(rawValue: 5), textureSize: [80, 40])
        }) as? TileMap)
        #expect(requests == 1)
        #expect(map.columns == 3 && map.rows == 2 && map.tileSize == [16, 16])
        #expect(map.position == [20, 30] && map.anchorPoint == [0.25, 0.75])
        #expect(map[0, 0]?.id == 0 && map[1, 0]?.id == 1 && map[2, 0] == nil)
        #expect(map[0, 1]?.id == 2 && map[1, 1]?.id == 0 && map[2, 1] == nil)
        #expect(abs(map.color.red - 0.6) < 0.00001)
        let scene = Scene(size: [100, 100])
        scene.addChild(map)
        let frame = scene.makeFrame(viewportSize: [100, 100])
        #expect(frame.vertices.count == 16)
        let center = frame.vertices.prefix(4).reduce(Vector2.zero) { $0 + $1.position } / 4
        #expect(center == [16, 86])
        map[2, 0] = map[0, 0]
        #expect(scene.makeFrame(viewportSize: [100, 100]).vertices.count == 20)
        let fresh = try #require(archive.makeNode(textureResolver: { _ in
            Texture(id: TextureID(rawValue: 6), textureSize: [80, 40])
        }) as? TileMap)
        #expect(fresh[2, 0] == nil)
    }

    @MainActor @Test func resolvesExternalTileSet() async throws {
        let sets = try await SpriteKitTileSetArchive.decode(at: Fixtures.url("SceneArchives/tilesets.sks"))
        #expect(sets.count == 1 && sets[0].name == "Terrain")
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/tiles-external.sks")))
        #expect(throws: SceneArchiveError.missingTileSet("Terrain")) { try archive.makeNode() }
        #expect(throws: SceneArchiveError.missingTexture("../SpriteKit/sample.atlas/wide.png")) {
            try archive.makeNode(tileSetResolver: { _ in sets.first })
        }
        var names: [String] = []
        let map = try #require(archive.makeNode(textureResolver: { _ in
            Texture(id: TextureID(rawValue: 3), textureSize: [80, 40])
        }, tileSetResolver: { name in names.append(name); return sets.first }) as? TileMap)
        #expect(names == ["Terrain"] && map[0, 1]?.id == 2)
    }

    private func graph() throws -> KeyedArchive {
        try KeyedArchive(ArchivePropertyList.decode(Data(contentsOf: Fixtures.url("SceneArchives/tiles.sks"))))
    }

    @Test func rejectsInvalidDimensionsAndCells() throws {
        let graph = try graph()
        let original = try graph.dictionary(.uid(graph.rootID))
        for changes: [String: PropertyValue] in [
            ["_currentColumns": .number(0)], ["_currentRows": .number(1.5)],
            ["_currentColumns": .number(1_000_000)], ["_tileWidth": .number(-1)],
            ["_tileHeight": .number(.infinity)], ["_rawTiles": .data(Data([0]))],
            ["_rawTiles": .data(Data(repeating: 0xff, count: 24))],
            ["_rawTiles": .data(Data([2, 0, 0, 0] + Array(repeating: UInt8(0), count: 20)))],
            ["_tileWidth": .number(32)]
        ] {
            let fields = original.merging(changes) { _, new in new }
            #expect(throws: SceneArchiveError.self) { try ArchiveTileMap(fields, graph: graph) }
        }
    }

    @Test func rejectsUnsupportedTileDefinitions() throws {
        let graph = try graph()
        let setIndex = try #require(graph.objects.firstIndex { value in
            guard let fields = value.dictionary else { return false }
            return (try? graph.className(fields)) == "SKTileSet"
        })
        let definitionIndex = try #require(graph.objects.firstIndex { value in
            guard let fields = value.dictionary else { return false }
            return (try? graph.className(fields)) == "SKTileDefinition"
        })
        for (index, changes): (Int, [String: PropertyValue]) in [
            (setIndex, ["_type": .number(1)]),
            (definitionIndex, ["_orientation": .number(1)]),
            (definitionIndex, ["_timePerFrame": .number(0.2)]),
            (definitionIndex, ["_textures": .array([])])
        ] {
            var objects = graph.objects
            var fields = try graph.dictionary(.uid(index))
            fields.merge(changes) { _, new in new }
            objects[index] = .dictionary(fields)
            let modified = try KeyedArchive(.dictionary(["$archiver": .string("NSKeyedArchiver"),
                "$version": .number(100_000), "$top": .dictionary(["root": .uid(graph.rootID)]), "$objects": .array(objects)]))
            #expect(throws: SceneArchiveError.self) { try SpriteKitTileSetArchive(.uid(setIndex), graph: modified) }
        }
    }
}
