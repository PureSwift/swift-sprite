//
//  FixedJoint.swift
//  SpritePhysics
//

import SpriteCore

/// Welds two bodies together, preventing relative translation and rotation.
public final class FixedJoint: PhysicsJoint {

    private var point: PointConstraint

    private let referenceAngle: Float
    private var angularImpulse: Float = 0

    /// - Parameter anchor: Weld point in world coordinates.
    public init(bodyA: PhysicsBody, bodyB: PhysicsBody, anchor: Vector2) {
        point = PointConstraint(anchor: anchor, bodyA: bodyA, bodyB: bodyB)
        referenceAngle = bodyB.rotation - bodyA.rotation
        super.init(bodyA: bodyA, bodyB: bodyB)
    }

    override func warmStart() {
        applyAngular(angularImpulse)
        point.warmStart(self)
    }

    override func solve(context: SolverContext, useBias: Bool) {
        let k = bodyA.invInertia + bodyB.invInertia
        let axialMass: Float = k > 0 ? 1 / k : 0
        var bias: Float = 0
        var massScale: Float = 1
        var impulseScale: Float = 0
        if useBias {
            let error = bodyB.rotation - bodyA.rotation - referenceAngle
            bias = context.jointSoftness.biasRate * error
            massScale = context.jointSoftness.massScale
            impulseScale = context.jointSoftness.impulseScale
        }
        let cdot = bodyB.angularVelocity - bodyA.angularVelocity
        let delta = -axialMass * massScale * (cdot + bias) - impulseScale * angularImpulse
        angularImpulse += delta
        applyAngular(delta)

        point.solve(self, context: context, useBias: useBias)
        reactionImpulse = point.impulse
    }
}
