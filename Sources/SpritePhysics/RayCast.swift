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

extension ConvexPart {

    /// Intersects the segment `p1 → p2` (world space) with this world-space part.
    func rayCast(from p1: Vector2, to p2: Vector2) -> (fraction: Float, normal: Vector2)? {
        let d = p2 - p1
        switch self {
        case let .circle(center, radius):
            let s = p1 - center
            let a = dot(d, d)
            let b = dot(s, d)
            let c = dot(s, s) - radius * radius
            let discriminant = b * b - a * c
            // Rays starting inside a circle report no hit.
            guard a > .ulpOfOne, discriminant >= 0, c > 0 else { return nil }
            let t = (-b - discriminant.squareRoot()) / a
            guard t >= 0, t <= 1 else { return nil }
            return (t, normalize(s + t * d))

        case let .polygon(vertices, normals) where vertices.count == 2:
            let v0 = vertices[0], v1 = vertices[1]
            let normal = normals[0]
            let numerator = dot(normal, v0 - p1)
            let denominator = dot(normal, d)
            guard denominator != 0 else { return nil }
            let t = numerator / denominator
            guard t >= 0, t <= 1 else { return nil }
            let q = p1 + t * d
            let e = v1 - v0
            let s = dot(q - v0, e) / dot(e, e)
            guard s >= 0, s <= 1 else { return nil }
            return (t, numerator > 0 ? -normal : normal)

        case let .polygon(vertices, normals):
            // Cyrus–Beck clipping against each edge's half-space.
            var lower: Float = 0
            var upper: Float = 1
            var index = -1
            for i in vertices.indices {
                let numerator = dot(normals[i], vertices[i] - p1)
                let denominator = dot(normals[i], d)
                if denominator == 0 {
                    if numerator < 0 { return nil }
                } else if denominator < 0, numerator < lower * denominator {
                    lower = numerator / denominator
                    index = i
                } else if denominator > 0, numerator < upper * denominator {
                    upper = numerator / denominator
                }
                if upper < lower { return nil }
            }
            guard index >= 0 else { return nil }
            return (lower, normals[index])
        }
    }
}
