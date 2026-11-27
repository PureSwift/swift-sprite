import Foundation
import Testing
import SpriteCore
import SpriteGraph
@testable import SpriteFormats

@Suite struct TiledTests {
    @MainActor @Test func loadsExternalTilesetAndLayers() async throws {
        let map = try await TiledMap.decode(at: Fixtures.url("Tiled/sample.tmx"))
        #expect(map.columns == 2 && map.rows == 2)
        let backend = MockBackend()
        let root = try map.makeNode(backend: backend)
        #expect(backend.uploads.count == 1)
        let ground = try #require(root.children[0] as? TileMap)
        let overlay = try #require(root.children[1] as? TileMap)
        #expect(ground[0, 1]?.id == 1)
        #expect(ground[0, 0] == nil)
        #expect(ground[1, 1]?.flipHorizontally == true)
        #expect(ground[1, 0]?.flipDiagonally == true)
        #expect(ground.tileSet[2]?.region == Rect(x: 20, y: 0, width: 20, height: 20))
        #expect(overlay.position == [2, -3])
        #expect(overlay.alpha == 0.5 && overlay.zPosition > ground.zPosition)
        let scene = Scene(size: [40, 40])
        scene.addChild(root)
        #expect(scene.makeFrame(viewportSize: [40, 40]).vertices.count == 16)
    }

    @Test(arguments: [
        ("orientation=\"orthogonal\"", "orientation=\"isometric\""),
        ("encoding=\"csv\"", "encoding=\"base64\""),
        ("1,2147483650", "99,2147483650"),
        ("1,2147483650", "1"),
        ("width=\"2\"", "width=\"-1\""),
        ("0,536870915", "0,invalid"),
        ("<map ", "<map infinite=\"1\" ")
    ])
    func rejectsInvalidOrUnsupportedInput(replacement: (String, String)) throws {
        let url = Fixtures.url("Tiled/sample.tmx")
        let source = try String(contentsOf: url, encoding: .utf8)
        let changed = source.replacingOccurrences(of: replacement.0, with: replacement.1)
        #expect(throws: TiledError.self) {
            try TiledMap.decode(Data(changed.utf8), relativeTo: url.deletingLastPathComponent())
        }
    }

    @Test func resolvesInlineTilesetsAndClearsFourthFlag() throws {
        let source = """
        <map orientation="orthogonal" width="1" height="1" tilewidth="20" tileheight="20">
          <tileset firstgid="10" tilewidth="20" tileheight="20" tilecount="1" columns="1">
            <image source="SpriteKit/sample.atlas/wide.png"/>
          </tileset>
          <layer width="1" height="1"><data encoding="csv">268435466</data></layer>
        </map>
        """
        let map = try TiledMap.decode(Data(source.utf8), relativeTo: Fixtures.root)
        #expect(map.layers[0].tiles[0]?.id == 10)
    }

    @Test func malformedXMLFails() {
        #expect(throws: TiledError.self) {
            try TiledMap.decode(Data("<map>".utf8), relativeTo: Fixtures.root)
        }
    }
}
