import Foundation
import Testing
import SpriteCore
import SpriteGraph
@testable import SpriteFormats

@Suite struct SceneArchiveTests {
    @MainActor @Test(arguments: ["sks", "xml"])
    func resolvesNativeReferences(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/references." + format)))
        let target = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/reference-target." + format)))
        #expect(archive.referenceNames == ["ReferenceTarget"])
        #expect(throws: SceneArchiveError.missingReference("ReferenceTarget")) { try archive.makeNode() }
        var references = 0, textures = 0
        let scene = try #require(archive.makeNode(textureResolver: { _ in
            textures += 1
            return Texture(id: TextureID(rawValue: 1), textureSize: [80, 40])
        }, referenceResolver: { name in
            references += 1
            #expect(name == "ReferenceTarget")
            return target
        }) as? Scene)
        #expect(references == 1 && textures == 1)
        #expect(scene.children.count == 2)
        let first = try #require(scene.children.first?.children.first)
        let second = try #require(scene.children.last?.children.first)
        #expect(!(first is Scene) && !(second is Scene) && first !== second)
        let a = try #require(first.children.first as? Sprite)
        let b = try #require(second.children.first as? Sprite)
        #expect(a !== b && a.name == "content" && b.name == "content")
        #expect(a.worldMatrix.transform(point: .zero) == [25, 17])
        #expect(b.worldMatrix.transform(point: .zero) == [85, 17])
        a.position.x = 99
        #expect(b.position == [5, 7])
        #expect(scene.makeFrame(viewportSize: [200, 100]).vertices.count == 8)
    }

    private func referenceArchive(_ name: String, scale: Float = 1) throws -> SpriteKitSceneArchive {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "$archiver": "NSKeyedArchiver", "$version": 100_000,
            "$top": ["root": ["CF$UID": 1]],
            "$objects": ["$null", ["$class": ["CF$UID": 2], "_referenceFileName": name, "_xScale": scale],
                ["$classname": "SKReferenceNode"]]
        ], format: .xml, options: 0)
        return try SpriteKitSceneArchive.decode(data)
    }

    @MainActor @Test func rejectsCyclicAndExcessivelyDeepReferences() throws {
        #expect(throws: SceneArchiveError.invalid("Missing reference node filename")) { try referenceArchive("") }
        let archive = try referenceArchive("self")
        #expect(throws: SceneArchiveError.invalid("Cyclic reference node: self")) {
            try archive.makeNode(referenceResolver: { _ in archive })
        }
        let start = try referenceArchive("0")
        #expect(throws: SceneArchiveError.invalid("Excessive reference expansion")) {
            try start.makeNode(referenceResolver: { name in try referenceArchive(String((Int(name) ?? 0) + 1)) })
        }
    }

    @MainActor @Test func resolvesNestedReferenceNames() throws {
        let start = try referenceArchive("nested.sks")
        let middle = try referenceArchive("leaf")
        let target = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/reference-target.sks")))
        var requested: [String] = []
        let root = try start.makeNode(textureResolver: { _ in
            Texture(id: TextureID(rawValue: 1), textureSize: [80, 40])
        }, referenceResolver: { name in
            requested.append(name)
            return name == "nested.sks" ? middle : target
        })
        #expect(requested == ["nested.sks", "leaf"])
        #expect(root.children.first?.children.first?.children.first is Sprite)
    }

    @MainActor @Test func rejectsPhysicsUnderScaledReferences() throws {
        let archive = try referenceArchive("physics", scale: 2)
        let target = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/physics.sks")))
        #expect(throws: SceneArchiveError.unsupported("Physics bodies under scaled reference nodes")) {
            try archive.makeNode(referenceResolver: { _ in target })
        }
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func loadsNativeArchive(format: String) async throws {
        let archive = try await SpriteKitSceneArchive.decode(at: Fixtures.url("SceneArchives/scene." + format))
        let backend = MockBackend()
        let font = try BitmapFont.debug(backend: backend)
        var textureRequests = 0
        var fontNames: [String] = []
        let root = try archive.makeNode(textureResolver: { reference in
            textureRequests += 1
            #expect(reference.imageName == "../SpriteKit/sample.atlas/wide.png")
            #expect(reference.filtering == .linear)
            return Texture(id: TextureID(rawValue: 99), textureSize: [80, 40])
        }, fontResolver: { name in
            fontNames.append(name)
            return font
        })
        let scene = try #require(root as? Scene)
        #expect(scene.name == "Fixture")
        #expect(scene.size == [320, 240] && scene.anchorPoint == [0.25, 0.5])
        #expect(scene.scaleMode == .aspectFit)
        #expect(abs(scene.backgroundColor.red - 0.1) < 0.00001)
        #expect(scene.children.map(\.name) == ["parent", "camera", "label", "textured", "sharedTexture"])
        let parent = scene.children[0]
        #expect(parent.position == [12, -8])
        #expect(parent.scale == [2, 0.5] && parent.zRotation == 0.25 && parent.alpha == 0.75)
        let sprite = try #require(parent.children.first as? Sprite)
        #expect(sprite.position == [5, 7] && sprite.size == [40, 24])
        #expect(abs(sprite.anchorPoint.x - 0.2) < 0.00001)
        #expect(abs(sprite.centerRect.minY - 0.2) < 0.00001)
        #expect(sprite.blendMode == .add && sprite.zPosition == 3)
        #expect(scene.camera === scene.children[1])
        #expect(scene.camera?.position == [160, 120])
        let label = try #require(scene.children[2] as? Label)
        #expect(label.text == "Hello 🦊" && label.fontSize == 18)
        #expect(label.horizontalAlignmentMode == .left && label.verticalAlignmentMode == .top)
        #expect(label.numberOfLines == 2 && label.preferredMaxLayoutWidth == 100)
        #expect(fontNames == ["Menlo"])
        #expect(textureRequests == 1)
        #expect(!scene.makeFrame(viewportSize: [320, 240]).vertices.isEmpty)
        #expect(abs(scene.physicsWorld.gravity.y + 1470) < 0.001)
        #expect(scene.physicsWorld.speed == 1)
    }

    @MainActor @Test func missingResourcesFailExplicitly() throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/scene.sks")))
        #expect(throws: SceneArchiveError.missingFont("Menlo")) { try archive.makeNode() }
        let font = try BitmapFont.debug(backend: MockBackend())
        #expect(throws: SceneArchiveError.missingTexture("../SpriteKit/sample.atlas/wide.png")) {
            try archive.makeNode(fontResolver: { _ in font })
        }
    }

    private func minimal(_ fields: [String: Any], className: String = "SKNode", extra: [Any] = []) throws -> Data {
        let objects: [Any] = ["$null", fields.merging(["$class": ["CF$UID": 2]]) { old, _ in old },
            ["$classname": className, "$classes": [className, "NSObject"]]] + extra
        return try PropertyListSerialization.data(fromPropertyList: [
            "$archiver": "NSKeyedArchiver", "$version": 100_000,
            "$top": ["root": ["CF$UID": 1]], "$objects": objects
        ], format: .xml, options: 0)
    }

    @Test func rejectsUnknownClass() throws {
        let data = try minimal([:], className: "CustomScene")
        #expect(throws: SceneArchiveError.unsupported("Node class CustomScene at object 1")) {
            try SpriteKitSceneArchive.decode(data)
        }
    }

    @Test func rejectsMalformedFields() throws {
        let cases: [[String: Any]] = [
        ["_children": [["CF$UID": 1]]],
        ["_children": [["CF$UID": 99]]],
        ["_name": ["CF$UID": 99]],
        ["_name": ["CF$UID": 3]],
        ["_position": "{nan, 0}"],
        ["_xScale": Double.infinity],
        ["_opacity": "bad"],
        ["_hidden": "bad"]
        ]
        for fields in cases {
            let data = try minimal(fields, extra: [["CF$UID": 3]])
            #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(data) }
        }
    }

    @Test func rejectsShaders() throws {
        for key in ["_shader"] {
            let data = try minimal([key: ["CF$UID": 3]], extra: [["unsupported": true]])
            #expect(throws: SceneArchiveError.unsupported("SKNode." + key)) {
                try SpriteKitSceneArchive.decode(data)
            }
        }
    }

    @MainActor @Test func mapsCommonPropertiesAndPlainNodeRoot() throws {
        let data = try minimal(["_name": "node", "_position": "{-2, 3}", "_hidden": true,
            "_paused": true, "_speed": 0.5, "_opacity": 0.25, "_zPosition": -1])
        let root = try SpriteKitSceneArchive.decode(data).makeNode()
        #expect(root.name == "node" && root.position == [-2, 3])
        #expect(root.isHidden && root.isPaused && root.speed == 0.5)
        #expect(root.alpha == 0.25 && root.zPosition == -1)
    }

    @Test func rejectsTruncatedAndNonArchivePlists() throws {
        let native = try Data(contentsOf: Fixtures.url("SceneArchives/scene.sks"))
        for bytes in [Data(), Data(native.prefix(32)), Data("not a plist".utf8)] {
            #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(bytes) }
        }
        let plain = try PropertyListSerialization.data(fromPropertyList: ["hello": "world"], format: .binary, options: 0)
        #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(plain) }
    }

    @MainActor @Test func textureRectConvertsFromBottomToTopOrigin() throws {
        let data = try minimal(["_texture": ["CF$UID": 3], "_bounds": "{{0, 0}, {20, 10}}"],
            className: "SKSpriteNode", extra: [
                ["$class": ["CF$UID": 4], "_imgName": "sheet.png",
                 "_textRect": "{{0.25, 0.125}, {0.5, 0.25}}"],
                ["$classname": "SKTexture"]
            ])
        let node = try SpriteKitSceneArchive.decode(data).makeNode(textureResolver: { _ in
            Texture(id: TextureID(rawValue: 1), textureSize: [80, 80])
        })
        let sprite = try #require(node as? Sprite)
        #expect(sprite.texture?.region == Rect(x: 20, y: 50, width: 40, height: 20))
    }

    @Test func rejectsCameraOutsideHierarchy() throws {
        let data = try minimal(["Scene_bounds": "{{0, 0}, {100, 100}}", "_camera": ["CF$UID": 3]],
            className: "SKScene", extra: [["$class": ["CF$UID": 4]], ["$classname": "SKCameraNode"]])
        #expect(throws: SceneArchiveError.invalid("Scene camera must reference a camera in the node tree")) {
            try SpriteKitSceneArchive.decode(data)
        }
    }
}
