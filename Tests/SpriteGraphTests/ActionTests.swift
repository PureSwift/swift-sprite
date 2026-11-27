//
//  ActionTests.swift
//  SpriteGraphTests
//

import Testing
import SpriteCore
@testable import SpriteGraph

@MainActor @Suite struct ActionTests {

    @Test func sizeBasedScaleHandlesZeroDimensionsAndPlainNodes() {
        let scene = Scene(size: [200, 100])
        let sprite = Sprite(color: .white, size: [0, 20])
        sprite.scale = [3, 2]
        let node = Node()
        node.scale = [4, 5]
        scene.addChild(sprite)
        scene.addChild(node)
        let action = Action.scale(toSize: [40, 80], duration: .seconds(2))
        sprite.run(action)
        node.run(action)
        scene.advance(by: .seconds(1))
        #expect(sprite.scale == [3, 3])
        #expect(node.scale == [4, 5])
        scene.advance(by: .seconds(1))
        #expect(sprite.scale == [3, 4])
        #expect(sprite.size == [0, 20])
        #expect(!sprite.hasActions && !node.hasActions)
    }

    @Test func speedChangesAffectDescendantsOnFollowingFrames() {
        let scene = Scene(size: [100, 100])
        let parent = Node()
        let child = Node()
        scene.addChild(parent)
        parent.addChild(child)
        parent.run(.changeSpeed(to: 2, duration: .zero))
        child.run(.move(by: [10, 0], duration: .seconds(1)))
        scene.advance(by: .milliseconds(250))
        #expect(parent.speed == 2 && child.position.x == 2.5)
        scene.advance(by: .milliseconds(250))
        #expect(child.position.x == 7.5)
        parent.isPaused = true
        scene.advance(by: .seconds(1))
        #expect(child.position.x == 7.5)
        parent.isPaused = false
        scene.advance(by: .milliseconds(125))
        #expect(child.position.x == 10 && !child.hasActions)
    }

    @Test func relativeSpeedCapturesValueWhenSequenceReachesIt() {
        let scene = Scene(size: [100, 100])
        let node = Node()
        scene.addChild(node)
        node.run(.sequence([
            .changeSpeed(to: 3, duration: .zero),
            .changeSpeed(by: 2, duration: .zero)
        ]))
        scene.advance(by: .milliseconds(1))
        #expect(node.speed == 6 && !node.hasActions)
    }

    @Test func childActionLooksUpAtPlaybackAndRunsIndependently() {
        let scene = Scene(size: [100, 100])
        let target = Node()
        target.name = "before"
        scene.addChild(target)
        scene.run(.sequence([
            .wait(for: .seconds(1)),
            .run(.move(by: [10, 0], duration: .seconds(1)), onChildWithName: "target")
        ]))
        scene.advance(by: .milliseconds(500))
        target.name = "target"
        scene.advance(by: .milliseconds(500))
        #expect(!scene.hasActions && target.hasActions)
        scene.removeAllActions()
        scene.advance(by: .seconds(1))
        #expect(target.position.x == 10 && !target.hasActions)
        scene.run(.run(.move(by: [100, 0], duration: .zero), onChildWithName: "absent"))
        scene.advance(by: .milliseconds(1))
        #expect(!scene.hasActions && target.position.x == 10)
    }

    @Test func childPathResolvesLateAndIgnoresMissingIntermediateNodes() {
        let scene = Scene(size: [100, 100])
        let container = Node()
        container.name = "container"
        scene.addChild(container)
        scene.run(.sequence([
            .wait(for: .seconds(1)),
            .run(.move(by: [10, 0], duration: .zero), onChildWithName: "container/target")
        ]))
        scene.advance(by: .milliseconds(500))
        let target = Node()
        target.name = "target"
        container.addChild(target)
        scene.advance(by: .milliseconds(500))
        #expect(target.position.x == 10)
        scene.run(.run(.move(by: [100, 0], duration: .zero), onChildWithName: "absent/target"))
        scene.advance(by: .milliseconds(1))
        #expect(target.position.x == 10 && !scene.hasActions)
    }

    @Test func rootChildPathUsesCurrentTreeAfterReparenting() {
        let oldScene = Scene(size: [100, 100])
        let newScene = Scene(size: [100, 100])
        let caller = Node()
        let oldTarget = Node()
        let newTarget = Node()
        oldTarget.name = "target"
        newTarget.name = "target"
        oldScene.addChild(caller)
        oldScene.addChild(oldTarget)
        newScene.addChild(newTarget)
        caller.run(.sequence([
            .wait(for: .seconds(1)),
            .run(.move(by: [10, 0], duration: .zero), onChildWithName: "/target")
        ]))
        oldScene.advance(by: .milliseconds(500))
        caller.removeFromParent()
        newScene.addChild(caller)
        newScene.advance(by: .milliseconds(500))
        newScene.advance(by: .milliseconds(1))
        #expect(newTarget.position.x == 10 && oldTarget.position == .zero)
        #expect(!caller.hasActions)
    }

