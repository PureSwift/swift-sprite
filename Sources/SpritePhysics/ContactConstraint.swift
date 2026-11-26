//
//  ContactConstraint.swift
//  SpritePhysics
//
//  Soft-step contact solver adapted from Box2D v3 (MIT License, Copyright 2023 Erin Catto).
//

import SpriteCore

/// Identifies a pair of convex parts on two bodies across steps.
struct ContactKey: Hashable {
    let bodyA: ObjectIdentifier
    let bodyB: ObjectIdentifier
    let partA: Int
    let partB: Int
}

/// Contact constraint between two parts with warm starting, soft position
/// correction, relaxation and restitution.
final class ContactConstraint {

    struct Point {
        var position: Vector2
        /// Separation when the manifold was computed.
        var separation: Float
        var id: UInt32
        /// Offsets from each center of mass at the start of the step.
        var anchorA: Vector2 = .zero
        var anchorB: Vector2 = .zero
        /// `separation - dot(anchorB - anchorA, normal)`, for tracking separation as bodies move.
        var baseSeparation: Float = 0
        var normalImpulse: Float = 0
        var tangentImpulse: Float = 0
        var maxNormalImpulse: Float = 0
        var normalMass: Float = 0
        var tangentMass: Float = 0
        /// Normal velocity at the start of the step, used for restitution.
        var relativeVelocity: Float = 0
    }

    let bodyA: PhysicsBody
    let bodyB: PhysicsBody
    let normal: Vector2
    var points: [Point]

    /// Whether the solver resolves this contact (vs. only reporting it).
    let collides: Bool

    /// Per-body response, honoring asymmetric collision masks.
    let affectsA: Bool
    let affectsB: Bool

    let friction: Float
    let restitution: Float

    private var invMassA: Float = 0
    private var invMassB: Float = 0
    private var invInertiaA: Float = 0
    private var invInertiaB: Float = 0
    private var startCenterA: Vector2 = .zero
    private var startCenterB: Vector2 = .zero
    private var startRotationA: Float = 0
    private var startRotationB: Float = 0
    private var softness = Softness.rigid

    init(bodyA: PhysicsBody, bodyB: PhysicsBody, manifold: Manifold, affectsA: Bool, affectsB: Bool) {
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.normal = manifold.normal
        self.points = manifold.points.map { Point(position: $0.position, separation: $0.separation, id: $0.id) }
        self.affectsA = affectsA
        self.affectsB = affectsB
        self.collides = affectsA || affectsB
        self.friction = (bodyA.friction * bodyB.friction).squareRoot()
        self.restitution = max(bodyA.restitution, bodyB.restitution)
    }

    /// Whether the surfaces are actually touching (not just within the speculative margin).
    func isTouching(slop: Float) -> Bool {
        points.contains { $0.separation <= slop }
    }

    /// Copies accumulated impulses from the previous step's matching points.
    func warmStart(from previous: ContactConstraint) {
        for i in points.indices {
            if let old = previous.points.first(where: { $0.id == points[i].id }) {
                points[i].normalImpulse = old.normalImpulse
                points[i].tangentImpulse = old.tangentImpulse
            }
        }
    }

    private var tangent: Vector2 {
        Vector2(normal.y, -normal.x)
    }

    /// Computes anchors, effective masses and pre-solve velocities. Call before integrating velocities.
    func prepare(context: SolverContext) {
        invMassA = affectsA ? bodyA.invMass : 0
        invMassB = affectsB ? bodyB.invMass : 0
        invInertiaA = affectsA ? bodyA.invInertia : 0
        invInertiaB = affectsB ? bodyB.invInertia : 0
        startCenterA = bodyA.worldCenter
        startCenterB = bodyB.worldCenter
        startRotationA = bodyA.rotation
        startRotationB = bodyB.rotation
        softness = (invMassA == 0 || invMassB == 0) ? context.staticSoftness : context.contactSoftness

        let mA = invMassA, mB = invMassB, iA = invInertiaA, iB = invInertiaB
        for i in points.indices {
            var p = points[i]
            p.anchorA = p.position - startCenterA
            p.anchorB = p.position - startCenterB
            p.baseSeparation = p.separation - dot(p.anchorB - p.anchorA, normal)

            let rnA = cross(p.anchorA, normal), rnB = cross(p.anchorB, normal)
            let kNormal = mA + mB + iA * rnA * rnA + iB * rnB * rnB
            p.normalMass = kNormal > 0 ? 1 / kNormal : 0

            let rtA = cross(p.anchorA, tangent), rtB = cross(p.anchorB, tangent)
            let kTangent = mA + mB + iA * rtA * rtA + iB * rtB * rtB
            p.tangentMass = kTangent > 0 ? 1 / kTangent : 0

            p.maxNormalImpulse = 0
            p.relativeVelocity = dot(relativeVelocity(p), normal)
            points[i] = p
        }
    }

