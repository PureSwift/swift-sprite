//
//  Matrix3x3.swift
//  SpriteCore
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// 2D vector type used throughout the engine.
public typealias Vector2 = SIMD2<Float>

/// Column-major 3×3 matrix representing a 2D affine transform.
///
/// Layout matches `simd_float3x3`, so `columns.2.xy` holds the translation.
/// Points are treated as column vectors: `p' = M * p`.
public struct Matrix3x3: Equatable, Hashable, Sendable {

    public var columns: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

    public init(_ c0: SIMD3<Float>, _ c1: SIMD3<Float>, _ c2: SIMD3<Float>) {
        self.columns = (c0, c1, c2)
    }

    /// Creates a matrix from row-major values (as commonly written on paper).
    public init(rows r0: SIMD3<Float>, _ r1: SIMD3<Float>, _ r2: SIMD3<Float>) {
        self.init(
            SIMD3(r0.x, r1.x, r2.x),
            SIMD3(r0.y, r1.y, r2.y),
            SIMD3(r0.z, r1.z, r2.z)
        )
    }

    public static func == (lhs: Matrix3x3, rhs: Matrix3x3) -> Bool {
        lhs.columns.0 == rhs.columns.0
            && lhs.columns.1 == rhs.columns.1
            && lhs.columns.2 == rhs.columns.2
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(columns.0)
        hasher.combine(columns.1)
        hasher.combine(columns.2)
    }
}

// MARK: - Constructors

public extension Matrix3x3 {

    static let identity = Matrix3x3(
        SIMD3(1, 0, 0),
        SIMD3(0, 1, 0),
        SIMD3(0, 0, 1)
    )

    static func translation(_ t: Vector2) -> Matrix3x3 {
        Matrix3x3(SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(t.x, t.y, 1))
    }

    /// Counter-clockwise rotation in radians (Y-up coordinate space).
    static func rotation(_ radians: Float) -> Matrix3x3 {
        let c = cosf(radians)
        let s = sinf(radians)
        return Matrix3x3(SIMD3(c, s, 0), SIMD3(-s, c, 0), SIMD3(0, 0, 1))
    }

    static func scale(_ s: Vector2) -> Matrix3x3 {
        Matrix3x3(SIMD3(s.x, 0, 0), SIMD3(0, s.y, 0), SIMD3(0, 0, 1))
    }

    /// Maps a Y-up world space with the origin at the bottom-left
    /// to a Y-down pixel space of the given size.
    static func viewport(size: Vector2) -> Matrix3x3 {
        Matrix3x3(SIMD3(1, 0, 0), SIMD3(0, -1, 0), SIMD3(0, size.y, 1))
    }
}

// MARK: - Operations

public extension Matrix3x3 {

    /// Row-major copy of this matrix, for APIs expecting row-major storage.
    var rows: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (
            SIMD3(columns.0.x, columns.1.x, columns.2.x),
            SIMD3(columns.0.y, columns.1.y, columns.2.y),
            SIMD3(columns.0.z, columns.1.z, columns.2.z)
        )
    }

    var translation: Vector2 {
        get { Vector2(columns.2.x, columns.2.y) }
        set { columns.2.x = newValue.x; columns.2.y = newValue.y }
    }

    static func * (lhs: Matrix3x3, rhs: SIMD3<Float>) -> SIMD3<Float> {
        lhs.columns.0 * rhs.x + lhs.columns.1 * rhs.y + lhs.columns.2 * rhs.z
    }

    static func * (lhs: Matrix3x3, rhs: Matrix3x3) -> Matrix3x3 {
        Matrix3x3(lhs * rhs.columns.0, lhs * rhs.columns.1, lhs * rhs.columns.2)
    }

    static func *= (lhs: inout Matrix3x3, rhs: Matrix3x3) {
        lhs = lhs * rhs
    }

    /// Transforms a point (applies translation).
    func transform(point p: Vector2) -> Vector2 {
        Vector2(
            columns.0.x * p.x + columns.1.x * p.y + columns.2.x,
            columns.0.y * p.x + columns.1.y * p.y + columns.2.y
        )
    }

    /// Transforms a direction (ignores translation).
    func transform(vector v: Vector2) -> Vector2 {
        Vector2(
            columns.0.x * v.x + columns.1.x * v.y,
            columns.0.y * v.x + columns.1.y * v.y
        )
    }

    /// Inverse of the affine transform, or `nil` if it is singular.
    var inverse: Matrix3x3? {
        let a = columns.0.x, b = columns.0.y
        let c = columns.1.x, d = columns.1.y
        let tx = columns.2.x, ty = columns.2.y
        let det = a * d - b * c
        guard det != 0, det.isFinite else { return nil }
        let invDet = 1 / det
        let ia = d * invDet, ib = -b * invDet
        let ic = -c * invDet, id = a * invDet
        return Matrix3x3(
            SIMD3(ia, ib, 0),
            SIMD3(ic, id, 0),
            SIMD3(-(ia * tx + ic * ty), -(ib * tx + id * ty), 1)
        )
    }
}
