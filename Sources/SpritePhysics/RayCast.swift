//
//  RayCast.swift
//  SpritePhysics
//

import SpriteCore

/// Intersection of a ray segment with a body.
public struct RayHit {

    public let body: PhysicsBody

    /// Hit position in world coordinates.
    public let point: Vector2

    /// Surface normal at the hit, facing the ray origin.
    public let normal: Vector2

    /// Distance along the ray as a fraction of `start → end`, in `0...1`.
    public let fraction: Float
}
