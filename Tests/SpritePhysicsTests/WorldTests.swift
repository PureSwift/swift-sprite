//
//  WorldTests.swift
//  SpritePhysicsTests
//

import Testing
import SpriteCore
@testable import SpritePhysics

/// World with a static ground slab whose top surface is at y = 0.
func makeWorld() -> (PhysicsWorld, ground: PhysicsBody) {
    let world = PhysicsWorld()
    let ground = PhysicsBody(rectangleOf: [2000, 20])
    ground.isDynamic = false
    ground.position = [0, -10]
    world.add(ground)
    return (world, ground)
}

func run(_ world: PhysicsWorld, seconds: Double) {
    for _ in 0 ..< Int((seconds * 60).rounded()) {
        world.step(1.0 / 60.0)
    }
}

@Suite struct WorldTests {

    @Test func freeFallMatchesSemiImplicitEuler() {
        let world = PhysicsWorld()
        let body = PhysicsBody(circleOfRadius: 1)
        body.linearDamping = 0
        world.add(body)
        run(world, seconds: 1)
        #expect(approx(body.velocity.y, -980, tolerance: 0.1))
        // Σ v_i dt = g dt² n(n+1)/2
        #expect(approx(body.position.y, -980 / 3600 * 1830, tolerance: 0.1))
    }

    @Test func fixedTimestepAccumulates() {
        let world = PhysicsWorld()
        let body = PhysicsBody(circleOfRadius: 1)
        world.add(body)
        world.simulate(elapsed: 0.5 / 60)
        #expect(body.velocity == .zero)
        world.simulate(elapsed: 0.5 / 60)
        #expect(body.velocity.y < 0)
        world.speed = 0
        let velocity = body.velocity
        world.simulate(elapsed: 1)
        #expect(body.velocity == velocity)
    }

    @Test func boxComesToRestOnGround() {
        let (world, _) = makeWorld()
        let box = PhysicsBody(rectangleOf: [20, 20])
        box.position = [0, 30]
        world.add(box)
        run(world, seconds: 3)
        #expect(abs(box.position.y - 10) < world.linearSlop + 0.5)
        #expect(length(box.velocity) < 1)
        #expect(abs(box.rotation) < 0.01)
    }

    @Test func stackRemainsStable() {
        let (world, _) = makeWorld()
        var boxes = [PhysicsBody]()
        for i in 0 ..< 6 {
            let box = PhysicsBody(rectangleOf: [20, 20])
            box.position = [0, 10 + Float(i) * 20.5]
            world.add(box)
            boxes.append(box)
        }
        run(world, seconds: 5)
        for (i, box) in boxes.enumerated() {
            #expect(abs(box.position.x) < 1, "Box \(i) drifted to \(box.position)")
            #expect(abs(box.position.y - (10 + Float(i) * 20)) < 3, "Box \(i) at \(box.position)")
            #expect(abs(box.rotation) < 0.05)
        }
    }

    @Test func circleRollsDownRampWithFriction() {
        let (world, _) = makeWorld()
        let ramp = PhysicsBody(shape: .polygon([[-200, 0], [0, 0], [-200, 100]]))
        ramp.isDynamic = false
        world.add(ramp)
        let ball = PhysicsBody(circleOfRadius: 10)
        ball.position = [-180, 105]
        ball.friction = 1
        ramp.friction = 1
        world.add(ball)
        run(world, seconds: 1)
        #expect(ball.position.x > -150)
        // Friction makes the ball spin clockwise (negative) while rolling right.
        #expect(ball.angularVelocity < -1)
    }

    @Test func restitutionBounces() {
        func maxHeightAfterBounce(restitution: Float) -> Float {
            let (world, ground) = makeWorld()
            let ball = PhysicsBody(circleOfRadius: 10)
            ball.restitution = restitution
            ball.linearDamping = 0
            ground.restitution = restitution
            ball.position = [0, 200]
            world.add(ball)
            // Fall until the first contact, then track the peak after it.
            var bounced = false
            var peak: Float = 0
            for _ in 0 ..< 240 {
                world.step(1.0 / 60.0)
                if ball.velocity.y > 0 { bounced = true }
                if bounced { peak = max(peak, ball.position.y) }
            }
            return peak
        }
        #expect(maxHeightAfterBounce(restitution: 1) > 160)
        #expect(maxHeightAfterBounce(restitution: 0) < 20)
    }

    @Test func frictionStopsSlidingBox() {
        func slide(friction: Float) -> Float {
            let (world, ground) = makeWorld()
            ground.friction = friction
            let box = PhysicsBody(rectangleOf: [20, 20])
            box.friction = friction
            box.linearDamping = 0
            box.position = [0, 10]
            box.velocity = [200, 0]
            world.add(box)
            run(world, seconds: 1)
            return box.velocity.x
        }
        #expect(abs(slide(friction: 1)) < 1)
        #expect(approx(slide(friction: 0), 200, tolerance: 1))
    }