    /// Applies accumulated impulses at the start of a substep.
    func warmStart() {
        for p in points {
            apply(p.normalImpulse * normal + p.tangentImpulse * tangent, p)
        }
    }

    /// - Parameter useBias: Include soft position correction; the relax pass omits it so
    ///   push-apart velocity does not persist as kinetic energy.
    func solve(context: SolverContext, useBias: Bool) {
        // Motion of each body since the start of the step, for tracking separation.
        let deltaA = bodyA.worldCenter - startCenterA
        let deltaB = bodyB.worldCenter - startCenterB
        let rotationA = Rotation(bodyA.rotation - startRotationA)
        let rotationB = Rotation(bodyB.rotation - startRotationB)

        for i in points.indices {
            var p = points[i]

            // Current separation from body displacement since the manifold was computed.
            let d = (deltaB - deltaA) + (rotationB.apply(p.anchorB) - rotationA.apply(p.anchorA))
            let separation = dot(d, normal) + p.baseSeparation

            var bias: Float = 0
            var massScale: Float = 1
            var impulseScale: Float = 0
            if separation > 0 {
                // Speculative: allow closing exactly the remaining gap this substep.
                bias = separation * context.invH
            } else if useBias {
                bias = max(softness.biasRate * separation, -context.maxBiasVelocity)
                massScale = softness.massScale
                impulseScale = softness.impulseScale
            }

            let normalVelocity = dot(relativeVelocity(p), normal)
            let impulse = -p.normalMass * massScale * (normalVelocity + bias) - impulseScale * p.normalImpulse
            let newImpulse = max(p.normalImpulse + impulse, 0)
            apply((newImpulse - p.normalImpulse) * normal, p)
            p.normalImpulse = newImpulse
            p.maxNormalImpulse = max(p.maxNormalImpulse, newImpulse)
            points[i] = p
        }

        // Friction, bounded by the Coulomb cone of the current normal impulse.
        for i in points.indices {
            var p = points[i]
            let tangentVelocity = dot(relativeVelocity(p), tangent)
            let maxFriction = friction * p.normalImpulse
            let newImpulse = min(max(p.tangentImpulse - p.tangentMass * tangentVelocity, -maxFriction), maxFriction)
            apply((newImpulse - p.tangentImpulse) * tangent, p)
            p.tangentImpulse = newImpulse
            points[i] = p
        }
    }

    /// Re-solves impacting points so they separate at `restitution × approach speed`.
    func applyRestitution(threshold: Float) {
        guard restitution > 0 else { return }
        for i in points.indices {
            var p = points[i]
            guard p.relativeVelocity < -threshold, p.maxNormalImpulse > 0 else { continue }
            let normalVelocity = dot(relativeVelocity(p), normal)
            let impulse = -p.normalMass * (normalVelocity + restitution * p.relativeVelocity)
            let newImpulse = max(p.normalImpulse + impulse, 0)
            apply((newImpulse - p.normalImpulse) * normal, p)
            p.normalImpulse = newImpulse
            p.maxNormalImpulse = max(p.maxNormalImpulse, newImpulse)
            points[i] = p
        }
    }

    private func relativeVelocity(_ p: Point) -> Vector2 {
        bodyB.velocity + cross(bodyB.angularVelocity, p.anchorB)
            - bodyA.velocity - cross(bodyA.angularVelocity, p.anchorA)
    }

    private func apply(_ impulse: Vector2, _ p: Point) {
        bodyA.velocity -= invMassA * impulse
        bodyA.angularVelocity -= invInertiaA * cross(p.anchorA, impulse)
        bodyB.velocity += invMassB * impulse
        bodyB.angularVelocity += invInertiaB * cross(p.anchorB, impulse)
    }

    /// Sum of the largest normal impulses applied at each point during the step.
    var totalNormalImpulse: Float {
        points.reduce(0) { $0 + $1.maxNormalImpulse }
    }
}
