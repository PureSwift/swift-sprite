//
//  SpringJoint.swift
//  SpritePhysics
//

import CBox2D
import SpriteCore

/// Damped spring between two anchors (Box2D distance joint with a spring).
public final class SpringJoint: PhysicsJoint {

    /// Oscillation frequency in hertz.
    public var frequency: Float {
        didSet { jointID.map { b2DistanceJoint_SetSpringHertz($0, frequency) } }
    }

    /// Damping ratio; `0` oscillates freely, `1` is critically damped.
    public var damping: Float {
        didSet { jointID.map { b2DistanceJoint_SetSpringDampingRatio($0, damping) } }
    }

    public var restLength: Float {
        didSet { jointID.map { b2DistanceJoint_SetRestLength($0, restLength) } }
    }

    private let localAnchorA: Vector2
    private let localAnchorB: Vector2

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
        restLength: Float? = nil,
        collideConnected: Bool = false
    ) {
        self.frequency = frequency
        self.damping = damping
        self.restLength = restLength ?? length(anchorB - anchorA)
        localAnchorA = PhysicsJoint.localPoint(anchorA, on: bodyA)
        localAnchorB = PhysicsJoint.localPoint(anchorB, on: bodyB)
        super.init(bodyA: bodyA, bodyB: bodyB, collideConnected: collideConnected)
    }

    override func makeJoint(in world: b2WorldId) -> b2JointId {
        var definition = b2DefaultDistanceJointDef()
        configure(&definition.base, localAnchorA: localAnchorA, localAnchorB: localAnchorB)
        definition.length = restLength
        definition.enableSpring = true
        definition.hertz = frequency
        definition.dampingRatio = damping
        definition.enableLimit = false
        return b2CreateDistanceJoint(world, &definition)
    }
}
