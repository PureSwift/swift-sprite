//
//  NodeTests.swift
//  SpriteGraphTests
//

import Testing
import SpriteCore
@testable import SpriteGraph

func approx(_ a: Vector2, _ b: Vector2, tolerance: Float = 1e-4) -> Bool {
    abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
}

func approx(_ a: Float, _ b: Float, tolerance: Float = 1e-4) -> Bool {
    abs(a - b) < tolerance
}

@MainActor @Suite struct NodeTests {

    @Test func hierarchy() {
        let root = Node(name: "root")
        let a = Node(name: "a")
        let b = Node(name: "b")
        root.addChild(a)
        a.addChild(b)
        #expect(b.parent === a)
        #expect(b.isDescendant(of: root))
        #expect(root.childNode(withName: "a") === a)
        #expect(root.childNode(withName: "b") == nil)
        #expect(root.childNode(withName: "//b") === b)

        // Re-parenting removes the node from its old parent.
        root.addChild(b)
        #expect(a.children.isEmpty)
        #expect(root.children.map(\.name) == ["a", "b"])

        b.removeFromParent()
        #expect(b.parent == nil)
        root.removeAllChildren()
        #expect(a.parent == nil && root.children.isEmpty)
    }

    @Test func builderComposesChildren() {
        let includeOptional = false
        let root = Node(name: "root") {
            Node(name: "first")
            if includeOptional {
                Node(name: "optional")
            }
            for i in 0 ..< 3 {
                Node(name: "item\(i)")
            }
        }
        #expect(root.children.map(\.name) == ["first", "item0", "item1", "item2"])
        let sprite = Sprite(color: .red, size: [4, 4]).addChildren {
            Node(name: "child")
        }
        #expect(sprite.children.first?.parent === sprite)
    }

    @Test func worldTransformAndConversion() {
        let root = Node()
        let parent = Node()
        parent.position = [100, 0]
        parent.zRotation = .pi / 2
        parent.scale = [2, 2]
        let child = Node()
        child.position = [10, 0]
        root.addChild(parent)
        parent.addChild(child)

        // (10, 0) scaled ×2 → (20, 0), rotated 90° → (0, 20), translated → (100, 20).
        #expect(approx(child.worldMatrix.translation, [100, 20]))
        #expect(approx(child.convert(.zero, to: root), [100, 20]))
        #expect(approx(root.convert([100, 20], to: child), .zero))
        #expect(approx(child.convert([100, 20], from: root), .zero))
    }

    @Test func framesAndHitTesting() {
        let root = Node()
        let back = Sprite(color: .red, size: [100, 100])
        back.position = [50, 50]
        let front = Sprite(color: .blue, size: [20, 20])
        front.position = [50, 50]
        front.zPosition = 1
        let hidden = Sprite(color: .green, size: [100, 100])
        hidden.isHidden = true
        root.addChildren {
            back
            front
            hidden
        }
        #expect(back.frame == Rect(x: 0, y: 0, width: 100, height: 100))
        let hits = root.nodes(at: [50, 50])
        #expect(hits.count == 2 && hits[0] === front && hits[1] === back)
        #expect(root.nodes(at: [10, 10]).count == 1)
        #expect(root.nodes(at: [200, 200]).isEmpty)

        let child = Sprite(color: .white, size: [10, 10])
        child.position = [100, 0]
        back.addChild(child)
        #expect(back.calculateAccumulatedFrame() == Rect(x: 0, y: 0, width: 155, height: 100))
    }

    @Test func renderAccumulatesAlphaAndZ() {
        let scene = Scene(size: [100, 100])
        let parent = Sprite(color: .red, size: [10, 10])
        parent.alpha = 0.5
        parent.zPosition = 2
        let child = Sprite(color: .blue, size: [10, 10])
        child.alpha = 0.5
        child.zPosition = -1
        parent.addChild(child)
        scene.addChild(parent)

        let frame = scene.makeFrame(viewportSize: [100, 100])
        #expect(frame.vertices.count == 8)
        // Child z (2 - 1 = 1) sorts before parent z (2).
        #expect(frame.vertices[0].color == Color(red: 0, green: 0, blue: 1, alpha: 0.25))
        #expect(frame.vertices[4].color == Color(red: 1, green: 0, blue: 0, alpha: 0.5))
    }

    @Test func hiddenNodesAreSkipped() {
        let scene = Scene(size: [10, 10])
        let parent = Sprite(color: .red, size: [1, 1])
        parent.isHidden = true
        parent.addChild(Sprite(color: .blue, size: [1, 1]))
        scene.addChild(parent)
        #expect(scene.makeFrame(viewportSize: [10, 10]).vertices.isEmpty)
    }
}
