//
//  PhysicsJoint.swift
//  SpritePhysics
//

import CBox2D
import SpriteCore

/// Constraint connecting two bodies, added to a ``PhysicsWorld``.
///
/// Anchors are given in world coordinates at creation and stored relative to each
/// body. The Box2D joint is created once both bodies are in the same world.
public class PhysicsJoint {

    public let bodyA: PhysicsBody

    public let bodyB: PhysicsBody

    /// Whether the connected bodies can collide with each other.
    public let collideConnected: Bool

    private(set) var jointID: b2JointId?

    init(bodyA: PhysicsBody, bodyB: PhysicsBody, collideConnected: Bool) {
        precondition(bodyA !== bodyB, "A joint must connect two different bodies")
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.collideConnected = collideConnected
    }

    /// Force applied by the joint in the last step.
    public var reactionForce: Vector2 {
        jointID.map { Vector2(b2Joint_GetConstraintForce($0)) } ?? .zero
    }

    /// Creates the Box2D joint; implemented by subclasses.
    func makeJoint(in world: b2WorldId) -> b2JointId {
        fatalError("Subclasses must implement makeJoint(in:)")
    }

    func create(in world: b2WorldId) {
        guard jointID == nil else { return }
        jointID = makeJoint(in: world)
    }

    func destroy() {
        if let jointID, b2Joint_IsValid(jointID) {
            b2DestroyJoint(jointID)
        }
        jointID = nil
    }

    /// Forgets the Box2D joint after one of its bodies was destroyed.
    func invalidate() {
        jointID = nil
    }

    /// Fills the shared joint definition with bodies and local frames.
    ///
    /// - Parameter alignRotation: Rotates frame B so the bodies keep their current relative angle.
    func configure(_ base: inout b2JointDef, localAnchorA: Vector2, localAnchorB: Vector2, alignRotation: Bool = false) {
        guard let a = bodyA.bodyID, let b = bodyB.bodyID else { return }
        base.bodyIdA = a
        base.bodyIdB = b
        base.collideConnected = collideConnected
        base.localFrameA = b2Transform(p: b2Vec2(localAnchorA), q: b2Rot(c: 1, s: 0))
        let relative = alignRotation ? bodyA.rotation - bodyB.rotation : 0
        base.localFrameB = b2Transform(p: b2Vec2(localAnchorB), q: b2Rot(angle: relative))
    }

    /// Converts a world point to a point relative to the body's origin in body space.
    static func localPoint(_ point: Vector2, on body: PhysicsBody) -> Vector2 {
        let rotation = b2Rot(angle: body.rotation)
        let d = point - body.position
        return Vector2(rotation.c * d.x + rotation.s * d.y, -rotation.s * d.x + rotation.c * d.y)
    }
}
