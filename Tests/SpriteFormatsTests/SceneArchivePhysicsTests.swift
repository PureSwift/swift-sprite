import Foundation
import Testing
import SpriteCore
import SpriteGraph
import SpritePhysics
@testable import SpriteFormats

@Suite struct SceneArchivePhysicsTests {
    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresNativePhysics(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/physics." + format)))
        let scene = try #require(archive.makeNode() as? Scene)
        #expect(scene.physicsWorld.gravity == [300, -600])
        #expect(scene.physicsWorld.speed == 0.5)
        let circle = try #require(scene.children[0].physicsBody)
        let rectangle = try #require(scene.children[1].physicsBody)
        let polygon = try #require(scene.children[2].physicsBody)
        #expect(circle.shape == .circle(radius: 12, center: [2, 3]))
        #expect(rectangle.shape == .rectangle(size: [30, 20], center: [4, 5]))
        #expect(polygon.shape == .polygon([[-10, -10], [20, -10], [0, 20]]))
        for body in [circle, rectangle, polygon] {
            #expect(abs(body.mass - 2) < 0.00001)
            #expect(body.friction == 0.3 && body.restitution == 0.4)
            #expect(body.linearDamping == 0.2 && body.angularDamping == 0.6)
            #expect(body.velocity == [7, 8] && body.angularVelocity == 0.7)
            #expect(!body.allowsRotation)
            #expect(body.categoryBitMask.rawValue == 0x80000001)
            #expect(body.collisionBitMask.rawValue == 3 && body.contactTestBitMask.rawValue == 4)
        }
        #expect(circle.affectedByGravity && !rectangle.affectedByGravity)
        #expect(circle.isDynamic && rectangle.isDynamic && !polygon.isDynamic)
        #expect(circle.node === scene.children[0])
        // A second materialization must own independent bodies and worlds.
        let other = try #require(archive.makeNode() as? Scene)
        #expect(other.children[0].physicsBody !== circle)
        for _ in 0..<60 { scene.advance(by: .seconds(1.0 / 60.0)) }
        #expect(circle.world === scene.physicsWorld)
        #expect(scene.children[0].position.y < 200)
        #expect(scene.children[1].position.y > 200)
        #expect(scene.children[2].position == [200, 200])
        #expect(other.children[0].position == [0, 200])
        scene.physicsWorld.speed = 0
        let stopped = circle.position
        scene.advance(by: .seconds(1.0 / 60.0))
        #expect(circle.position == stopped)
    }

    private func mutated(_ className: String, changes: [String: Any]) throws -> Data {
        let data = try Data(contentsOf: Fixtures.url("SceneArchives/physics.xml"))
        // Use XML UID dictionaries so tests can change object fields without private UID APIs.
        let text = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "CF$UID", with: "TestUID")
        var plist = try #require(PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any])
        var objects = try #require(plist["$objects"] as? [Any])
        for index in objects.indices {
            guard var fields = objects[index] as? [String: Any],
                  let reference = fields["$class"] as? [String: Int], let id = reference["TestUID"],
                  let descriptor = objects[id] as? [String: Any], descriptor["$classname"] as? String == className else { continue }
            fields.merge(changes) { _, new in new }
            objects[index] = fields
            break
        }
        plist["$objects"] = objects
        let result = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return Data(String(decoding: result, as: UTF8.self).replacingOccurrences(of: "TestUID", with: "CF$UID").utf8)
    }

    @Test func rejectsInvalidBodyValues() throws {
        for changes: [String: Any] in [
            ["_radius": 0], ["_radius": -1], ["density": -1], ["density": Double.infinity],
            ["linearDamping": -1], ["restitution": 2], ["categoryBitMask": 1.5],
            ["categoryBitMask": 4_294_967_296.0], ["linearVelocity": "{nan, 0}"],
            ["_p0": ["TestUID": 99999]]
        ] {
            let data = try mutated("PKPhysicsBody", changes: changes)
            #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(data) }
        }
    }

    @Test func rejectsUnsupportedPhysics() throws {
        for changes: [String: Any] in [["_shapeType": 99], ["pinned": true],
            ["needsContinuousCollsionDetection": true], ["charge": 1]] {
            let data = try mutated("PKPhysicsBody", changes: changes)
            #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(data) }
        }
        for changes: [String: Any] in [["speedMultiplier": -1], ["gravity": "{inf, 0}"],
            ["_joints": [["TestUID": 1]]]] {
            let data = try mutated("PKPhysicsWorld", changes: changes)
            #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(data) }
        }
    }

    @MainActor @Test func preservesUnsignedAndAllBitsMasks() throws {
        let data = try mutated("PKPhysicsBody", changes: ["categoryBitMask": 4_294_967_295.0,
            "collisionBitMask": 0, "intersectionTestBitMask": -1])
        let scene = try SpriteKitSceneArchive.decode(data).makeNode()
        let body = try #require(scene.children[0].physicsBody)
        #expect(body.categoryBitMask.rawValue == UInt32.max)
        #expect(body.collisionBitMask.isEmpty)
        #expect(body.contactTestBitMask.rawValue == UInt32.max)
    }

    @Test func validatesPolygonGeometry() throws {
        func body(_ points: [Vector2], curve: Bool = false) throws -> ArchivePhysicsBody {
            let graph = try KeyedArchive(ArchivePropertyList.decode(Data(contentsOf: Fixtures.url("SceneArchives/physics.xml"))))
            let bodyClass = try #require(graph.objects.firstIndex { $0.dictionary?["$classname"]?.string == "PKPhysicsBody" })
            let dictionaryClass = try #require(graph.objects.firstIndex { $0.dictionary?["$classname"]?.string == "NSDictionary" })
            let elements: [PropertyValue] = points.enumerated().map { index, point in
                .dictionary(["$class": .uid(dictionaryClass), "NS.keys": .array([.string("type"), .string("points")]),
                    "NS.objects": .array([.number(index == 0 ? 0 : (curve ? 2 : 1)),
                        .array([.string("{\(point.x), \(point.y)}")])])])
            }
            return try ArchivePhysicsBody(.dictionary(["$class": .uid(bodyClass),
                "_shapeType": .number(3), "_path": .array(elements)]), graph: graph)
        }
        for points: [Vector2] in [[], [[0, 0], [1, 1], [2, 2]],
            [[0, 0], [0, 10], [10, 0]], [[0, 0], [10, 0], [2, 2], [0, 10]]] {
            #expect(throws: SceneArchiveError.self) { try body(points) }
        }
        #expect(throws: SceneArchiveError.self) { try body([[0, 0], [10, 0], [0, 10]], curve: true) }
        #expect(try body([[0, 0], [10, 0], [0, 10]]).shape == .polygon([[0, 0], [10, 0], [0, 10]]))
    }

    @Test func rejectsScaledPhysicsHierarchy() throws {
        for name in ["SKScene", "SKNode"] {
            let data = try mutated(name, changes: ["_xScale": 2])
            #expect(throws: SceneArchiveError.unsupported("Physics bodies under scaled nodes")) {
                try SpriteKitSceneArchive.decode(data)
            }
        }
    }
}