    @Test func parentPathsDoNotClimbAboveRoot() {
        let scene = Scene(size: [100, 100])
        let caller = Node(), target = Node()
        caller.name = "caller"
        target.name = "target"
        scene.addChild(caller)
        scene.addChild(target)
        caller.run(.run(.move(by: [10, 0], duration: .zero), onChildWithName: "./../target"))
        scene.advance(by: .milliseconds(1))
        #expect(target.position.x == 10)
        caller.run(.run(.move(by: [100, 0], duration: .zero), onChildWithName: "../../target"))
        scene.advance(by: .milliseconds(1))
        #expect(target.position.x == 10 && !caller.hasActions)
        let detached = Node()
        detached.run(.run(.move(by: [100, 0], duration: .zero), onChildWithName: ".."))
        detached.evaluateActions(seconds: 1)
        #expect(detached.position == .zero && !detached.hasActions)
    }

    @Test func relativeResizeComposesAndIgnoresPlainNodes() {
        let scene = Scene(size: [200, 100])
        let sprite = Sprite(color: .white, size: [20, 30])
        let node = Node()
        scene.addChild(sprite)
        scene.addChild(node)
        let action = Action.group([
            .resize(by: [10, -10], duration: .seconds(2)),
            .resize(by: [20, 10], duration: .seconds(2))
        ])
        sprite.run(action)
        node.run(action)
        scene.advance(by: .seconds(1))
        #expect(sprite.size == [35, 30])
        scene.advance(by: .seconds(1))
        #expect(sprite.size == [50, 30])
        #expect(!sprite.hasActions && !node.hasActions)
    }

    @Test(arguments: 0..<6)
    func cancellingNestedTextureAnimationRestoresOriginal(wrapper: Int) {
        let original = Texture(id: TextureID(rawValue: 1), textureSize: [12, 8])
        let frame = Texture(id: TextureID(rawValue: 2), textureSize: [24, 16])
        let sprite = Sprite(texture: original)
        let animation = Action.animate(with: [frame], timePerFrame: .seconds(1), resize: true, restore: true)
        let action: Action
        switch wrapper {
        case 0: action = animation
        case 1: action = .sequence([.wait(for: .milliseconds(100)), animation])
        case 2: action = .group([animation, .wait(for: .seconds(2))])
        case 3: action = .repeat(animation, count: 3)
        case 4: action = .repeatForever(animation)
        default: action = animation.timingMode(.easeIn)
        }
        var completed = false
        sprite.run(action, withKey: "flipbook") { completed = true }
        step(sprite, seconds: 0.25)
        #expect(sprite.texture == frame && sprite.size == frame.size)
        sprite.removeAction(forKey: "flipbook")
        #expect(sprite.texture == original && sprite.size == original.size)
        #expect(!sprite.hasActions && !completed)
    }

    @Test func removingAndReplacingTextureAnimations() {
        let original = Texture(id: TextureID(rawValue: 1), textureSize: [12, 8])
        let frame = Texture(id: TextureID(rawValue: 2), textureSize: [24, 16])
        let sprite = Sprite(texture: original)
        sprite.size = [5, 7]
        let animation = Action.animate(with: [frame], timePerFrame: .seconds(1), restore: true)
        sprite.run(animation, withKey: "flipbook")
        step(sprite, seconds: 0.25)
        sprite.run(animation, withKey: "flipbook")
        #expect(sprite.texture == original && sprite.size == [5, 7])
        step(sprite, seconds: 0.25)
        sprite.removeAllActions()
        #expect(sprite.texture == original && sprite.size == [5, 7])
        sprite.texture = nil
        sprite.run(animation)
        step(sprite, seconds: 0.25)
        sprite.removeAllActions()
        #expect(sprite.texture == nil && sprite.size == [5, 7])
        sprite.run(.animate(with: [frame], timePerFrame: .seconds(1), restore: false))
        step(sprite, seconds: 0.25)
        sprite.removeAllActions()
        #expect(sprite.texture == frame)
    }

    @Test func cancellationDoesNotRestoreInactiveAnimation() {
        let original = Texture(id: TextureID(rawValue: 1), textureSize: [12, 8])
        let frame = Texture(id: TextureID(rawValue: 2), textureSize: [24, 16])
        let sprite = Sprite(texture: original)
        let animation = Action.animate(with: [frame], timePerFrame: .seconds(1), restore: true)
        sprite.run(.sequence([.wait(for: .seconds(1)), animation]))
        step(sprite, seconds: 0.25)
        sprite.texture = frame
        sprite.removeAllActions()
        #expect(sprite.texture == frame)
        sprite.texture = original
        sprite.run(.group([animation, .wait(for: .seconds(10))]))
        step(sprite, seconds: 2)
        #expect(sprite.texture == original)
        sprite.texture = frame
        sprite.removeAllActions()
        #expect(sprite.texture == frame)
    }

    @Test func cancellationInsideCallbackStopsComposite() {
        let sprite = Sprite(texture: nil)
        let frame = Texture(id: TextureID(rawValue: 2), textureSize: [24, 16])
        let cancel = Action.run { node in node.removeAllActions() }
        let animation = Action.animate(with: [frame], timePerFrame: .seconds(1), restore: true)
        for action in [Action.sequence([cancel, animation]), .group([cancel, animation]), .repeatForever(cancel)] {
            var completed = false
            sprite.run(action) { completed = true }
            step(sprite, seconds: 0.25)
            #expect(sprite.texture == nil && !sprite.hasActions && !completed)
        }
    }

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
