//
//  PhysicsWorld.swift
//  SpritePhysics
//

import CBox2D
import SpriteCore

/// Simulates rigid bodies and joints using Box2D v3 with a fixed timestep.
///
/// Units are scene units (points) and seconds, with ``pointsPerMeter`` points per
/// meter. The default gravity of `(0, -980)` is 9.8 m/s².
public final class PhysicsWorld {

    /// Length scale passed to Box2D (`b2SetLengthUnitsPerMeter`).
    ///
    /// - Note: This is process-wide Box2D state.
    public static let pointsPerMeter: Float = 100

    let worldID: b2WorldId

    // MARK: - Configuration

    public var gravity: Vector2 {
        get { Vector2(b2World_GetGravity(worldID)) }
        set { b2World_SetGravity(worldID, b2Vec2(newValue)) }
    }

    /// Multiplier applied to elapsed time in ``simulate(elapsed:)``.
    public var speed: Float = 1

    /// Duration of each step in seconds.
    public var fixedTimeStep: Double = 1.0 / 60.0

    /// Upper bound on steps per ``simulate(elapsed:)`` call, to avoid a spiral of death.
    public var maxStepsPerUpdate = 8

    /// Box2D solver substeps per step.
    public var subStepCount = 4

    /// Closing speed below which collisions do not bounce.
    public var restitutionThreshold: Float = 100 {
        didSet { b2World_SetRestitutionThreshold(worldID, restitutionThreshold) }
    }

    // MARK: - Contact handlers

    /// Called when two bodies start touching (subject to contact test masks).
    public var onContactBegin: ((PhysicsContact) -> Void)?

    /// Called when two bodies stop touching.
    public var onContactEnd: ((PhysicsContact) -> Void)?

    // MARK: - State

    /// Bodies in the world. Assigning replaces the set of simulated bodies.
    public var bodies: [PhysicsBody] = [] {
        didSet { bodiesDidChange(oldValue) }
    }

    public private(set) var joints: [PhysicsJoint] = []

    private var accumulator: Double = 0

    /// Number of touching shape pairs per body pair, from contact and sensor events.
    private var touchCounts: [BodyPair: Int] = [:]

    public init() {
        _ = configureBox2DUnits
        var definition = b2DefaultWorldDef()
        definition.gravity = b2Vec2(x: 0, y: -980)
        definition.restitutionThreshold = restitutionThreshold
        worldID = b2CreateWorld(&definition)
    }

    deinit {
        // Destroying the world destroys all Box2D bodies; detach to keep Swift state.
        for body in bodies {
            body.detach()
            body.world = nil
        }
        b2DestroyWorld(worldID)
    }

    // MARK: - Bodies & joints

    public func add(_ body: PhysicsBody) {
        guard !bodies.contains(where: { $0 === body }) else { return }
        bodies.append(body)
    }

    public func remove(_ body: PhysicsBody) {
        bodies.removeAll { $0 === body }
    }

    /// Adds a joint; it takes effect once both of its bodies are in this world.
    public func add(_ joint: PhysicsJoint) {
        guard !joints.contains(where: { $0 === joint }) else { return }
        joints.append(joint)
        realizeJoints()
    }

    public func remove(_ joint: PhysicsJoint) {
        joints.removeAll { $0 === joint }
        joint.destroy()
    }

    public func removeAllJoints() {
        joints.forEach { $0.destroy() }
        joints.removeAll()
    }

    private func bodiesDidChange(_ oldValue: [PhysicsBody]) {
        let current = Set(bodies.map(ObjectIdentifier.init))
        let previous = Set(oldValue.map(ObjectIdentifier.init))
        for body in oldValue where !current.contains(ObjectIdentifier(body)) {
            // Box2D destroys a body's joints along with it.
            for joint in joints where joint.bodyA === body || joint.bodyB === body {
                joint.invalidate()
            }
            body.detach()
            body.world = nil
            let id = ObjectIdentifier(body)
            touchCounts = touchCounts.filter { $0.key.a != id && $0.key.b != id }
        }
        for body in bodies where !previous.contains(ObjectIdentifier(body)) {
            if let other = body.world, other !== self {
                other.remove(body)
            }
            body.world = self
            body.attach(to: worldID)
        }
        realizeJoints()
    }

