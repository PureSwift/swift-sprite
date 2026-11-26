//
//  PhysicsShape.swift
//  SpritePhysics
//

import CBox2D
import SpriteCore

/// Collision geometry of a ``PhysicsBody`` in the body's local coordinates.
public indirect enum PhysicsShape: Equatable, Sendable {

    case circle(radius: Float, center: Vector2 = .zero)

    case rectangle(size: Vector2, center: Vector2 = .zero)

    /// Convex polygon; the convex hull is used if the points are not convex.
    case polygon([Vector2])

    /// Line segment with no area; bodies made only of edges are static.
    case edge(from: Vector2, to: Vector2)

    /// Open chain of segments.
    case edgeChain([Vector2])

    /// Closed loop of segments, e.g. the boundary of a level.
    case edgeLoop([Vector2])

    /// Union of several shapes.
    case compound([PhysicsShape])

    /// Closed edge loop around a rectangle.
    public static func edgeLoop(rect: Rect) -> PhysicsShape {
        .edgeLoop([
            Vector2(rect.minX, rect.minY),
            Vector2(rect.maxX, rect.minY),
            Vector2(rect.maxX, rect.maxY),
            Vector2(rect.minX, rect.maxY),
        ])
    }
}

// MARK: - Primitives

/// Box2D primitive making up a shape.
enum ShapePrimitive {

    case circle(b2Circle)

    case polygon(b2Polygon)

    case segment(b2Segment)

    /// Area used for density and mass computations.
    var area: Float {
        switch self {
        case let .circle(circle):
            return .pi * circle.radius * circle.radius
        case var .polygon(polygon):
            return b2ComputePolygonMass(&polygon, 1).mass
        case .segment:
            return 0
        }
    }

    func massData(density: Float) -> b2MassData {
        switch self {
        case var .circle(circle):
            return b2ComputeCircleMass(&circle, density)
        case var .polygon(polygon):
            return b2ComputePolygonMass(&polygon, density)
        case .segment:
            return b2MassData(mass: 0, center: b2Vec2(x: 0, y: 0), rotationalInertia: 0)
        }
    }

    /// Local-space vertices of polygons and segments (circles are handled by radius).
    var boundsPoints: [Vector2] {
        switch self {
        case let .circle(circle):
            return [Vector2(circle.center)]
        case let .polygon(polygon):
            return withUnsafeBytes(of: polygon.vertices) { buffer in
                Array(buffer.bindMemory(to: b2Vec2.self).prefix(Int(polygon.count))).map(Vector2.init)
            }
        case let .segment(segment):
            return [Vector2(segment.point1), Vector2(segment.point2)]
        }
    }

    /// Creates the primitive on a Box2D body.
    @discardableResult
    func create(on body: b2BodyId, definition: inout b2ShapeDef) -> b2ShapeId {
        switch self {
        case var .circle(circle):
            return b2CreateCircleShape(body, &definition, &circle)
        case var .polygon(polygon):
            return b2CreatePolygonShape(body, &definition, &polygon)
        case var .segment(segment):
            return b2CreateSegmentShape(body, &definition, &segment)
        }
    }
}

extension PhysicsShape {

    /// Decomposes the shape into Box2D primitives.
    var primitives: [ShapePrimitive] {
        switch self {
        case let .circle(radius, center):
            guard radius > 0 else { return [] }
            return [.circle(b2Circle(center: b2Vec2(center), radius: radius))]
        case let .rectangle(size, center):
            guard size.x > 0, size.y > 0 else { return [] }
            return [.polygon(b2MakeOffsetBox(size.x / 2, size.y / 2, b2Vec2(center), b2Rot(c: 1, s: 0)))]
        case let .polygon(points):
            return Self.convexPolygons(points).map(ShapePrimitive.polygon)
        case let .edge(from, to):
            return Self.segments([from, to])
        case let .edgeChain(points):
            return Self.segments(points)
        case let .edgeLoop(points):
            // Two-sided segments rather than a one-sided Box2D chain, so loops
            // contain bodies on either side.
            guard let first = points.first else { return [] }
            return Self.segments(points + [first])
        case let .compound(shapes):
            return shapes.flatMap(\.primitives)
        }
    }

    private static func segments(_ points: [Vector2]) -> [ShapePrimitive] {
        zip(points, points.dropFirst()).compactMap { a, b in
            length(b - a) > .ulpOfOne ? .segment(b2Segment(point1: b2Vec2(a), point2: b2Vec2(b))) : nil
        }
    }

    /// Convex hull as Box2D polygons, fanned into several when it exceeds Box2D's vertex limit.
    private static func convexPolygons(_ points: [Vector2]) -> [b2Polygon] {
        let hull = convexHull(points)
        guard hull.count >= 3 else { return [] }
        let maxVertices = Int(B2_MAX_POLYGON_VERTICES)
        var pieces = [[Vector2]]()
        if hull.count <= maxVertices {
            pieces = [hull]
        } else {
            // Fan from the first vertex into convex pieces sharing it.
            var start = 1
            while start < hull.count - 1 {
                let end = min(start + maxVertices - 2, hull.count - 1)
                pieces.append([hull[0]] + hull[start ... end])
                start = end
            }
        }
        return pieces.compactMap { piece in
            var points = piece.map(b2Vec2.init)
            var b2hull = b2ComputeHull(&points, Int32(points.count))
            guard b2hull.count >= 3 else { return nil }
            return b2MakePolygon(&b2hull, 0)
        }
    }
}

/// Counter-clockwise convex hull (Andrew's monotone chain), without collinear points.
func convexHull(_ points: [Vector2]) -> [Vector2] {
    let sorted = points.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
    var unique = [Vector2]()
    for point in sorted where unique.last.map({ length(point - $0) > 1e-6 }) ?? true {
        unique.append(point)
    }
    guard unique.count > 2 else { return unique }
    func half(_ input: [Vector2]) -> [Vector2] {
        var chain = [Vector2]()
        for p in input {
            while chain.count >= 2, cross(chain[chain.count - 1] - chain[chain.count - 2], p - chain[chain.count - 2]) <= 0 {
                chain.removeLast()
            }
            chain.append(p)
        }
        return chain
    }
    return Array(half(unique).dropLast() + half(unique.reversed()).dropLast())
}
