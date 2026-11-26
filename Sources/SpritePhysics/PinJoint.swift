//
//  PinJoint.swift
//  SpritePhysics
//

import CBox2D
import SpriteCore

/// Pins two bodies together at an anchor point, allowing free rotation about it (Box2D revolute joint).
public final class PinJoint: PhysicsJoint {

    private let localAnchorA: Vector2
    private let localAnchorB: Vector2

    /// Resists relative rotation with up to this much torque.
    public var frictionTorque: Float = 0 {
        didSet {
            guard let jointID else { return }
            b2RevoluteJoint_EnableMotor(jointID, frictionTorque > 0)
            b2RevoluteJoint_SetMaxMotorTorque(jointID, frictionTorque)
        }
    }

    /// - Parameter anchor: Shared pivot in world coordinates.
    public init(bodyA: PhysicsBody, bodyB: PhysicsBody, anchor: Vector2, collideConnected: Bool = false) {
        localAnchorA = PhysicsJoint.localPoint(anchor, on: bodyA)
        localAnchorB = PhysicsJoint.localPoint(anchor, on: bodyB)
        super.init(bodyA: bodyA, bodyB: bodyB, collideConnected: collideConnected)
    }

    override func makeJoint(in world: b2WorldId) -> b2JointId {
        var definition = b2DefaultRevoluteJointDef()
        configure(&definition.base, localAnchorA: localAnchorA, localAnchorB: localAnchorB, alignRotation: true)
        // Friction is a motor driving relative rotation toward zero with limited torque.
        definition.enableMotor = frictionTorque > 0
        definition.maxMotorTorque = frictionTorque
        definition.motorSpeed = 0
        return b2CreateRevoluteJoint(world, &definition)
    }
}
