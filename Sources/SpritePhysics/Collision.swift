//
//  Collision.swift
//  SpritePhysics
//

import SpriteCore

/// Contact point between two convex parts.
struct ManifoldPoint {

    /// World position midway between the two surfaces.
    var position: Vector2

    /// Signed distance between surfaces; negative when penetrating.
    var separation: Float

    /// Feature identifier used to match points across steps for warm starting.
    var id: UInt32
}

/// Contact geometry between two convex parts.
struct Manifold {

    /// Unit normal pointing from part A to part B.
    var normal: Vector2

    var points: [ManifoldPoint]
}

/// Computes contacts between two world-space parts closer than `margin`.
func collide(_ a: ConvexPart, _ b: ConvexPart, margin: Float) -> Manifold? {
    switch (a, b) {
    case let (.circle(centerA, radiusA), .circle(centerB, radiusB)):
        return collideCircles(centerA, radiusA, centerB, radiusB, margin: margin)
    case let (.polygon(vertices, normals), .circle(center, radius)):
        return collidePolygonCircle(vertices, normals, center, radius, margin: margin)
    case let (.circle(center, radius), .polygon(vertices, normals)):
        guard var manifold = collidePolygonCircle(vertices, normals, center, radius, margin: margin) else { return nil }
        manifold.normal = -manifold.normal
        return manifold
    case let (.polygon(verticesA, normalsA), .polygon(verticesB, normalsB)):
        // Segments have no interior; segment-segment contacts are not meaningful.
        guard verticesA.count > 2 || verticesB.count > 2 else { return nil }
        return collidePolygons(verticesA, normalsA, verticesB, normalsB, margin: margin)
    }
}

func collideCircles(_ centerA: Vector2, _ radiusA: Float, _ centerB: Vector2, _ radiusB: Float, margin: Float) -> Manifold? {
    let d = centerB - centerA
    let distance = length(d)
    let separation = distance - radiusA - radiusB
    guard separation <= margin else { return nil }
    let normal = distance > .ulpOfOne ? d / distance : Vector2(0, 1)
    let surfaceA = centerA + normal * radiusA
    let surfaceB = centerB - normal * radiusB
    return Manifold(normal: normal, points: [
        ManifoldPoint(position: (surfaceA + surfaceB) * 0.5, separation: separation, id: 0),
    ])
}

/// Contact from polygon (A) to circle (B).
func collidePolygonCircle(
    _ vertices: [Vector2],
    _ normals: [Vector2],
    _ center: Vector2,
    _ radius: Float,
    margin: Float
) -> Manifold? {
    var normalIndex = 0
    var maxSeparation = -Float.greatestFiniteMagnitude
    for i in vertices.indices {
        let s = dot(normals[i], center - vertices[i])
        if s > radius + margin { return nil }
        if s > maxSeparation {
            maxSeparation = s
            normalIndex = i
        }
    }
    let v1 = vertices[normalIndex]
    let v2 = vertices[(normalIndex + 1) % vertices.count]
    let normal: Vector2
    let closest: Vector2
    if maxSeparation < .ulpOfOne {
        // Center is inside the polygon.
        normal = normals[normalIndex]
        closest = center - normal * maxSeparation
    } else if dot(center - v1, v2 - v1) <= 0 {
        guard length(center - v1) <= radius + margin else { return nil }
        normal = normalize(center - v1)
        closest = v1
    } else if dot(center - v2, v1 - v2) <= 0 {
        guard length(center - v2) <= radius + margin else { return nil }
        normal = normalize(center - v2)
        closest = v2
    } else {
        normal = normals[normalIndex]
        closest = center - normal * dot(center - v1, normal)
    }
    let separation = dot(center - closest, normal) - radius
    guard separation <= margin else { return nil }
    let surface = center - normal * radius
    return Manifold(normal: normal, points: [
        ManifoldPoint(position: (closest + surface) * 0.5, separation: separation, id: UInt32(normalIndex)),
    ])
}