    private func realizeJoints() {
        for joint in joints where joint.bodyA.world === self && joint.bodyB.world === self {
            joint.create(in: worldID)
        }
    }

    // MARK: - Simulation

    /// Advances by `elapsed` seconds (scaled by ``speed``) in fixed steps.
    public func simulate(elapsed: Double) {
        accumulator += elapsed * Double(speed)
        var steps = 0
        while accumulator >= fixedTimeStep, steps < maxStepsPerUpdate {
            step(fixedTimeStep)
            accumulator -= fixedTimeStep
            steps += 1
        }
        if steps == maxStepsPerUpdate {
            accumulator = min(accumulator, fixedTimeStep)
        }
    }

    /// Performs a single step of `dt` seconds.
    public func step(_ dt: Double) {
        guard dt > 0 else { return }
        b2World_Step(worldID, Float(dt), Int32(subStepCount))
        dispatchEvents()
    }

    // MARK: - Contact events

    struct BodyPair: Hashable {
        let a: ObjectIdentifier
        let b: ObjectIdentifier

        init(_ x: PhysicsBody, _ y: PhysicsBody) {
            let (i, j) = (ObjectIdentifier(x), ObjectIdentifier(y))
            (a, b) = i < j ? (i, j) : (j, i)
        }
    }

    private enum TouchEvent {
        case begin(PhysicsContact)
        case end(PhysicsContact)
    }

    static func testsContact(_ a: PhysicsBody, _ b: PhysicsBody) -> Bool {
        a.contactTestBitMask.intersects(b.categoryBitMask) || b.contactTestBitMask.intersects(a.categoryBitMask)
    }

    /// Converts Box2D contact and sensor events into body-level begin/end notifications.
    private func dispatchEvents() {
        var events = [TouchEvent]()

        func touch(_ a: PhysicsBody, _ b: PhysicsBody, began: Bool, contact: () -> PhysicsContact) {
            let pair = BodyPair(a, b)
            let count = touchCounts[pair, default: 0]
            if began {
                touchCounts[pair] = count + 1
                if count == 0, Self.testsContact(a, b) { events.append(.begin(contact())) }
            } else if count > 0 {
                touchCounts[pair] = count > 1 ? count - 1 : nil
                if count == 1, Self.testsContact(a, b) { events.append(.end(contact())) }
            }
        }

        let contactEvents = b2World_GetContactEvents(worldID)
        for i in 0 ..< Int(contactEvents.beginCount) {
            let event = contactEvents.beginEvents[i]
            guard let a = PhysicsBody.from(shape: event.shapeIdA), let b = PhysicsBody.from(shape: event.shapeIdB) else { continue }
            touch(a, b, began: true) { Self.makeContact(a, b, contact: event.contactId) }
        }
        for i in 0 ..< Int(contactEvents.endCount) {
            let event = contactEvents.endEvents[i]
            guard let a = PhysicsBody.from(shape: event.shapeIdA), let b = PhysicsBody.from(shape: event.shapeIdB) else { continue }
            touch(a, b, began: false) { Self.makeContact(a, b) }
        }

        let sensorEvents = b2World_GetSensorEvents(worldID)
        for i in 0 ..< Int(sensorEvents.beginCount) {
            let event = sensorEvents.beginEvents[i]
            guard let a = PhysicsBody.from(shape: event.sensorShapeId), let b = PhysicsBody.from(shape: event.visitorShapeId) else { continue }
            touch(a, b, began: true) { Self.makeContact(a, b) }
        }
        for i in 0 ..< Int(sensorEvents.endCount) {
            let event = sensorEvents.endEvents[i]
            guard let a = PhysicsBody.from(shape: event.sensorShapeId), let b = PhysicsBody.from(shape: event.visitorShapeId) else { continue }
            touch(a, b, began: false) { Self.makeContact(a, b) }
        }

        // Handlers run after Box2D's event buffers are consumed, so they may modify the world.
        for event in events {
            switch event {
            case let .begin(contact): onContactBegin?(contact)
            case let .end(contact): onContactEnd?(contact)
            }
        }
    }

