//
//  DistanceJoint.swift
//  SpritePhysics
//

import CBox2D
import SpriteCore

/// Keeps the distance between two anchors within `minLength...maxLength` (Box2D distance joint).
///
/// Equal limits make a rigid rod; `minLength: 0` makes a rope (like `SKPhysicsJointLimit`).
public final class DistanceJoint: PhysicsJoint {

    public var minLength: Float {
        didSet { updateLimits() }
    }

    public var maxLength: Float {
        didSet { updateLimits() }
    }

    private let localAnchorA: Vector2
    private let localAnchorB: Vector2

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
        maxLength: Float? = nil,
        collideConnected: Bool = false
    ) {
        let current = length(anchorB - anchorA)
        self.minLength = minLength ?? current
        self.maxLength = max(maxLength ?? current, minLength ?? current)
        localAnchorA = PhysicsJoint.localPoint(anchorA, on: bodyA)
        localAnchorB = PhysicsJoint.localPoint(anchorB, on: bodyB)
        super.init(bodyA: bodyA, bodyB: bodyB, collideConnected: collideConnected)
    }

    /// Rope joint allowing any distance up to `maxLength`.
    public static func rope(bodyA: PhysicsBody, bodyB: PhysicsBody, anchorA: Vector2, anchorB: Vector2, maxLength: Float? = nil) -> DistanceJoint {
        DistanceJoint(bodyA: bodyA, bodyB: bodyB, anchorA: anchorA, anchorB: anchorB, minLength: 0, maxLength: maxLength)
    }

    private var isRigid: Bool {
        maxLength - minLength < 1e-3
    }

    override func makeJoint(in world: b2WorldId) -> b2JointId {
        var definition = b2DefaultDistanceJointDef()
        configure(&definition.base, localAnchorA: localAnchorA, localAnchorB: localAnchorB)
        definition.length = maxLength
        // A spring with zero stiffness leaves the bodies free between the limits.
        definition.enableSpring = !isRigid
        definition.hertz = 0
        definition.enableLimit = !isRigid
        definition.minLength = minLength
        definition.maxLength = maxLength
        return b2CreateDistanceJoint(world, &definition)
    }

    private func updateLimits() {
        guard let jointID else { return }
        b2DistanceJoint_SetRestLength(jointID, maxLength)
        b2DistanceJoint_EnableSpring(jointID, !isRigid)
        b2DistanceJoint_EnableLimit(jointID, !isRigid)
        b2DistanceJoint_SetLimits(jointID, minLength, maxLength)
    }
}
