//
//  VectorMath.swift
//  SpritePhysics
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import SpriteCore

/// 2D scalar cross product `a × b`.
@inline(__always)
func cross(_ a: Vector2, _ b: Vector2) -> Float {
    a.x * b.y - a.y * b.x
}

/// Cross product of a scalar (z-axis) with a vector: `w × v`.
@inline(__always)
func cross(_ w: Float, _ v: Vector2) -> Vector2 {
    Vector2(-w * v.y, w * v.x)
}

@inline(__always)
func dot(_ a: Vector2, _ b: Vector2) -> Float {
    (a * b).sum()
}

@inline(__always)
func length(_ v: Vector2) -> Float {
    dot(v, v).squareRoot()
}

@inline(__always)
func normalize(_ v: Vector2) -> Vector2 {
    let len = length(v)
    return len > .ulpOfOne ? v / len : .zero
}

/// Rotation stored as cosine and sine.
struct Rotation {

    var c: Float
    var s: Float

    init(_ angle: Float) {
        c = cosf(angle)
        s = sinf(angle)
    }

    @inline(__always)
    func apply(_ v: Vector2) -> Vector2 {
        Vector2(c * v.x - s * v.y, s * v.x + c * v.y)
    }

    @inline(__always)
    func applyInverse(_ v: Vector2) -> Vector2 {
        Vector2(c * v.x + s * v.y, -s * v.x + c * v.y)
    }
}

/// Rigid transform (rotation then translation).
struct RigidTransform {

    var position: Vector2
    var rotation: Rotation

    init(position: Vector2, angle: Float) {
        self.position = position
        self.rotation = Rotation(angle)
    }

    @inline(__always)
    func apply(_ v: Vector2) -> Vector2 {
        position + rotation.apply(v)
    }
}

/// Symmetric 2×2 matrix used by point constraints.
struct Matrix2x2 {

    var c0: Vector2
    var c1: Vector2

    var inverse: Matrix2x2 {
        let det = c0.x * c1.y - c1.x * c0.y
        let invDet: Float = det != 0 ? 1 / det : 0
        return Matrix2x2(
            c0: Vector2(c1.y, -c0.y) * invDet,
            c1: Vector2(-c1.x, c0.x) * invDet
        )
    }

    static func * (m: Matrix2x2, v: Vector2) -> Vector2 {
        m.c0 * v.x + m.c1 * v.y
    }
}
