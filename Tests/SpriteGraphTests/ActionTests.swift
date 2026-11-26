//
//  ActionTests.swift
//  SpriteGraphTests
//

import Testing
import SpriteCore
@testable import SpriteGraph

@MainActor @Suite struct ActionTests {

    /// Advances `node` (via a temporary scene) in fixed steps.
    func step(_ node: Node, seconds: Double, steps: Int = 1) {
        for _ in 0 ..< steps {
            node.evaluateActions(seconds: seconds / Double(steps))
        }
    }

    @Test func moveByIsIncremental() {
        let node = Node()
        node.run(.move(by: [10, 0], duration: .seconds(1)))
        step(node, seconds: 0.5)
        #expect(approx(node.position, [5, 0]))
        // External changes during an incremental action are preserved.
        node.position.y = 3
        step(node, seconds: 0.5)
        #expect(approx(node.position, [10, 3]))
        #expect(!node.hasActions)
    }

    @Test func moveToInterpolatesFromStart() {
        let node = Node()
        node.position = [10, 10]
        node.run(.move(to: [20, 30], duration: .seconds(2)))
        step(node, seconds: 1)
        #expect(approx(node.position, [15, 20]))
        step(node, seconds: 5)
        #expect(approx(node.position, [20, 30]))
    }

    @Test func sequenceCarriesLeftoverTime() {
        let node = Node()
        node.run(.sequence([
            .move(by: [10, 0], duration: .seconds(1)),
            .move(by: [0, 10], duration: .seconds(1)),
        ]))
        step(node, seconds: 1.5)
        #expect(approx(node.position, [10, 5]))
        step(node, seconds: 0.5)
        #expect(approx(node.position, [10, 10]))
        #expect(!node.hasActions)
    }

    @Test func groupRunsInParallel() {
        let node = Node()
        let group = Action.group([
            .move(by: [10, 0], duration: .seconds(1)),
            .rotate(by: 1, duration: .seconds(2)),
        ])
        #expect(group.duration == .seconds(2))
        node.run(group)
        step(node, seconds: 1)
        #expect(approx(node.position, [10, 0]))
        #expect(approx(node.zRotation, 0.5))
        step(node, seconds: 1)
        #expect(approx(node.zRotation, 1))
        #expect(!node.hasActions)
    }

    @Test func repeatCountAndForever() {
        let node = Node()
        node.run(.repeat(.move(by: [1, 0], duration: .seconds(1)), count: 3))
        step(node, seconds: 10, steps: 7)
        #expect(approx(node.position, [3, 0]))
        #expect(!node.hasActions)

        var count = 0
        node.run(.repeatForever(.sequence([.wait(for: .seconds(1)), .run { _ in count += 1 }])), withKey: "tick")
        step(node, seconds: 3.5, steps: 7)
        #expect(count == 3)
        #expect(node.action(forKey: "tick") != nil)
        node.removeAction(forKey: "tick")
        #expect(!node.hasActions)
    }

    @Test func instantRepeatForeverRunsOncePerFrame() {
        let node = Node()
        var count = 0
        node.run(.repeatForever(.run { _ in count += 1 }))
        step(node, seconds: 1, steps: 4)
        #expect(count == 4)
    }

    @Test func timingModeAndSpeed() {
        let eased = Node()
        eased.run(.moveTo(x: 100, duration: .seconds(1)).timingMode(.easeIn))
        step(eased, seconds: 0.5)
        #expect(approx(eased.position.x, 25))
        step(eased, seconds: 0.5)
        #expect(approx(eased.position.x, 100))

        let fast = Node()
        let action = Action.moveTo(x: 100, duration: .seconds(2)).speed(2)
        #expect(action.duration == .seconds(1))
        fast.run(action)
        step(fast, seconds: 0.5)
        #expect(approx(fast.position.x, 50))
    }

    @Test func nodeSpeedAndPauseAffectDescendants() {
        let parent = Node()
        let child = Node()
        parent.addChild(child)
        child.run(.moveTo(x: 10, duration: .seconds(1)))
        parent.speed = 0.5
        step(parent, seconds: 1)
        #expect(approx(child.position.x, 5))
        parent.isPaused = true
        step(parent, seconds: 1)
        #expect(approx(child.position.x, 5))
    }

    @Test func keyedActionsReplaceEachOther() {
        let node = Node()
        var firstCompleted = false
        node.run(.moveTo(x: 10, duration: .seconds(1)), withKey: "move") { firstCompleted = true }
        node.run(.moveTo(x: -10, duration: .seconds(1)), withKey: "move")
        step(node, seconds: 1)
        #expect(approx(node.position.x, -10))
        #expect(!firstCompleted)
    }

    @Test func completionAndRemoveFromParent() {
        let parent = Node()
        let child = Node()
        parent.addChild(child)
        var completed = false
        child.run(.sequence([.fadeOut(duration: .seconds(1)), .removeFromParent()])) { completed = true }
        step(parent, seconds: 1)
        #expect(child.alpha == 0)
        #expect(child.parent == nil)
        #expect(completed)
    }

    @Test func spriteActions() {
        let frames = (1 ... 4).map {
            Texture(id: TextureID(rawValue: UInt32($0)), textureSize: Vector2(repeating: Float($0 * 8)))
        }
        let sprite = Sprite(texture: frames[0])
        sprite.run(.animate(with: frames, timePerFrame: .milliseconds(250), resize: true))
        step(sprite, seconds: 0.6)
        #expect(sprite.texture == frames[2])
        #expect(sprite.size == [24, 24])

        sprite.run(.group([
            .resize(to: [100, 50], duration: .seconds(1)),
            .colorize(with: .red, blendFactor: 1, duration: .seconds(1)),
        ]))
        step(sprite, seconds: 2)
        #expect(sprite.size == [100, 50])
        #expect(sprite.color == .red && sprite.colorBlendFactor == 1)
    }

    @Test func rotateToShortestArc() {
        let node = Node()
        node.zRotation = 0.1
        node.run(.rotate(to: 2 * .pi - 0.1, duration: .seconds(1), shortestUnitArc: true))
        step(node, seconds: 1)
        #expect(approx(node.zRotation, -0.1))
    }

    @Test func customActionReportsElapsedTime() {
        let node = Node()
        var times = [Duration]()
        node.run(.customAction(duration: .seconds(1)) { _, elapsed in times.append(elapsed) })
        step(node, seconds: 1, steps: 2)
        #expect(times == [.seconds(0.5), .seconds(1)])
    }

    @Test func runAndWaitResumesOnCompletionAndRemoval() async {
        let node = Node()
        async let finished: Void = node.runAndWait(.wait(for: .seconds(1)))
        while !node.hasActions { await Task.yield() }
        step(node, seconds: 1)
        await finished

        async let removed: Void = node.runAndWait(.wait(for: .seconds(10)), withKey: "long")
        while !node.hasActions { await Task.yield() }
        node.removeAllActions()
        await removed
        #expect(!node.hasActions)
    }

    @Test func sceneAdvanceRunsActionsAndHooks() {
        final class TestScene: Scene {
            var updates = [Duration]()
            override func update(_ deltaTime: Duration) { updates.append(deltaTime) }
        }
        let scene = TestScene(size: [100, 100])
        let node = Node()
        scene.addChild(node)
        node.run(.moveTo(x: 10, duration: .seconds(1)))
        scene.advance(by: .milliseconds(500))
        #expect(scene.updates == [.milliseconds(500)])
        #expect(approx(node.position.x, 5))
        scene.isPaused = true
        scene.advance(by: .milliseconds(500))
        #expect(approx(node.position.x, 5))
    }
}
