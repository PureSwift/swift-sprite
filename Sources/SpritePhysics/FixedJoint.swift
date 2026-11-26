//
//  FixedJoint.swift
//  SpritePhysics
//

import CBox2D
import SpriteCore

/// Welds two bodies together, preventing relative translation and rotation (Box2D weld joint).
public final class FixedJoint: PhysicsJoint {

    private let localAnchorA: Vector2
    private let localAnchorB: Vector2

    /// - Parameter anchor: Weld point in world coordinates.
    public init(bodyA: PhysicsBody, bodyB: PhysicsBody, anchor: Vector2) {
        localAnchorA = PhysicsJoint.localPoint(anchor, on: bodyA)
        localAnchorB = PhysicsJoint.localPoint(anchor, on: bodyB)
        super.init(bodyA: bodyA, bodyB: bodyB, collideConnected: false)
    }

    override func makeJoint(in world: b2WorldId) -> b2JointId {
        var definition = b2DefaultWeldJointDef()
        configure(&definition.base, localAnchorA: localAnchorA, localAnchorB: localAnchorB, alignRotation: true)
        // Zero stiffness makes the weld rigid.
        definition.linearHertz = 0
        definition.angularHertz = 0
        return b2CreateWeldJoint(world, &definition)
    }
}