    @Test func collisionMasksFilterResponse() {
        let (world, ground) = makeWorld()
        let ghost = PhysicsBody(circleOfRadius: 5)
        ghost.position = [0, 20]
        ghost.collisionBitMask = .none
        world.add(ghost)
        let solid = PhysicsBody(circleOfRadius: 5)
        solid.position = [50, 20]
        world.add(solid)
        run(world, seconds: 1)
        #expect(ghost.position.y < -100)
        #expect(solid.position.y > 0)

        // Asymmetric: the static ground is never pushed, and a heavy body ignoring a light one is not either.
        let player = PhysicsCategory(bit: 1)
        let debris = PhysicsCategory(bit: 2)
        let heavy = PhysicsBody(rectangleOf: [20, 20])
        heavy.categoryBitMask = player
        heavy.collisionBitMask = .all.subtracting(debris)
        heavy.position = [200, 10]
        heavy.affectedByGravity = false
        let light = PhysicsBody(rectangleOf: [10, 10])
        light.categoryBitMask = debris
        light.position = [180, 10]
        light.velocity = [100, 0]
        light.affectedByGravity = false
        world.add(heavy)
        world.add(light)
        _ = ground
        run(world, seconds: 0.5)
        #expect(approx(heavy.velocity.x, 0, tolerance: 0.01))
        #expect(light.velocity.x < 50)
    }

    @Test func contactEventsRespectTestMask() {
        let (world, ground) = makeWorld()
        var begins = 0, ends = 0
        world.onContactBegin = { contact in
            begins += 1
            #expect(contact.involves(ground))
            #expect(contact.collisionImpulse >= 0)
        }
        world.onContactEnd = { _ in ends += 1 }

        let quiet = PhysicsBody(circleOfRadius: 5)
        quiet.position = [-100, 10]
        world.add(quiet)
        let reporter = PhysicsBody(circleOfRadius: 5)
        reporter.position = [100, 10]
        reporter.contactTestBitMask = .all
        reporter.restitution = 0
        ground.restitution = 0
        world.add(reporter)
        run(world, seconds: 1)
        #expect(begins == 1)
        #expect(ends == 0)
        #expect(reporter.allContactedBodies().first === ground)

        reporter.velocity = [0, 500]
        run(world, seconds: 0.1)
        #expect(ends == 1)
    }

    @Test func sensorsReportWithoutColliding() {
        let world = PhysicsWorld()
        world.gravity = .zero
        let sensor = PhysicsBody(rectangleOf: [50, 50])
        sensor.isDynamic = false
        sensor.collisionBitMask = .none
        sensor.categoryBitMask = PhysicsCategory(bit: 3)
        let ball = PhysicsBody(circleOfRadius: 5)
        ball.position = [-100, 0]
        ball.velocity = [200, 0]
        ball.linearDamping = 0
        ball.collisionBitMask = .all.subtracting(PhysicsCategory(bit: 3))
        ball.contactTestBitMask = PhysicsCategory(bit: 3)
        world.add(sensor)
        world.add(ball)
        var entered = false, exited = false
        world.onContactBegin = { _ in entered = true }
        world.onContactEnd = { _ in exited = true }
        run(world, seconds: 1.5)
        #expect(entered && exited)
        #expect(approx(ball.velocity.x, 200, tolerance: 0.01))
    }

    @Test func impulsesAndForces() {
        let world = PhysicsWorld()
        world.gravity = .zero
        let body = PhysicsBody(rectangleOf: [10, 10])
        body.linearDamping = 0
        body.angularDamping = 0
        world.add(body)
        body.applyImpulse([100, 0])
        #expect(approx(body.velocity, [1, 0]))
        body.applyImpulse([0, 100], at: [5, 0])
        #expect(body.angularVelocity > 0)

        let spinner = PhysicsBody(rectangleOf: [10, 10])
        spinner.allowsRotation = false
        spinner.applyImpulse([0, 100], at: [5, 0])
        #expect(spinner.angularVelocity == 0)

        let pushed = PhysicsBody(circleOfRadius: 1)
        pushed.position = [100, 0]
        pushed.linearDamping = 0
        world.add(pushed)
        pushed.applyForce([pushed.mass * 60, 0])
        world.step(1.0 / 60.0)
        #expect(approx(pushed.velocity.x, 1))
        world.step(1.0 / 60.0)
        // Forces are cleared after each step.
        #expect(approx(pushed.velocity.x, 1))
    }

    @Test func removingBodiesClearsWorld() {
        let (world, ground) = makeWorld()
        #expect(ground.world === world)
        world.remove(ground)
        #expect(ground.world == nil)
        #expect(world.bodies.isEmpty)
    }
}
