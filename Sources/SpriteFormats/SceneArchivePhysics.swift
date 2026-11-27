import SpriteCore
import SpritePhysics

/// Native SpriteKit archives use 150 points per meter (including density's area units).
private let archivePointsPerMeter: Float = 150

struct ArchivePhysicsWorld: Sendable {
    let gravity: Vector2
    let speed: Float

    init(_ value: PropertyValue, graph: KeyedArchive) throws {
        let fields = try graph.dictionary(value)
        guard try graph.className(fields) == "PKPhysicsWorld" else {
            throw SceneArchiveError.unsupported("Physics world class")
        }
        guard try graph.isEmpty(fields["_joints"]) else {
            throw SceneArchiveError.unsupported("Archived physics joints")
        }
        gravity = try graph.vector(fields["gravity"], default: [0, -9.8]) * archivePointsPerMeter
        speed = try graph.number(fields["speedMultiplier"], default: 1)
        guard gravity.x.isFinite, gravity.y.isFinite, speed >= 0 else {
            throw SceneArchiveError.invalid("Invalid physics world settings")
        }
    }
}

struct ArchivePhysicsBody: Sendable {
    let shape: PhysicsShape
    let density: Float
    let friction: Float
    let restitution: Float
    let linearDamping: Float
    let angularDamping: Float
    let velocity: Vector2
    let angularVelocity: Float
    let dynamic: Bool
    let affectedByGravity: Bool
    let allowsRotation: Bool
    let category: UInt32
    let collision: UInt32
    let contact: UInt32

    init(_ value: PropertyValue, graph: KeyedArchive) throws {
        let fields = try graph.dictionary(value)
        guard try graph.className(fields) == "PKPhysicsBody" else {
            throw SceneArchiveError.unsupported("Physics body class")
        }
        for key in ["pinned", "needsContinuousCollsionDetection"] {
            guard try !graph.boolean(fields[key], default: false) else {
                throw SceneArchiveError.unsupported("Physics body \(key)")
            }
        }
        guard try graph.number(fields["charge"], default: 0) == 0 else {
            throw SceneArchiveError.unsupported("Charged physics body")
        }
        switch try graph.number(fields["_shapeType"], default: -1) {
        case 1:
            let radius = try graph.number(fields["_radius"], default: 0)
            guard radius > 0, radius <= 1_000_000 else { throw SceneArchiveError.invalid("Invalid physics radius") }
            shape = .circle(radius: radius, center: try graph.vector(fields["_p0"], default: .zero))
        case 2:
            let size = try graph.vector(fields["_size"], default: .zero)
            guard size.x > 0, size.y > 0, size.x <= 1_000_000, size.y <= 1_000_000 else {
                throw SceneArchiveError.invalid("Invalid physics rectangle")
            }
            shape = .rectangle(size: size, center: try graph.vector(fields["_p0"], default: .zero))
        case 3:
            shape = .polygon(try Self.polygon(fields["_path"], graph: graph))
        default: throw SceneArchiveError.unsupported("Physics shape type")
        }
        let center = try graph.vector(fields["_p0"], default: .zero)
        guard abs(center.x) <= 1_000_000, abs(center.y) <= 1_000_000 else {
            throw SceneArchiveError.invalid("Invalid physics center")
        }
        density = try graph.number(fields["density"], default: 1) / (archivePointsPerMeter * archivePointsPerMeter)
        friction = try graph.number(fields["friction"], default: 0.2)
        restitution = try graph.number(fields["restitution"], default: 0.2)
        linearDamping = try graph.number(fields["linearDamping"], default: 0.1)
        angularDamping = try graph.number(fields["angularDamping"], default: 0.1)
        guard density > 0, density <= 1e12, friction >= 0, friction <= 1, restitution >= 0, restitution <= 1,
              linearDamping >= 0, angularDamping >= 0 else {
            throw SceneArchiveError.invalid("Invalid physics material or density")
        }
        velocity = try graph.vector(fields["linearVelocity"], default: .zero)
        angularVelocity = try graph.number(fields["angularVelocity"], default: 0)
        dynamic = try graph.boolean(fields["dynamic"], default: true)
        affectedByGravity = try graph.boolean(fields["affectedByGravity"], default: true)
        allowsRotation = try graph.boolean(fields["allowRotation"], default: true)
        category = try Self.mask(fields["categoryBitMask"], default: .max, graph: graph)
        collision = try Self.mask(fields["collisionBitMask"], default: .max, graph: graph)
        contact = try Self.mask(fields["intersectionTestBitMask"], default: 0, graph: graph)
    }

