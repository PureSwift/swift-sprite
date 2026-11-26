//
//  DistanceJoint.swift
//  SpritePhysics
//
//  Adapted from Box2D v3's distance joint (MIT License, Copyright 2023 Erin Catto).
//

import SpriteCore

/// Keeps the distance between two anchors within `minLength...maxLength`.
///
/// Equal limits make a rigid rod; `minLength: 0` makes a rope (like `SKPhysicsJointLimit`).
public final class DistanceJoint: PhysicsJoint {

    public var minLength: Float

    public var maxLength: Float

    private let localAnchorA: Vector2
    private let localAnchorB: Vector2
    private var impulse: Float = 0
    private var lowerImpulse: Float = 0
    private var upperImpulse: Float = 0

    /// - Parameters:
    ///   - anchorA: Attachment point on body A in world coordinates.
    ///   - anchorB: Attachment point on body B in world coordinates.
    ///   - minLength: Defaults to the current distance.
    ///   - maxLength: Defaults to the current distance.
    public init(
        bodyA: PhysicsBody,
        bodyB: PhysicsBody,
        anchorA: Vector2,
        anchorB: Vector2,
        minLength: Float? = nil,
        maxLength: Float? = nil
    ) {
        let current = length(anchorB - anchorA)
        self.minLength = minLength ?? current
        self.maxLength = max(maxLength ?? current, minLength ?? current)
        localAnchorA = PhysicsJoint.localAnchor(anchorA, on: bodyA)
        localAnchorB = PhysicsJoint.localAnchor(anchorB, on: bodyB)
        super.init(bodyA: bodyA, bodyB: bodyB)
    }

    /// Rope joint allowing any distance up to `maxLength`.
    public static func rope(bodyA: PhysicsBody, bodyB: PhysicsBody, anchorA: Vector2, anchorB: Vector2, maxLength: Float? = nil) -> DistanceJoint {
        DistanceJoint(bodyA: bodyA, bodyB: bodyB, anchorA: anchorA, anchorB: anchorB, minLength: 0, maxLength: maxLength)
    }

    private var isRigid: Bool {
        maxLength - minLength < 1e-3
    }

    /// Current anchor offsets, axis and length.
    private func geometry() -> (rA: Vector2, rB: Vector2, axis: Vector2, length: Float) {
        let rA = Rotation(bodyA.rotation).apply(localAnchorA)
        let rB = Rotation(bodyB.rotation).apply(localAnchorB)
        let d = (bodyB.worldCenter + rB) - (bodyA.worldCenter + rA)
        let currentLength = length(d)
        return (rA, rB, currentLength > .ulpOfOne ? d / currentLength : Vector2(1, 0), currentLength)
    }

    override func prepare(context: SolverContext) {
        if isRigid {
            lowerImpulse = 0
            upperImpulse = 0
        } else {
            impulse = 0
        }
    }

    override func warmStart() {
        let (rA, rB, axis, _) = geometry()
        apply((impulse + lowerImpulse - upperImpulse) * axis, rA: rA, rB: rB)
    }

    override func solve(context: SolverContext, useBias: Bool) {
        let (rA, rB, axis, currentLength) = geometry()
        let crA = cross(rA, axis), crB = cross(rB, axis)
        let k = bodyA.invMass + bodyB.invMass + bodyA.invInertia * crA * crA + bodyB.invInertia * crB * crB
        let axialMass: Float = k > 0 ? 1 / k : 0
        let softness = context.jointSoftness

        if isRigid {
            let error = currentLength - minLength
            var bias: Float = 0, massScale: Float = 1, impulseScale: Float = 0
            if useBias {
                bias = softness.biasRate * error
                massScale = softness.massScale
                impulseScale = softness.impulseScale
            }
            let cdot = dot(relativeVelocity(rA: rA, rB: rB), axis)
            let delta = -massScale * axialMass * (cdot + bias) - impulseScale * impulse
            impulse += delta
            apply(delta * axis, rA: rA, rB: rB)
        } else {
            // Lower limit pushes apart; a positive gap is closed speculatively.
            do {
                let error = currentLength - minLength
                var bias: Float = 0, massScale: Float = 1, impulseScale: Float = 0
                if error > 0 {
                    bias = error * context.invH
                } else if useBias {
                    bias = softness.biasRate * error
                    massScale = softness.massScale
                    impulseScale = softness.impulseScale
                }
                let cdot = dot(relativeVelocity(rA: rA, rB: rB), axis)
                let delta = -massScale * axialMass * (cdot + bias) - impulseScale * lowerImpulse
                let newImpulse = max(lowerImpulse + delta, 0)
                apply((newImpulse - lowerImpulse) * axis, rA: rA, rB: rB)
                lowerImpulse = newImpulse
            }
            // Upper limit pulls together.
            do {
                let error = maxLength - currentLength
                var bias: Float = 0, massScale: Float = 1, impulseScale: Float = 0
                if error > 0 {
                    bias = error * context.invH
                } else if useBias {
                    bias = softness.biasRate * error
                    massScale = softness.massScale
                    impulseScale = softness.impulseScale
                }
                let cdot = -dot(relativeVelocity(rA: rA, rB: rB), axis)
                let delta = -massScale * axialMass * (cdot + bias) - impulseScale * upperImpulse
                let newImpulse = max(upperImpulse + delta, 0)
                apply(-(newImpulse - upperImpulse) * axis, rA: rA, rB: rB)
                upperImpulse = newImpulse
            }
        }
        reactionImpulse = (impulse + lowerImpulse - upperImpulse) * axis
    }
}
