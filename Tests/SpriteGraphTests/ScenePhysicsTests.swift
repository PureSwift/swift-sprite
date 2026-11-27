//
//  ScenePhysicsTests.swift
//  SpriteGraphTests
//

import Testing
import SpriteCore
import SpritePhysics
@testable import SpriteGraph

@MainActor @Suite struct ScenePhysicsTests {

    func step(_ scene: Scene, seconds: Double) {
        for _ in 0 ..< Int((seconds * 60).rounded()) {
            scene.advance(by: .seconds(1.0 / 60.0))
        }
    }

    @Test func dynamicBodiesMoveTheirNodes() {
        let scene = Scene(size: [400, 400])
        let ball = Sprite(color: .red, size: [10, 10])
        ball.position = [200, 300]
        ball.physicsBody = PhysicsBody(circleOfRadius: 5)
        scene.addChild(ball)
        step(scene, seconds: 0.5)
        #expect(ball.position.y < 250)
        #expect(ball.physicsBody?.node === ball)
        #expect(scene.physicsWorld.bodies.count == 1)
    }

    @Test func sceneEdgeLoopContainsBodies() {
        let scene = Scene(size: [400, 400])
        scene.physicsBody = PhysicsBody(edgeLoopFrom: Rect(x: 0, y: 0, width: 400, height: 400))
        let box = Node()
        box.position = [200, 200]
        box.physicsBody = PhysicsBody(rectangleOf: [20, 20])
        scene.addChild(box)
        step(scene, seconds: 2)
        #expect(abs(box.position.y - 10) < 1)
        #expect(scene.physicsBody?.isDynamic == false)
    }

    @Test func nestedNodesConvertCoordinates() {
        let scene = Scene(size: [400, 400])
        let container = Node()
        container.position = [100, 100]
        container.zRotation = .pi / 2
        scene.addChild(container)
        let child = Node()
        child.position = [50, 0]
        child.physicsBody = PhysicsBody(circleOfRadius: 5)
        child.physicsBody?.affectedByGravity = false
        container.addChild(child)

        step(scene, seconds: 1.0 / 60.0)
        // Local (50, 0) in a container rotated 90° at (100, 100) is (100, 150) in the scene.
        #expect(approx(child.physicsBody!.position, [100, 150]))

        // Pushing the body in scene +x moves the child along the container's -y axis.
        child.physicsBody?.velocity = [60, 0]
        child.physicsBody?.linearDamping = 0
        step(scene, seconds: 1)
        #expect(approx(child.position, [50, -60], tolerance: 1))
    }

    @Test func movingNodesTeleportBodies() {
        let scene = Scene(size: [400, 400])
        let platform = Node()
        platform.position = [100, 100]
        platform.physicsBody = PhysicsBody(rectangleOf: [50, 10])
        platform.physicsBody?.isDynamic = false
        scene.addChild(platform)
        step(scene, seconds: 1.0 / 60.0)
        platform.run(.moveTo(x: 300, duration: .milliseconds(100)))
        step(scene, seconds: 0.5)
        #expect(approx(platform.physicsBody!.position, [300, 100]))
        // Static bodies never write back to their nodes.
        #expect(platform.position == [300, 100])
    }

    @Test func pinnedNodeFollowsExplicitParentTransforms() {
        let scene = Scene(size: [400, 400])
        let parent = Node()
        parent.position = [100, 100]
        let child = Node()
        child.position = [30, 0]
        let body = PhysicsBody(circleOfRadius: 5)
        body.isPinned = true
        child.physicsBody = body
        parent.addChild(child)
        scene.addChild(parent)
        step(scene, seconds: 0.5)
        #expect(approx(child.position, [30, 0], tolerance: 0.1))
        parent.position = [200, 200]
        parent.zRotation = .pi / 2
        step(scene, seconds: 0.5)
        #expect(approx(body.position, [200, 230], tolerance: 0.1))
        #expect(approx(child.position, [30, 0], tolerance: 0.1))
        child.removeFromParent()
        step(scene, seconds: 1.0 / 60)
        #expect(body.world == nil)
        parent.addChild(child)
        step(scene, seconds: 0.5)
        #expect(approx(body.position, [200, 230], tolerance: 0.1))
        body.isPinned = false
        step(scene, seconds: 0.5)
        #expect(body.position.y < 200)
    }

    @Test func removedNodesLeaveTheWorld() {
        let scene = Scene(size: [400, 400])
        let node = Node()
        let body = PhysicsBody(circleOfRadius: 5)
        node.physicsBody = body
        scene.addChild(node)
        step(scene, seconds: 1.0 / 60.0)
        #expect(body.world === scene.physicsWorld)
        node.removeFromParent()
        step(scene, seconds: 1.0 / 60.0)
        #expect(body.world == nil)
        #expect(scene.physicsWorld.bodies.isEmpty)
    }

    @Test func contactsReportNodes() {
        let scene = Scene(size: [400, 400])
        let groundCategory = PhysicsCategory(bit: 0)
        let ground = Node()
        ground.name = "ground"
        ground.position = [200, 10]
        ground.physicsBody = PhysicsBody(rectangleOf: [400, 20])
        ground.physicsBody?.isDynamic = false
        ground.physicsBody?.categoryBitMask = groundCategory
        let ball = Node()
        ball.name = "ball"
        ball.position = [200, 100]
        ball.physicsBody = PhysicsBody(circleOfRadius: 10)
        ball.physicsBody?.contactTestBitMask = groundCategory
        scene.addChildren {
            ground
            ball
        }
        var names = Set<String>()
        scene.physicsWorld.onContactBegin = { contact in
            names.insert(contact.bodyA.node?.name ?? "")
            names.insert(contact.bodyB.node?.name ?? "")
        }
        step(scene, seconds: 1)
        #expect(names == ["ground", "ball"])
    }

    @Test func pausedScenesDoNotSimulate() {
        let scene = Scene(size: [400, 400])
        let ball = Node()
        ball.position = [200, 300]
        ball.physicsBody = PhysicsBody(circleOfRadius: 5)
        scene.addChild(ball)
        scene.isPaused = true
        step(scene, seconds: 0.5)
        #expect(ball.position == [200, 300])
    }
}
