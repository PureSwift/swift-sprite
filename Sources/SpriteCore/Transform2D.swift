//
//  Transform2D.swift
//  SpriteCore
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// Decomposed 2D transform (translation, rotation, scale) for node hierarchies.
public struct Transform2D: Equatable, Hashable, Sendable {

    public var position: Vector2

    /// Rotation in radians, counter-clockwise.
    public var rotation: Float

    public var scale: Vector2

    public init(
        position: Vector2 = .zero,
        rotation: Float = 0,
        scale: Vector2 = .one
    ) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }

    public static let identity = Transform2D()

    /// Local-to-parent matrix computed as `T * R * S`.
    public var matrix: Matrix3x3 {
        let c = cosf(rotation)
        let s = sinf(rotation)
        return Matrix3x3(
            SIMD3(c * scale.x, s * scale.x, 0),
            SIMD3(-s * scale.y, c * scale.y, 0),
            SIMD3(position.x, position.y, 1)
        )
    }
}