    func makeBody() -> PhysicsBody {
        let body = PhysicsBody(shape: shape)
        body.density = density
        body.friction = friction
        body.restitution = restitution
        body.linearDamping = linearDamping
        body.angularDamping = angularDamping
        body.velocity = velocity
        body.angularVelocity = angularVelocity
        body.isDynamic = dynamic
        body.affectedByGravity = affectedByGravity
        body.allowsRotation = allowsRotation
        body.categoryBitMask = PhysicsCategory(rawValue: category)
        body.collisionBitMask = PhysicsCategory(rawValue: collision)
        body.contactTestBitMask = PhysicsCategory(rawValue: contact)
        return body
    }

    private static func mask(_ value: PropertyValue?, default fallback: UInt32, graph: KeyedArchive) throws -> UInt32 {
        let value = try graph.resolve(value)
        if case .null = value { return fallback }
        // Native archives encode UInt32 masks as signed int32; do not round through Float.
        guard case let .number(number) = value, number.isFinite, number.rounded() == number,
              number >= Double(Int32.min), number <= Double(UInt32.max) else {
            throw SceneArchiveError.invalid("Invalid physics bit mask")
        }
        return number < 0 ? UInt32(bitPattern: Int32(number)) : UInt32(number)
    }

    private static func polygon(_ value: PropertyValue?, graph: KeyedArchive) throws -> [Vector2] {
        let elements = try graph.array(value)
        guard (3...1025).contains(elements.count) else { throw SceneArchiveError.invalid("Invalid physics polygon") }
        var points: [Vector2] = []
        for (index, element) in elements.enumerated() {
            let fields = try graph.dictionary(element)
            guard ["NSDictionary", "NSMutableDictionary"].contains(try graph.className(fields)) else {
                throw SceneArchiveError.unsupported("Physics path element class")
            }
            let keys = try graph.array(fields["NS.keys"])
            let values = try graph.array(fields["NS.objects"])
            guard keys.count == values.count else { throw SceneArchiveError.invalid("Invalid physics path element") }
            var entry: [String: PropertyValue] = [:]
            for (key, value) in zip(keys, values) {
                guard let name = try graph.string(key), entry[name] == nil else {
                    throw SceneArchiveError.invalid("Invalid physics path key")
                }
                entry[name] = value
            }
            let type = try graph.number(entry["type"], default: -1)
            guard type == (index == 0 ? 0 : 1) else {
                throw SceneArchiveError.unsupported("Physics polygon curves or subpaths")
            }
            let vertices = try graph.array(entry["points"])
            guard vertices.count == 1, try !graph.isNull(vertices[0]) else {
                throw SceneArchiveError.invalid("Invalid physics path point")
            }
            points.append(try graph.vector(vertices[0], default: .zero))
        }
        if points.last == points.first { points.removeLast() }
        guard points.count >= 3, points.allSatisfy({ abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else {
            throw SceneArchiveError.invalid("Invalid physics polygon")
        }
        // Require a strictly convex counterclockwise path; never silently replace it with a hull.
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            for j in points.indices where j != i && j != (i + 1) % points.count {
                let c = points[j]
                guard (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 0.000001 else {
                    throw SceneArchiveError.invalid("Physics polygon must be convex and counterclockwise")
                }
            }
        }
        return points
    }
}
