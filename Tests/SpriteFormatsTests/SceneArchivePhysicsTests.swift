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

    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresCompoundPhysics(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf:
            Fixtures.url("SceneArchives/compound-physics." + format)))
        let scene = try #require(archive.makeNode() as? Scene)
        let body = try #require(scene.children.first?.physicsBody)
        guard case let .compound(shapes) = body.shape else {
            Issue.record("Expected compound body")
            return
        }
        #expect(shapes.count == 2)
        #expect(shapes[0] == .circle(radius: 12, center: [2, 3]))
        guard case let .polygon(points) = shapes[1] else {
            Issue.record("Expected polygon component")
            return
        }
        let expected: [Vector2] = [[25, -5], [55, -5], [55, 15], [25, 15]]
        #expect(points.count == expected.count)
        for (point, target) in zip(points, expected) {
            #expect(abs(point.x - target.x) < 0.00001 && abs(point.y - target.y) < 0.00001)
        }
        #expect(abs(body.mass - 2) < 0.00001)
        scene.advance(by: .seconds(1.0 / 60))
        #expect(scene.physicsWorld.rayCast(from: [2, 30], to: [2, -30])?.body === body)
        #expect(scene.physicsWorld.rayCast(from: [40, 30], to: [40, -30])?.body === body)
        #expect(scene.physicsWorld.rayCast(from: [20, 30], to: [20, -30]) == nil)
        for _ in 0..<59 { scene.advance(by: .seconds(1.0 / 60)) }
        #expect(abs(scene.children[0].position.x - 10) < 0.01)
        let other = try archive.makeNode()
        #expect(other.children[0].physicsBody !== body)
        #expect(other.children[0].position == .zero)
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresEdgePhysics(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf:
            Fixtures.url("SceneArchives/edge-physics." + format)))
        let scene = try #require(archive.makeNode() as? Scene)
        let shapes: [PhysicsShape] = [
            .edge(from: [2, 3], to: [40, 5]),
            .edgeChain([[10, 20], [40, 20], [40, 60]]),
            .edgeLoop([[10, 20], [40, 20], [40, 60]]),
            .edgeLoop([[10, 20], [40, 20], [40, 60], [10, 60]])
        ]
        for (node, shape) in zip(scene.children, shapes) {
            let body = try #require(node.physicsBody)
            #expect(body.shape == shape)
            #expect(!body.isDynamic && body.area == 0)
        }
        for _ in 0..<60 { scene.advance(by: .seconds(1.0 / 60)) }
        for (index, node) in scene.children.enumerated() {
            #expect(node.position == [Float(index * 100), 0])
            #expect(node.zRotation == 0)
        }
        let world = scene.physicsWorld
        #expect(world.rayCast(from: [20, 10], to: [20, 0])?.body === scene.children[0].physicsBody)
        // The open chain has no closing diagonal, while the loop does.
        #expect(world.rayCast(from: [105, 40], to: [135, 40]) == nil)
        #expect(world.rayCast(from: [205, 40], to: [235, 40])?.body === scene.children[2].physicsBody)
        #expect(world.rayCast(from: [305, 40], to: [315, 40])?.body === scene.children[3].physicsBody)
        #expect(world.rayCast(from: [315, 40], to: [305, 40])?.body === scene.children[3].physicsBody)
    }

    @Test func rejectsMalformedEdges() throws {
        for changes: [String: Any] in [
            ["_p1": "{2, 3}"], ["_p1": "{1000001, 0}"], ["_p1": "{nan, 0}"],
            ["_p1": ["TestUID": 0]], ["_p0": ["TestUID": 0]],
            ["_shapeType": 5], ["_shapeType": 6]
        ] {
            let data = try mutated("PKPhysicsBody", changes: changes, fixture: "edge-physics")
            #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(data) }
        }
    }

    @Test func rejectsMalformedCompoundPhysics() throws {
        for changes: [String: Any] in [
            ["_compoundBodyCount": 0], ["_compoundBodyCount": -1],
            ["_compoundBodyCount": 1.5], ["_compoundBodyCount": 257],
            ["_compoundBodyCount": 1], ["_compoundBodyCount": 3],
            ["$0": "edge"], ["$1": "{0, 0}"], ["$1": "{12, 1}"],
            ["$2": "{1000001, 0}"], ["$4": ["TestUID": 99999]],
            ["$4": ["TestUID": 0]], ["$5": "unexpected"]
        ] {
            let data = try mutated("PKPhysicsBody", changes: changes, fixture: "compound-physics")
            #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(data) }
        }
    }

    private func mutated(_ className: String, changes: [String: Any], fixture: String = "physics") throws -> Data {
        let data = try Data(contentsOf: Fixtures.url("SceneArchives/" + fixture + ".xml"))
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

    @MainActor @Test func restoresContinuousCollisionDetection() throws {
        for enabled in [false, true] {
            let data = try mutated("PKPhysicsBody", changes: ["needsContinuousCollsionDetection": enabled])
            let scene = try SpriteKitSceneArchive.decode(data).makeNode()
            #expect(scene.children[0].physicsBody?.usesContinuousCollisionDetection == enabled)
            #expect(scene.children[1].physicsBody?.usesContinuousCollisionDetection == false)
        }
        let invalid = try mutated("PKPhysicsBody", changes: ["needsContinuousCollsionDetection": "yes"])
        #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(invalid) }
    }

    @Test func rejectsUnsupportedPhysics() throws {
        for changes: [String: Any] in [["_shapeType": 99], ["pinned": true],
            ["charge": 1]] {
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

    @Test func validatesPathGeometry() throws {
        func body(_ points: [Vector2], curve: Bool = false, shapeType: Double = 3) throws -> ArchivePhysicsBody {
            let graph = try KeyedArchive(ArchivePropertyList.decode(Data(contentsOf: Fixtures.url("SceneArchives/physics.xml"))))
            let bodyClass = try #require(graph.objects.firstIndex { $0.dictionary?["$classname"]?.string == "PKPhysicsBody" })
            let dictionaryClass = try #require(graph.objects.firstIndex { $0.dictionary?["$classname"]?.string == "NSDictionary" })
            let elements: [PropertyValue] = points.enumerated().map { index, point in
                .dictionary(["$class": .uid(dictionaryClass), "NS.keys": .array([.string("type"), .string("points")]),
                    "NS.objects": .array([.number(index == 0 ? 0 : (curve ? 2 : 1)),
                        .array([.string("{\(point.x), \(point.y)}")])])])
            }
            return try ArchivePhysicsBody(.dictionary(["$class": .uid(bodyClass),
                "_shapeType": .number(shapeType), "_path": .array(elements)]), graph: graph)
        }
        for points: [Vector2] in [[], [[0, 0], [1, 1], [2, 2]],
            [[0, 0], [0, 10], [10, 0]], [[0, 0], [10, 0], [2, 2], [0, 10]]] {
            #expect(throws: SceneArchiveError.self) { try body(points) }
        }
        #expect(throws: SceneArchiveError.self) { try body([[0, 0], [10, 0], [0, 10]], curve: true) }
        #expect(try body([[0, 0], [10, 0], [0, 10]]).shape == .polygon([[0, 0], [10, 0], [0, 10]]))
        for type: Double in [5, 6] {
            for points: [Vector2] in [[], [[0, 0]], [[0, 0], [0, 0], [10, 0]],
                [[0, 0], [10, 0], [0, 1_000_001]], Array(repeating: [0, 0], count: 1026)] {
                #expect(throws: SceneArchiveError.self) { try body(points, shapeType: type) }
            }
            #expect(throws: SceneArchiveError.self) {
                try body([[0, 0], [10, 0], [0, 10]], curve: true, shapeType: type)
            }
        }
        let concave: [Vector2] = [[0, 0], [10, 0], [2, 2], [0, 10]]
        #expect(try body(concave, shapeType: 6).shape == .edgeLoop(concave))
        #expect(try body([[0, 0], [10, 0]], shapeType: 5).shape == .edgeChain([[0, 0], [10, 0]]))
        #expect(throws: SceneArchiveError.self) { try body([[0, 0], [10, 0]], shapeType: 6) }
        let closed: [Vector2] = [[0, 0], [10, 0], [0, 10], [0, 0]]
        #expect(try body(closed, shapeType: 5).shape == .edgeChain(closed))
        #expect(try body(closed, shapeType: 6).shape == .edgeLoop(Array(closed.dropLast())))
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
