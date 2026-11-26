//
//  JointTests.swift
//  SpritePhysicsTests
//

import Testing
import SpriteCore
@testable import SpritePhysics

@Suite struct JointTests {

    func makeAnchor(_ world: PhysicsWorld, at position: Vector2 = .zero) -> PhysicsBody {
        let anchor = PhysicsBody(circleOfRadius: 1)
        anchor.isDynamic = false
        anchor.position = position
        anchor.collisionBitMask = .none
        world.add(anchor)
        return anchor
    }

    @Test func pinJointPendulumKeepsLength() {
        let world = PhysicsWorld()
        let anchor = makeAnchor(world)
        let bob = PhysicsBody(circleOfRadius: 5)
        bob.position = [100, 0]
        bob.collisionBitMask = .none
        world.add(bob)
        world.add(PinJoint(bodyA: anchor, bodyB: bob, anchor: .zero))

        var lowest: Float = 0
        for _ in 0 ..< 120 {
            world.step(1.0 / 60.0)
            #expect(abs(length(bob.position) - 100) < 2)
            lowest = min(lowest, bob.position.y)
        }
        // The bob swings down through the bottom of the arc.
        #expect(lowest < -95)
    }

    @Test func jointWaitsForBodiesToJoinWorld() {
        let world = PhysicsWorld()
        let a = PhysicsBody(circleOfRadius: 1)
        let b = PhysicsBody(circleOfRadius: 1)
        b.position = [10, 0]
        world.add(PinJoint(bodyA: a, bodyB: b, anchor: [5, 0]))
        world.add(a)
        world.add(b)
        #expect(world.joints.count == 1)
    }

    @Test func ropeOnlyLimitsMaximumLength() {
        let world = PhysicsWorld()
        let anchor = makeAnchor(world)
        let ball = PhysicsBody(circleOfRadius: 5)
        ball.position = [0, -20]
        ball.collisionBitMask = .none
        world.add(ball)
        world.add(DistanceJoint.rope(bodyA: anchor, bodyB: ball, anchorA: .zero, anchorB: ball.position, maxLength: 50))

        // Within the rope length the ball falls freely.
        world.step(1.0 / 60.0)
        #expect(ball.velocity.y < 0)
        for _ in 0 ..< 120 {
            world.step(1.0 / 60.0)
        }
        #expect(abs(ball.position.y + 50) < 2)
    }

    @Test func rigidRodHoldsDistance() {
        let world = PhysicsWorld()
        world.gravity = .zero
        let a = PhysicsBody(circleOfRadius: 5)
        let b = PhysicsBody(circleOfRadius: 5)
        b.position = [40, 0]
        a.collisionBitMask = .none
        b.collisionBitMask = .none
        world.add(a)
        world.add(b)
        world.add(DistanceJoint(bodyA: a, bodyB: b, anchorA: a.position, anchorB: b.position))
        b.velocity = [0, 200]
        for _ in 0 ..< 60 {
            world.step(1.0 / 60.0)
        }
        #expect(abs(length(b.position - a.position) - 40) < 1)
    }

    @Test func fixedJointWeldsBodies() {
        let world = PhysicsWorld()
        world.gravity = .zero
        let a = PhysicsBody(rectangleOf: [10, 10])
        let b = PhysicsBody(rectangleOf: [10, 10])
        b.position = [10, 0]
        world.add(a)
        world.add(b)
        world.add(FixedJoint(bodyA: a, bodyB: b, anchor: [5, 0]))
        b.applyImpulse([0, 500], at: [15, 0])
        for _ in 0 ..< 60 {
            world.step(1.0 / 60.0)
        }
        #expect(abs((b.rotation - a.rotation)) < 0.02)
        #expect(abs(length(b.position - a.position) - 10) < 0.5)
        #expect(abs(a.angularVelocity) > 0.1)
    }

    @Test func springSettlesAtEquilibrium() {
        let world = PhysicsWorld()
        let anchor = makeAnchor(world)
        let weight = PhysicsBody(circleOfRadius: 5)
        weight.position = [0, -100]
        weight.collisionBitMask = .none
        world.add(weight)
        let spring = SpringJoint(bodyA: anchor, bodyB: weight, anchorA: .zero, anchorB: weight.position, frequency: 2, damping: 1)
        world.add(spring)
        for _ in 0 ..< 600 {
            world.step(1.0 / 60.0)
        }
        // k x = m g with k = m ω²  →  x = g / ω²
        let omega = 2 * Float.pi * 2
        let stretch = 980 / (omega * omega)
        #expect(abs(weight.position.y + 100 + stretch) < 1)
        #expect(length(weight.velocity) < 1)
    }

    @Test func pinJointFrictionDampsSpin() {
        let world = PhysicsWorld()
        world.gravity = .zero
        let anchor = makeAnchor(world)
        let wheel = PhysicsBody(circleOfRadius: 20)
        wheel.angularDamping = 0
        wheel.collisionBitMask = .none
        world.add(wheel)
        let joint = PinJoint(bodyA: anchor, bodyB: wheel, anchor: .zero)
        joint.frictionTorque = wheel.inertia * 10
        world.add(joint)
        wheel.angularVelocity = 5
        for _ in 0 ..< 60 {
            world.step(1.0 / 60.0)
        }
        #expect(abs(wheel.angularVelocity) < 0.01)
    }
}
