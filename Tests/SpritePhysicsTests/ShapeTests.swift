//
//  ShapeTests.swift
//  SpritePhysicsTests
//

import Testing
import SpriteCore
@testable import SpritePhysics

func approx(_ a: Float, _ b: Float, tolerance: Float = 1e-3) -> Bool {
    abs(a - b) <= tolerance
}

func approx(_ a: Vector2, _ b: Vector2, tolerance: Float = 1e-3) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

@Suite struct ShapeTests {

    @Test func rectangleMassProperties() {
        let body = PhysicsBody(rectangleOf: [10, 20])
        #expect(approx(body.area, 200))
        #expect(approx(body.mass, 200))
        #expect(approx(body.inertia, 200 * (100 + 400) / 12, tolerance: 0.5))
        #expect(approx(body.localCenter, .zero))
        #expect(body.isDynamic)

        body.mass = 50
        #expect(approx(body.density, 0.25))
        #expect(approx(body.inertia, 50 * 500 / 12, tolerance: 0.5))
    }

    @Test func offsetShapesShiftCenterOfMass() {
        let body = PhysicsBody(rectangleOf: [10, 20], center: [5, 0])
        #expect(approx(body.localCenter, [5, 0]))
        // Inertia is about the center of mass, so unaffected by the offset.
        #expect(approx(body.inertia, 200 * 500 / 12, tolerance: 0.5))
        body.rotation = .pi / 2
        #expect(approx(body.worldCenter, [0, 5]))
    }

    @Test func circleMassProperties() {
        let body = PhysicsBody(circleOfRadius: 2)
        let mass = Float.pi * 4
        #expect(approx(body.mass, mass))
        #expect(approx(body.inertia, mass * 2))
    }

    @Test func compoundCombinesParts() {
        let body = PhysicsBody(shape: .compound([
            .rectangle(size: [2, 2], center: [-5, 0]),
            .rectangle(size: [2, 2], center: [5, 0]),
        ]))
        #expect(approx(body.mass, 8))
        #expect(approx(body.localCenter, .zero))
        // Parallel axis: 2 × (I_box + m d²) = 2 × (4 × 8/12 + 4 × 25).
        #expect(approx(body.inertia, 2 * (4 * 8 / 12 + 100), tolerance: 0.01))
    }

    @Test func edgesAreStatic() {
        let edge = PhysicsBody(shape: .edge(from: [0, 0], to: [10, 0]))
        #expect(edge.area == 0 && !edge.isDynamic)
        let loop = PhysicsBody(edgeLoopFrom: Rect(x: 0, y: 0, width: 10, height: 10))
        #expect(loop.parts.count == 4)
        #expect(PhysicsShape.edgeChain([[0, 0], [1, 0], [2, 0]]).parts.count == 2)
    }

    @Test func convexHullIsCounterClockwise() {
        let hull = convexHull([[1, 1], [0, 0], [0, 1], [1, 0], [0.5, 0.5], [0.5, 0]])
        #expect(hull == [[0, 0], [1, 0], [1, 1], [0, 1]])
        // Clockwise polygons are normalized.
        let part = ConvexPart.polygon([[0, 0], [0, 1], [1, 1], [1, 0]])
        guard case let .polygon(vertices, normals) = part else {
            Issue.record("Expected polygon")
            return
        }
        #expect(vertices.first == [0, 0] && vertices[1] == [1, 0])
        #expect(normals[0] == [0, -1])
    }

    @Test func containsPoint() {
        let body = PhysicsBody(rectangleOf: [10, 10])
        body.position = [100, 0]
        body.rotation = .pi / 4
        #expect(body.contains([100, 0]))
        #expect(body.contains([100, 6.5]))
        #expect(!body.contains([105, 5]))
        let bounds = try! #require(body.bounds)
        #expect(approx(bounds.width, 10 * 2.0.squareRoot().asFloat, tolerance: 0.01))
    }

    @Test func circleCircleManifold() throws {
        let manifold = try #require(collideCircles([0, 0], 1, [1.5, 0], 1, margin: 0))
        #expect(manifold.normal == [1, 0])
        #expect(approx(manifold.points[0].separation, -0.5))
        #expect(approx(manifold.points[0].position, [0.75, 0]))
        #expect(collideCircles([0, 0], 1, [3, 0], 1, margin: 0.5) == nil)
    }

    @Test func boxBoxManifoldHasTwoPoints() throws {
        let a = ConvexPart.polygon([[-1, -1], [1, -1], [1, 1], [-1, 1]])!
        let b = ConvexPart.polygon([[-1, 0.9], [1, 0.9], [1, 2.9], [-1, 2.9]])!
        let manifold = try #require(collide(a, b, margin: 0))
        #expect(approx(manifold.normal, [0, 1]))
        #expect(manifold.points.count == 2)
        #expect(manifold.points.allSatisfy { approx($0.separation, -0.1) })
    }

    @Test func circleAgainstPolygonCorner() throws {
        let box = ConvexPart.polygon([[-1, -1], [1, -1], [1, 1], [-1, 1]])!
        let circle = ConvexPart.circle(center: [1.5, 1.5], radius: 1)
        let manifold = try #require(collide(box, circle, margin: 0))
        #expect(approx(manifold.normal, normalize([1, 1])))
        // Reversed order flips the normal.
        let reversed = try #require(collide(circle, box, margin: 0))
        #expect(approx(reversed.normal, -normalize([1, 1])))
    }
}

private extension Double {
    var asFloat: Float { Float(self) }
}
