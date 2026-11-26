//
//  SpringJoint.swift
//  SpritePhysics
//
//  Adapted from Box2D v3's distance joint spring (MIT License, Copyright 2023 Erin Catto).
//

import SpriteCore

/// Damped spring between two anchors, solved implicitly for stability.
public final class SpringJoint: PhysicsJoint {

    /// Oscillation frequency in hertz.
    public var frequency: Float

    /// Damping ratio; `0` oscillates freely, `1` is critically damped.
    public var damping: Float

    public var restLength: Float

    private let localAnchorA: Vector2
    private let localAnchorB: Vector2
    private var impulse: Float = 0

    /// - Parameters:
    ///   - anchorA: Attachment point on body A in world coordinates.
    ///   - anchorB: Attachment point on body B in world coordinates.
    ///   - restLength: Defaults to the current distance between anchors.
    public init(
        bodyA: PhysicsBody,
        bodyB: PhysicsBody,
        anchorA: Vector2,
        anchorB: Vector2,
        frequency: Float = 2,
        damping: Float = 0.3,
        restLength: Float? = nil
    ) {
        self.frequency = frequency
        self.damping = damping
        self.restLength = restLength ?? length(anchorB - anchorA)
        localAnchorA = PhysicsJoint.localAnchor(anchorA, on: bodyA)
        localAnchorB = PhysicsJoint.localAnchor(anchorB, on: bodyB)
        super.init(bodyA: bodyA, bodyB: bodyB)
    }

    private func geometry() -> (rA: Vector2, rB: Vector2, axis: Vector2, length: Float) {
        let rA = Rotation(bodyA.rotation).apply(localAnchorA)
        let rB = Rotation(bodyB.rotation).apply(localAnchorB)
        let d = (bodyB.worldCenter + rB) - (bodyA.worldCenter + rA)
        let currentLength = length(d)
        return (rA, rB, currentLength > .ulpOfOne ? d / currentLength : Vector2(1, 0), currentLength)
    }

    override func warmStart() {
        let (rA, rB, axis, _) = geometry()
        apply(impulse * axis, rA: rA, rB: rB)
    }

    /// Spring forces are physical, so they apply in both the biased and relax passes.
    override func solve(context: SolverContext, useBias: Bool) {
        let (rA, rB, axis, currentLength) = geometry()
        let crA = cross(rA, axis), crB = cross(rB, axis)
        let k = bodyA.invMass + bodyB.invMass + bodyA.invInertia * crA * crA + bodyB.invInertia * crB * crB
        let axialMass: Float = k > 0 ? 1 / k : 0
        let spring = Softness(hertz: frequency, dampingRatio: damping, h: context.h)
        let bias = spring.biasRate * (currentLength - restLength)
        let cdot = dot(relativeVelocity(rA: rA, rB: rB), axis)
        let delta = -spring.massScale * axialMass * (cdot + bias) - spring.impulseScale * impulse
        impulse += delta
        apply(delta * axis, rA: rA, rB: rB)
        reactionImpulse = impulse * axis
    }
}
