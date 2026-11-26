//
//  Scene+Physics.swift
//  SpriteGraph
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import SpriteCore
import SpritePhysics

public extension PhysicsBody {

    /// The node this body is attached to, if any.
    @MainActor
    var node: Node? {
        owner as? Node
    }
}

extension Scene {

    /// Synchronizes node and body transforms around a physics step.
    ///
    /// Bodies are simulated in scene coordinates. A node moved directly since the last
    /// step teleports its body; afterwards dynamic bodies write back to their nodes.
    func simulatePhysics(seconds: Double) {
        var nodes = [Node]()
        if physicsBody != nil {
            nodes.append(self)
        }
        enumerateDescendants { node, _ in
            if node.physicsBody != nil {
                nodes.append(node)
            }
        }

        let sceneInverse = worldMatrix.inverse ?? .identity
        for node in nodes {
            guard let body = node.physicsBody else { continue }
            let (position, rotation) = Self.decompose(sceneInverse * node.worldMatrix)
            if let synced = node.physicsSyncedTransform,
               length(synced.position - position) < 1e-3,
               abs(synced.rotation - rotation) < 1e-5 {
                continue
            }
            body.position = position
            body.rotation = rotation
            node.physicsSyncedTransform = (position, rotation)
        }

        physicsWorld.bodies = nodes.compactMap(\.physicsBody)
        physicsWorld.simulate(elapsed: seconds)

        for node in nodes where node !== self {
            guard let body = node.physicsBody, body.isDynamic, let parent = node.parent else { continue }
            let parentInScene = sceneInverse * parent.worldMatrix
            let (_, parentRotation) = Self.decompose(parentInScene)
            if let inverse = parentInScene.inverse {
                node.position = inverse.transform(point: body.position)
            }
            node.zRotation = body.rotation - parentRotation
            let (position, rotation) = Self.decompose(sceneInverse * node.worldMatrix)
            node.physicsSyncedTransform = (position, rotation)
        }
    }

    /// Translation and rotation of an affine matrix.
    static func decompose(_ matrix: Matrix3x3) -> (position: Vector2, rotation: Float) {
        (matrix.translation, atan2f(matrix.columns.0.y, matrix.columns.0.x))
    }

    private func length(_ v: Vector2) -> Float {
        (v * v).sum().squareRoot()
    }
}
