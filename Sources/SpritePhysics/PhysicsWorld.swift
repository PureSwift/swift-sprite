//
//  PhysicsWorld.swift
//  SpritePhysics
//

import SpriteCore

/// Simulates rigid bodies and joints with a fixed-timestep impulse solver.
///
/// Units are scene units (points) and seconds. The default gravity of
/// `(0, -980)` treats 100 points as one meter.
public final class PhysicsWorld {

    // MARK: - Configuration

    public var gravity = Vector2(0, -980)

    /// Multiplier applied to elapsed time in ``simulate(elapsed:)``.
    public var speed: Float = 1

    /// Duration of each internal step in seconds.
    public var fixedTimeStep: Double = 1.0 / 60.0

    /// Upper bound on steps per ``simulate(elapsed:)`` call, to avoid a spiral of death.
    public var maxStepsPerUpdate = 8

    public var velocityIterations = 8

    /// Iterations after position integration that remove position-correction velocity.
    public var relaxIterations = 3

    /// Penetration allowed before position correction, in scene units.
    public var linearSlop: Float = 0.5

    /// Contacts are created this far before surfaces touch, preventing tunneling at rest.
    public var speculativeMargin: Float = 2

    /// Closing speed below which collisions do not bounce.
    public var restitutionThreshold: Float = 100

    // MARK: - Contact handlers

    /// Called when two bodies start touching (subject to contact test masks).
    public var onContactBegin: ((PhysicsContact) -> Void)?

    /// Called when two bodies stop touching.
    public var onContactEnd: ((PhysicsContact) -> Void)?

    // MARK: - State

    /// Bodies in simulation order. Assigning replaces the set of simulated bodies.
    public var bodies: [PhysicsBody] = [] {
        didSet { bodiesDidChange(oldValue) }
    }

    public private(set) var joints: [PhysicsJoint] = []

    private var accumulator: Double = 0

    private(set) var constraints: [ContactKey: ContactConstraint] = [:]

    /// Body pairs touching after the last step, for begin/end events.
    private var touching: [BodyPair: PhysicsContact] = [:]

    public init() { }

    // MARK: - Bodies & joints

    public func add(_ body: PhysicsBody) {
        guard !bodies.contains(where: { $0 === body }) else { return }
        bodies.append(body)
    }

    public func remove(_ body: PhysicsBody) {
        bodies.removeAll { $0 === body }
    }

    public func add(_ joint: PhysicsJoint) {
        guard !joints.contains(where: { $0 === joint }) else { return }
        joints.append(joint)
    }

    public func remove(_ joint: PhysicsJoint) {
        joints.removeAll { $0 === joint }
    }

    public func removeAllJoints() {
        joints.removeAll()
    }

    private func bodiesDidChange(_ oldValue: [PhysicsBody]) {
        let current = Set(bodies.map(ObjectIdentifier.init))
        for body in oldValue where !current.contains(ObjectIdentifier(body)) {
            body.world = nil
        }
        for body in bodies {
            body.world = self
        }
        constraints = constraints.filter { current.contains($0.key.bodyA) && current.contains($0.key.bodyB) }
        touching = touching.filter { current.contains($0.key.a) && current.contains($0.key.b) }
    }

    /// Bodies currently touching `body`.
    func contactedBodies(of body: PhysicsBody) -> [PhysicsBody] {
        touching.values.compactMap { $0.other(than: body) }
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
        let dt = Float(dt)
        let invDt = 1 / dt
        let settings = SolverSettings(linearSlop: linearSlop, restitutionThreshold: restitutionThreshold)

        integrateForces(dt)
        let contacts = findContacts()
        let colliding = contacts.values.filter(\.collides)
        // Joints only act once both of their bodies are in this world.
        let joints = joints.filter { $0.bodyA.world === self && $0.bodyB.world === self }

        for contact in colliding {
            contact.prepare(invDt: invDt, settings: settings)
        }
        for joint in joints {
            joint.prepare(dt: dt, settings: settings)
        }
        for _ in 0 ..< velocityIterations {
            for joint in joints {
                joint.solve(useBias: true)
            }
            for contact in colliding {
                contact.solve(useBias: true)
            }
        }

        integrateVelocities(dt)

        // Relax: re-solve without position correction so push-apart velocity does not
        // persist into the next step (and get amplified by restitution).
        for _ in 0 ..< relaxIterations {
            for joint in joints {
                joint.solve(useBias: false)
            }
            for contact in colliding {
                contact.solve(useBias: false)
            }
        }
        for contact in colliding {
            contact.applyRestitution(threshold: restitutionThreshold)
        }

        constraints = contacts
        dispatchContactEvents(contacts)
    }

    private func integrateForces(_ dt: Float) {
        for body in bodies {
            defer {
                body.force = .zero
                body.torque = 0
            }
            guard body.isDynamic, body.invMass > 0 else { continue }
            var acceleration = body.force * body.invMass
            if body.affectedByGravity {
                acceleration += gravity * body.gravityScale
            }
            body.velocity += acceleration * dt
            body.angularVelocity += body.torque * body.invInertia * dt
            body.velocity *= 1 / (1 + dt * body.linearDamping)
            body.angularVelocity *= 1 / (1 + dt * body.angularDamping)
            if !body.allowsRotation {
                body.angularVelocity = 0
            }
        }
    }