/// Largest separation of `b`'s vertices along `a`'s edge normals.
private func findMaxSeparation(
    _ verticesA: [Vector2],
    _ normalsA: [Vector2],
    _ verticesB: [Vector2]
) -> (separation: Float, edge: Int) {
    var best = -Float.greatestFiniteMagnitude
    var edge = 0
    for i in verticesA.indices {
        var minimum = Float.greatestFiniteMagnitude
        for v in verticesB {
            minimum = min(minimum, dot(normalsA[i], v - verticesA[i]))
        }
        if minimum > best {
            best = minimum
            edge = i
        }
    }
    return (best, edge)
}

private struct ClipVertex {
    var position: Vector2
    var id: UInt32
}

/// Clips a segment to the half-space `dot(normal, v) <= offset`.
private func clip(_ input: [ClipVertex], normal: Vector2, offset: Float, clipID: UInt32) -> [ClipVertex] {
    let d0 = dot(normal, input[0].position) - offset
    let d1 = dot(normal, input[1].position) - offset
    var output = [ClipVertex]()
    if d0 <= 0 { output.append(input[0]) }
    if d1 <= 0 { output.append(input[1]) }
    if d0 * d1 < 0 {
        let t = d0 / (d0 - d1)
        output.append(ClipVertex(
            position: input[0].position + t * (input[1].position - input[0].position),
            id: input[0].id | clipID
        ))
    }
    return output
}

/// Separating axis test with reference-face clipping (up to two contact points).
func collidePolygons(
    _ verticesA: [Vector2],
    _ normalsA: [Vector2],
    _ verticesB: [Vector2],
    _ normalsB: [Vector2],
    margin: Float
) -> Manifold? {
    let (separationA, edgeA) = findMaxSeparation(verticesA, normalsA, verticesB)
    guard separationA <= margin else { return nil }
    let (separationB, edgeB) = findMaxSeparation(verticesB, normalsB, verticesA)
    guard separationB <= margin else { return nil }

    // Prefer A as the reference face unless B is clearly better, for coherence.
    let flip = separationB > separationA + 1e-3
    let (refVertices, refNormals, refEdge, incVertices, incNormals) = flip
        ? (verticesB, normalsB, edgeB, verticesA, normalsA)
        : (verticesA, normalsA, edgeA, verticesB, normalsB)

    // Incident edge: most anti-parallel to the reference normal.
    let refNormal = refNormals[refEdge]
    var incidentEdge = 0
    var minimumDot = Float.greatestFiniteMagnitude
    for i in incNormals.indices {
        let d = dot(refNormal, incNormals[i])
        if d < minimumDot {
            minimumDot = d
            incidentEdge = i
        }
    }
    let i1 = incidentEdge
    let i2 = (incidentEdge + 1) % incVertices.count
    let baseID = UInt32(refEdge) << 8 | (flip ? 1 << 16 : 0)
    let incident = [
        ClipVertex(position: incVertices[i1], id: baseID | UInt32(i1)),
        ClipVertex(position: incVertices[i2], id: baseID | UInt32(i2)),
    ]

    let v11 = refVertices[refEdge]
    let v12 = refVertices[(refEdge + 1) % refVertices.count]
    let tangent = normalize(v12 - v11)
    let frontOffset = dot(refNormal, v11)
    let sideOffset1 = -dot(tangent, v11)
    let sideOffset2 = dot(tangent, v12)

    let clipped1 = clip(incident, normal: -tangent, offset: sideOffset1, clipID: 0x40)
    guard clipped1.count >= 2 else { return nil }
    let clipped2 = clip(clipped1, normal: tangent, offset: sideOffset2, clipID: 0x80)
    guard clipped2.count >= 2 else { return nil }

    var points = [ManifoldPoint]()
    for vertex in clipped2 {
        let separation = dot(refNormal, vertex.position) - frontOffset
        guard separation <= margin else { continue }
        points.append(ManifoldPoint(
            position: vertex.position - refNormal * (separation * 0.5),
            separation: separation,
            id: vertex.id
        ))
    }
    guard !points.isEmpty else { return nil }
    return Manifold(normal: flip ? -refNormal : refNormal, points: points)
}
