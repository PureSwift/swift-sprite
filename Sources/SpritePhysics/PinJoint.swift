//
//  PinJoint.swift
//  SpritePhysics
//

import SpriteCore

/// Pins two bodies together at an anchor point, allowing free rotation about it.
public final class PinJoint: PhysicsJoint {

    private var point: PointConstraint

    /// Resists relative rotation with up to this much torque.
    public var frictionTorque: Float = 0

    private var angularImpulse: Float = 0

    /// - Parameter anchor: Shared pivot in world coordinates.
    public init(bodyA: PhysicsBody, bodyB: PhysicsBody, anchor: Vector2) {
        point = PointConstraint(anchor: anchor, bodyA: bodyA, bodyB: bodyB)
        super.init(bodyA: bodyA, bodyB: bodyB)
    }

    override func prepare(context: SolverContext) {
        if frictionTorque <= 0 { angularImpulse = 0 }
    }

    override func warmStart() {
        applyAngular(angularImpulse)
        point.warmStart(self)
    }

    override func solve(context: SolverContext, useBias: Bool) {
        if frictionTorque > 0 {
            let k = bodyA.invInertia + bodyB.invInertia
            let axialMass: Float = k > 0 ? 1 / k : 0
            let maxImpulse = frictionTorque * context.h
            let old = angularImpulse
            let dw = bodyB.angularVelocity - bodyA.angularVelocity
            angularImpulse = min(max(old - axialMass * dw, -maxImpulse), maxImpulse)
            applyAngular(angularImpulse - old)
        }
        point.solve(self, context: context, useBias: useBias)
        reactionImpulse = point.impulse
    }
}
