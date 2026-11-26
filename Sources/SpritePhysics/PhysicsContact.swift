//
//  PhysicsContact.swift
//  SpritePhysics
//

import SpriteCore

/// Contact between two bodies reported to ``PhysicsWorld`` contact handlers.
///
/// Contacts are reported when either body's ``PhysicsBody/contactTestBitMask``
/// intersects the other's ``PhysicsBody/categoryBitMask``.
public struct PhysicsContact {

    public let bodyA: PhysicsBody

    public let bodyB: PhysicsBody

    /// Representative contact point in world coordinates.
    public let contactPoint: Vector2

    /// Unit normal pointing from body A to body B.
    public let contactNormal: Vector2

    /// Total normal impulse applied during the step (zero for non-colliding contacts).
    public let collisionImpulse: Float

    /// Whether `body` participates in this contact.
    public func involves(_ body: PhysicsBody) -> Bool {
        bodyA === body || bodyB === body
    }

    /// The body in this contact that is not `body`.
    public func other(than body: PhysicsBody) -> PhysicsBody? {
        if bodyA === body { return bodyB }
        if bodyB === body { return bodyA }
        return nil
    }
}
