//
//  PhysicsJoint.swift
//  SpritePhysics
//
//  Joint solver adapted from Box2D v3 (MIT License, Copyright 2023 Erin Catto).
//

import SpriteCore

/// Constraint connecting two bodies, added to a ``PhysicsWorld``.
///
/// Anchors are given in world coordinates at creation and stored relative to each body.
public class PhysicsJoint {

    public let bodyA: PhysicsBody

    public let bodyB: PhysicsBody

    /// Linear impulse applied by the joint in the last step (`reactionImpulse / dt` gives the force).
    public internal(set) var reactionImpulse: Vector2 = .zero

    init(bodyA: PhysicsBody, bodyB: PhysicsBody) {
        precondition(bodyA !== bodyB, "A joint must connect two different bodies")
        self.bodyA = bodyA
        self.bodyB = bodyB
    }

    /// Called once per step before velocities are integrated.
    func prepare(context: SolverContext) { }

    /// Applies accumulated impulses at the start of a substep.
    func warmStart() { }

    /// - Parameter useBias: Include soft position correction (omitted in the relax pass).
    func solve(context: SolverContext, useBias: Bool) { }

    /// Converts a world anchor to an offset from the body's center of mass in body space.
    static func localAnchor(_ anchor: Vector2, on body: PhysicsBody) -> Vector2 {
        Rotation(body.rotation).applyInverse(anchor - body.worldCenter)
    }

    /// Applies a linear impulse at offsets `rA`, `rB` (equal and opposite).
    func apply(_ impulse: Vector2, rA: Vector2, rB: Vector2) {
        bodyA.velocity -= bodyA.invMass * impulse
        bodyA.angularVelocity -= bodyA.invInertia * cross(rA, impulse)
        bodyB.velocity += bodyB.invMass * impulse
        bodyB.angularVelocity += bodyB.invInertia * cross(rB, impulse)
    }

    /// Applies an angular impulse (equal and opposite).
    func applyAngular(_ impulse: Float) {
        bodyA.angularVelocity -= bodyA.invInertia * impulse
        bodyB.angularVelocity += bodyB.invInertia * impulse
    }

    /// Relative velocity of the anchor on B with respect to the anchor on A.
    func relativeVelocity(rA: Vector2, rB: Vector2) -> Vector2 {
        bodyB.velocity + cross(bodyB.angularVelocity, rB) - bodyA.velocity - cross(bodyA.angularVelocity, rA)
    }
}

/// Keeps a point on body A coincident with a point on body B (revolute constraint).
struct PointConstraint {

    let localAnchorA: Vector2
    let localAnchorB: Vector2

    var impulse: Vector2 = .zero

    init(anchor: Vector2, bodyA: PhysicsBody, bodyB: PhysicsBody) {
        localAnchorA = PhysicsJoint.localAnchor(anchor, on: bodyA)
        localAnchorB = PhysicsJoint.localAnchor(anchor, on: bodyB)
    }

    func anchors(_ joint: PhysicsJoint) -> (rA: Vector2, rB: Vector2) {
        (Rotation(joint.bodyA.rotation).apply(localAnchorA), Rotation(joint.bodyB.rotation).apply(localAnchorB))
    }

    func warmStart(_ joint: PhysicsJoint) {
        let (rA, rB) = anchors(joint)
        joint.apply(impulse, rA: rA, rB: rB)
    }

    mutating func solve(_ joint: PhysicsJoint, context: SolverContext, useBias: Bool) {
        let a = joint.bodyA, b = joint.bodyB
        let (rA, rB) = anchors(joint)
        let cdot = joint.relativeVelocity(rA: rA, rB: rB)

        var bias = Vector2.zero
        var massScale: Float = 1
        var impulseScale: Float = 0
        if useBias {
            let separation = (b.worldCenter + rB) - (a.worldCenter + rA)
            bias = context.jointSoftness.biasRate * separation
            massScale = context.jointSoftness.massScale
            impulseScale = context.jointSoftness.impulseScale
        }

        let mA = a.invMass, mB = b.invMass, iA = a.invInertia, iB = b.invInertia
        let k = Matrix2x2(
            c0: Vector2(mA + mB + iA * rA.y * rA.y + iB * rB.y * rB.y, -iA * rA.x * rA.y - iB * rB.x * rB.y),
            c1: Vector2(-iA * rA.x * rA.y - iB * rB.x * rB.y, mA + mB + iA * rA.x * rA.x + iB * rB.x * rB.x)
        )
        let solved = k.inverse * (cdot + bias)
        let delta = -massScale * solved - impulseScale * impulse
        impulse += delta
        joint.apply(delta, rA: rA, rB: rB)
    }
}
