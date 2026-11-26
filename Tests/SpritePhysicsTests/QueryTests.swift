//
//  QueryTests.swift
//  SpritePhysicsTests
//

import Testing
import SpriteCore
@testable import SpritePhysics

@Suite struct QueryTests {

    @Test func rayCastFindsClosestBody() throws {
        let world = PhysicsWorld()
        let circle = PhysicsBody(circleOfRadius: 10)
        circle.position = [50, 0]
        let box = PhysicsBody(rectangleOf: [20, 20])
        box.position = [100, 0]
        world.add(circle)
        world.add(box)

        let hit = try #require(world.rayCast(from: [0, 0], to: [200, 0]))
        #expect(hit.body === circle)
        #expect(approx(hit.point, [40, 0]))
        #expect(approx(hit.normal, [-1, 0]))
        #expect(approx(hit.fraction, 0.2))

        let all = world.rayCastAll(from: [0, 0], to: [200, 0])
        #expect(all.count == 2)
        #expect(all[1].body === box)
        #expect(approx(all[1].point, [90, 0]))

        #expect(world.rayCast(from: [0, 50], to: [200, 50]) == nil)
        #expect(world.rayCast(from: [0, 0], to: [30, 0]) == nil)
    }

    @Test func rayCastHonorsMask() throws {
        let world = PhysicsWorld()
        let wall = PhysicsCategory(bit: 0)
        let near = PhysicsBody(circleOfRadius: 5)
        near.position = [20, 0]
        near.categoryBitMask = PhysicsCategory(bit: 1)
        let far = PhysicsBody(rectangleOf: [10, 100])
        far.position = [60, 0]
        far.categoryBitMask = wall
        world.add(near)
        world.add(far)
        let hit = try #require(world.rayCast(from: .zero, to: [100, 0], mask: wall))
        #expect(hit.body === far)
    }

    @Test func rayCastAgainstEdges() throws {
        let world = PhysicsWorld()
        let floor = PhysicsBody(shape: .edge(from: [-100, 0], to: [100, 0]))
        world.add(floor)
        let down = try #require(world.rayCast(from: [10, 50], to: [10, -50]))
        #expect(approx(down.point, [10, 0]))
        #expect(approx(down.normal, [0, 1]))
        let up = try #require(world.rayCast(from: [10, -50], to: [10, 50]))
        #expect(approx(up.normal, [0, -1]))
    }

    @Test func rotatedBoxRayCast() throws {
        let world = PhysicsWorld()
        let box = PhysicsBody(rectangleOf: [20, 20])
        box.rotation = .pi / 4
        world.add(box)
        let hit = try #require(world.rayCast(from: [-50, 0], to: [50, 0]))
        #expect(approx(hit.point.x, -10 * Float(2).squareRoot(), tolerance: 0.01))
    }

    @Test func pointAndRectQueries() {
        let world = PhysicsWorld()
        let a = PhysicsBody(circleOfRadius: 10)
        let b = PhysicsBody(rectangleOf: [10, 10])
        b.position = [100, 100]
        world.add(a)
        world.add(b)
        #expect(world.body(at: [5, 0]) === a)
        #expect(world.body(at: [50, 50]) == nil)
        #expect(world.bodies(at: [100, 100]).count == 1)
        #expect(world.bodies(in: Rect(x: -20, y: -20, width: 200, height: 200)).count == 2)
        #expect(world.bodies(in: Rect(x: 90, y: 90, width: 5, height: 5)).first === b)
    }
}