    /// Builds a contact from Box2D manifold data, or an approximation for sensors and ended contacts.
    private static func makeContact(_ a: PhysicsBody, _ b: PhysicsBody, contact: b2ContactId? = nil) -> PhysicsContact {
        if let contact, b2Contact_IsValid(contact) {
            let data = b2Contact_GetData(contact)
            let manifold = data.manifold
            let points = withUnsafeBytes(of: manifold.points) { buffer in
                Array(buffer.bindMemory(to: b2ManifoldPoint.self).prefix(Int(manifold.pointCount)))
            }
            // Box2D may order the shapes differently than the event.
            let bodyA = PhysicsBody.from(shape: data.shapeIdA) ?? a
            let bodyB = PhysicsBody.from(shape: data.shapeIdB) ?? b
            let center = bodyA.worldCenter
            let point = points.isEmpty
                ? (bodyA.position + bodyB.position) * 0.5
                : points.reduce(Vector2.zero) { $0 + center + Vector2($1.anchorA) } / Float(points.count)
            return PhysicsContact(
                bodyA: bodyA,
                bodyB: bodyB,
                contactPoint: point,
                contactNormal: Vector2(manifold.normal),
                collisionImpulse: points.reduce(0) { $0 + $1.totalNormalImpulse }
            )
        }
        return PhysicsContact(
            bodyA: a,
            bodyB: b,
            contactPoint: b.position,
            contactNormal: normalize(b.position - a.position),
            collisionImpulse: 0
        )
    }

    // MARK: - Queries

    /// Closest body hit by the segment `start → end` whose category intersects `mask`.
    public func rayCast(from start: Vector2, to end: Vector2, mask: PhysicsCategory = .all) -> RayHit? {
        rayCastAll(from: start, to: end, mask: mask).first
    }

    /// All bodies hit by the segment `start → end`, nearest first (one hit per body).
    public func rayCastAll(from start: Vector2, to end: Vector2, mask: PhysicsCategory = .all) -> [RayHit] {
        final class Collector {
            var hits: [(shape: b2ShapeId, point: Vector2, normal: Vector2, fraction: Float)] = []
        }
        let collector = Collector()
        let filter = b2QueryFilter(categoryBits: .max, maskBits: mask.box2DBits)
        withExtendedLifetime(collector) {
            _ = b2World_CastRay(
                worldID,
                b2Vec2(start),
                b2Vec2(end - start),
                filter,
                { shape, point, normal, fraction, context in
                    let collector = Unmanaged<Collector>.fromOpaque(context!).takeUnretainedValue()
                    collector.hits.append((shape, Vector2(point), Vector2(normal), fraction))
                    // Keep searching the full ray.
                    return 1
                },
                Unmanaged.passUnretained(collector).toOpaque()
            )
        }
        var closest = [ObjectIdentifier: RayHit]()
        for hit in collector.hits {
            guard let body = PhysicsBody.from(shape: hit.shape) else { continue }
            let id = ObjectIdentifier(body)
            if hit.fraction < closest[id]?.fraction ?? .infinity {
                closest[id] = RayHit(body: body, point: hit.point, normal: hit.normal, fraction: hit.fraction)
            }
        }
        return closest.values.sorted { $0.fraction < $1.fraction }
    }

    /// First body containing a world point.
    public func body(at point: Vector2) -> PhysicsBody? {
        bodies.first { $0.contains(point) }
    }

    /// All bodies containing a world point.
    public func bodies(at point: Vector2) -> [PhysicsBody] {
        bodies.filter { $0.contains(point) }
    }

    /// Bodies whose bounds intersect a world rectangle.
    public func bodies(in rect: Rect) -> [PhysicsBody] {
        bodies.filter { body in
            guard let bounds = body.bounds else { return false }
            return bounds.minX <= rect.maxX && rect.minX <= bounds.maxX && bounds.minY <= rect.maxY && rect.minY <= bounds.maxY
        }
    }
}
