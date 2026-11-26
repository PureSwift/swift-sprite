//
//  ShapeTests.swift
//  SpritePhysicsTests
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
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
        #expect(loop.primitives.count == 4)
        #expect(PhysicsShape.edgeChain([[0, 0], [1, 0], [2, 0]]).primitives.count == 2)
    }

    @Test func convexHullIsCounterClockwise() {
        let hull = convexHull([[1, 1], [0, 0], [0, 1], [1, 0], [0.5, 0.5], [0.5, 0]])
        #expect(hull == [[0, 0], [1, 0], [1, 1], [0, 1]])
    }

    @Test func largePolygonsAreSplit() {
        // A 16-gon exceeds Box2D's 8-vertex limit and is fanned into several polygons.
        let points = (0 ..< 16).map { i -> Vector2 in
            let angle = Float(i) / 16 * 2 * .pi
            return Vector2(cosf(angle), sinf(angle)) * 100
        }
        let shape = PhysicsShape.polygon(points)
        #expect(shape.primitives.count > 1)
        let expectedArea = 0.5 * 16 * 10_000 * sinf(2 * .pi / 16)
        #expect(approx(PhysicsBody(shape: shape).area, expectedArea, tolerance: 1))
    }

    @Test func containsPointAndBounds() throws {
        let body = PhysicsBody(rectangleOf: [10, 10])
        body.position = [100, 0]
        body.rotation = .pi / 4
        #expect(body.contains([100, 0]))
        #expect(body.contains([100, 6.5]))
        #expect(!body.contains([105, 5]))
        let bounds = try #require(body.bounds)
        #expect(approx(bounds.width, 10 * Float(2).squareRoot(), tolerance: 0.01))

        let circle = PhysicsBody(circleOfRadius: 5, center: [10, 0])
        circle.rotation = .pi / 2
        let circleBounds = try #require(circle.bounds)
        #expect(approx(circleBounds.center, [0, 10]))
        #expect(approx(circleBounds.size, [10, 10]))
    }

    @Test func propertiesSurviveAttachAndDetach() {
        let world = PhysicsWorld()
        let body = PhysicsBody(circleOfRadius: 1)
        body.position = [5, 6]
        body.velocity = [1, 2]
        world.add(body)
        #expect(body.position == [5, 6])
        #expect(approx(body.velocity, [1, 2]))
        body.position = [7, 8]
        world.remove(body)
        #expect(body.world == nil)
        #expect(body.position == [7, 8])
        #expect(approx(body.velocity, [1, 2]))
    }
}