    private func integrateVelocities(_ dt: Float) {
        for body in bodies where body.isDynamic && body.invMass > 0 {
            let center = body.worldCenter + body.velocity * dt
            body.rotation += body.angularVelocity * dt
            body.worldCenter = center
        }
    }

    // MARK: - Collision detection

    private struct Proxy {
        let body: Int
        let part: Int
        let shape: ConvexPart
        let bounds: Rect
    }

    /// Broadphase sweep-and-prune on x, then narrowphase on overlapping pairs.
    private func findContacts() -> [ContactKey: ContactConstraint] {
        var proxies = [Proxy]()
        for (bodyIndex, body) in bodies.enumerated() {
            let transform = body.transform
            for (partIndex, part) in body.parts.enumerated() {
                let shape = part.transformed(by: transform)
                proxies.append(Proxy(
                    body: bodyIndex,
                    part: partIndex,
                    shape: shape,
                    bounds: shape.bounds.insetBy(dx: -speculativeMargin, dy: -speculativeMargin)
                ))
            }
        }
        proxies.sort { $0.bounds.minX < $1.bounds.minX }

        var contacts = [ContactKey: ContactConstraint]()
        for i in proxies.indices {
            let p = proxies[i]
            for j in (i + 1) ..< proxies.count {
                let q = proxies[j]
                if q.bounds.minX > p.bounds.maxX { break }
                guard p.body != q.body,
                      q.bounds.minY <= p.bounds.maxY, p.bounds.minY <= q.bounds.maxY else { continue }
                // Order pairs by body index for stable keys.
                let (first, second) = p.body < q.body ? (p, q) : (q, p)
                let a = bodies[first.body], b = bodies[second.body]
                let affectsA = a.invMass > 0 && a.collisionBitMask.intersects(b.categoryBitMask)
                let affectsB = b.invMass > 0 && b.collisionBitMask.intersects(a.categoryBitMask)
                guard affectsA || affectsB || Self.testsContact(a, b) else { continue }
                guard let manifold = collide(first.shape, second.shape, margin: speculativeMargin) else { continue }

                let key = ContactKey(
                    bodyA: ObjectIdentifier(a),
                    bodyB: ObjectIdentifier(b),
                    partA: first.part,
                    partB: second.part
                )
                let constraint = ContactConstraint(bodyA: a, bodyB: b, manifold: manifold, affectsA: affectsA, affectsB: affectsB)
                if let previous = constraints[key] {
                    constraint.warmStart(from: previous)
                }
                contacts[key] = constraint
            }
        }
        return contacts
    }

    static func testsContact(_ a: PhysicsBody, _ b: PhysicsBody) -> Bool {
        a.contactTestBitMask.intersects(b.categoryBitMask) || b.contactTestBitMask.intersects(a.categoryBitMask)
    }

    // MARK: - Contact events

    struct BodyPair: Hashable {
        let a: ObjectIdentifier
        let b: ObjectIdentifier
    }

    private func dispatchContactEvents(_ contacts: [ContactKey: ContactConstraint]) {
        var current = [BodyPair: PhysicsContact]()
        for (key, constraint) in contacts where constraint.isTouching(slop: linearSlop) {
            let pair = BodyPair(a: key.bodyA, b: key.bodyB)
            let impulse = constraint.totalNormalImpulse + (current[pair]?.collisionImpulse ?? 0)
            let point = constraint.points.reduce(Vector2.zero) { $0 + $1.position } / Float(constraint.points.count)
            current[pair] = PhysicsContact(
                bodyA: constraint.bodyA,
                bodyB: constraint.bodyB,
                contactPoint: point,
                contactNormal: constraint.normal,
                collisionImpulse: impulse
            )
        }
        let previous = touching
        touching = current

        if let onContactBegin {
            for (pair, contact) in current where previous[pair] == nil && Self.testsContact(contact.bodyA, contact.bodyB) {
                onContactBegin(contact)
            }
        }
        if let onContactEnd {
            for (pair, contact) in previous where current[pair] == nil && Self.testsContact(contact.bodyA, contact.bodyB) {
                onContactEnd(contact)
            }
        }
    }

    // MARK: - Queries

    /// Closest body hit by the segment `start → end` whose category intersects `mask`.
    public func rayCast(from start: Vector2, to end: Vector2, mask: PhysicsCategory = .all) -> RayHit? {
        rayCastAll(from: start, to: end, mask: mask).first
    }

    /// All bodies hit by the segment `start → end`, nearest first (one hit per body).
    public func rayCastAll(from start: Vector2, to end: Vector2, mask: PhysicsCategory = .all) -> [RayHit] {
        var hits = [RayHit]()
        for body in bodies where body.categoryBitMask.intersects(mask) {
            let transform = body.transform
            var best: (fraction: Float, normal: Vector2)?
            for part in body.parts {
                if let hit = part.transformed(by: transform).rayCast(from: start, to: end),
                   hit.fraction < (best?.fraction ?? .infinity) {
                    best = hit
                }
            }
            if let best {
                hits.append(RayHit(body: body, point: start + (end - start) * best.fraction, normal: best.normal, fraction: best.fraction))
            }
        }
        return hits.sorted { $0.fraction < $1.fraction }
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
            // Treat degenerate (edge) bounds as touching when overlapping on both axes.
            return bounds.minX <= rect.maxX && rect.minX <= bounds.maxX && bounds.minY <= rect.maxY && rect.minY <= bounds.maxY
        }
    }
}
