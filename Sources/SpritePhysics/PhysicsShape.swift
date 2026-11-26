//
//  PhysicsShape.swift
//  SpritePhysics
//

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

// MARK: - Convex parts

/// Convex primitive used internally for collision, mass and queries.
enum ConvexPart: Equatable {

    case circle(center: Vector2, radius: Float)

    /// Counter-clockwise vertices with outward edge normals.
    /// Two vertices represent a segment with normals on both sides.
    case polygon(vertices: [Vector2], normals: [Vector2])

    static func polygon(_ points: [Vector2]) -> ConvexPart? {
        let hull = convexHull(points)
        switch hull.count {
        case 0, 1:
            return nil
        case 2:
            return segment(hull[0], hull[1])
        default:
            let normals = hull.indices.map { i in
                let edge = hull[(i + 1) % hull.count] - hull[i]
                return normalize(Vector2(edge.y, -edge.x))
            }
            return .polygon(vertices: hull, normals: normals)
        }
    }

    static func segment(_ a: Vector2, _ b: Vector2) -> ConvexPart? {
        let edge = b - a
        guard dot(edge, edge) > .ulpOfOne else { return nil }
        let normal = normalize(Vector2(edge.y, -edge.x))
        return .polygon(vertices: [a, b], normals: [normal, -normal])
    }

    func transformed(by transform: RigidTransform) -> ConvexPart {
        switch self {
        case let .circle(center, radius):
            .circle(center: transform.apply(center), radius: radius)
        case let .polygon(vertices, normals):
            .polygon(
                vertices: vertices.map(transform.apply),
                normals: normals.map(transform.rotation.apply)
            )
        }
    }

    var bounds: Rect {
        switch self {
        case let .circle(center, radius):
            return Rect(origin: center - radius, size: Vector2(repeating: radius * 2))
        case let .polygon(vertices, _):
            var lo = vertices[0], hi = vertices[0]
            for v in vertices.dropFirst() {
                lo = pointwiseMin(lo, v)
                hi = pointwiseMax(hi, v)
            }
            return Rect(origin: lo, size: hi - lo)
        }
    }

    func contains(_ point: Vector2) -> Bool {
        switch self {
        case let .circle(center, radius):
            let d = point - center
            return dot(d, d) <= radius * radius
        case let .polygon(vertices, normals):
            guard vertices.count >= 3 else { return false }
            return vertices.indices.allSatisfy { dot(normals[$0], point - vertices[$0]) <= 0 }
        }
    }

    /// Mass, center of mass and rotational inertia about the local origin.
    func massData(density: Float) -> (mass: Float, center: Vector2, inertia: Float) {
        switch self {
        case let .circle(center, radius):
            let mass = density * .pi * radius * radius
            return (mass, center, mass * (0.5 * radius * radius + dot(center, center)))
        case let .polygon(vertices, _):
            guard vertices.count >= 3 else { return (0, vertices.reduce(.zero, +) / Float(vertices.count), 0) }
            // Triangle fan about the first vertex.
            let reference = vertices[0]
            var area: Float = 0
            var center = Vector2.zero
            var inertia: Float = 0
            for i in 1 ..< vertices.count - 1 {
                let e1 = vertices[i] - reference
                let e2 = vertices[i + 1] - reference
                let d = cross(e1, e2)
                let triangleArea = 0.5 * d
                area += triangleArea
                center += triangleArea * (e1 + e2) / 3
                let intx2 = e1.x * e1.x + e2.x * e1.x + e2.x * e2.x
                let inty2 = e1.y * e1.y + e2.y * e1.y + e2.y * e2.y
                inertia += (0.25 / 3 * d) * (intx2 + inty2)
            }
            let mass = density * area
            let relativeCenter = center / area
            let worldCenter = relativeCenter + reference
            // Shift inertia from the reference vertex to the origin via the center of mass.
            let originInertia = density * inertia + mass * (dot(worldCenter, worldCenter) - dot(relativeCenter, relativeCenter))
            return (mass, worldCenter, originInertia)
        }
    }

    var area: Float {
        massData(density: 1).mass
    }
}

extension PhysicsShape {

    /// Decomposes the shape into convex parts.
    var parts: [ConvexPart] {
        switch self {
        case let .circle(radius, center):
            return radius > 0 ? [.circle(center: center, radius: radius)] : []
        case let .rectangle(size, center):
            let half = size * 0.5
            return [ConvexPart.polygon([
                center + Vector2(-half.x, -half.y),
                center + Vector2(half.x, -half.y),
                center + Vector2(half.x, half.y),
                center + Vector2(-half.x, half.y),
            ])].compactMap { $0 }
        case let .polygon(points):
            return [ConvexPart.polygon(points)].compactMap { $0 }
        case let .edge(from, to):
            return [ConvexPart.segment(from, to)].compactMap { $0 }
        case let .edgeChain(points):
            return zip(points, points.dropFirst()).compactMap { ConvexPart.segment($0, $1) }
        case let .edgeLoop(points):
            guard let first = points.first else { return [] }
            let closed = points + [first]
            return zip(closed, closed.dropFirst()).compactMap { ConvexPart.segment($0, $1) }
        case let .compound(shapes):
            return shapes.flatMap(\.parts)
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
    var lower = [Vector2]()
    for p in unique {
        while lower.count >= 2, cross(lower[lower.count - 1] - lower[lower.count - 2], p - lower[lower.count - 2]) <= 0 {
            lower.removeLast()
        }
        lower.append(p)
    }
    var upper = [Vector2]()
    for p in unique.reversed() {
        while upper.count >= 2, cross(upper[upper.count - 1] - upper[upper.count - 2], p - upper[upper.count - 2]) <= 0 {
            upper.removeLast()
        }
        upper.append(p)
    }
    return Array(lower.dropLast() + upper.dropLast())
}
