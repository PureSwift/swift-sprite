//
//  Rect.swift
//  SpriteCore
//

/// Axis-aligned rectangle defined by an origin (minimum corner) and size.
public struct Rect: Equatable, Hashable, Sendable {

    public var origin: Vector2

    public var size: Vector2

    public init(origin: Vector2 = .zero, size: Vector2 = .zero) {
        self.origin = origin
        self.size = size
    }

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.init(origin: Vector2(x, y), size: Vector2(width, height))
    }

    public static let zero = Rect()

    /// The unit rectangle `(0, 0, 1, 1)`, used for full-texture UVs.
    public static let unit = Rect(x: 0, y: 0, width: 1, height: 1)
}

public extension Rect {

    var minX: Float { origin.x }
    var minY: Float { origin.y }
    var maxX: Float { origin.x + size.x }
    var maxY: Float { origin.y + size.y }
    var midX: Float { origin.x + size.x * 0.5 }
    var midY: Float { origin.y + size.y * 0.5 }
    var width: Float { size.x }
    var height: Float { size.y }

    var min: Vector2 { origin }
    var max: Vector2 { origin + size }
    var center: Vector2 { origin + size * 0.5 }

    var isEmpty: Bool { size.x <= 0 || size.y <= 0 }

    func contains(_ point: Vector2) -> Bool {
        point.x >= minX && point.x < maxX && point.y >= minY && point.y < maxY
    }

    func intersects(_ other: Rect) -> Bool {
        minX < other.maxX && other.minX < maxX && minY < other.maxY && other.minY < maxY
    }

    func union(_ other: Rect) -> Rect {
        let lo = pointwiseMin(min, other.min)
        let hi = pointwiseMax(max, other.max)
        return Rect(origin: lo, size: hi - lo)
    }

    func insetBy(dx: Float, dy: Float) -> Rect {
        Rect(x: minX + dx, y: minY + dy, width: width - dx * 2, height: height - dy * 2)
    }

    /// Axis-aligned bounds of this rectangle after applying a transform.
    func applying(_ transform: Matrix3x3) -> Rect {
        let corners = [
            transform.transform(point: Vector2(minX, minY)),
            transform.transform(point: Vector2(maxX, minY)),
            transform.transform(point: Vector2(maxX, maxY)),
            transform.transform(point: Vector2(minX, maxY)),
        ]
        var lo = corners[0], hi = corners[0]
        for corner in corners.dropFirst() {
            lo = pointwiseMin(lo, corner)
            hi = pointwiseMax(hi, corner)
        }
        return Rect(origin: lo, size: hi - lo)
    }
}
