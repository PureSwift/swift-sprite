//
//  Node.swift
//  SpriteGraph
//

import SpriteCore

/// Base element of the 2D scene tree.
///
/// Coordinates are Y-up. A node's transform is applied as translate → rotate → scale,
/// and `zPosition`, `alpha`, `speed` and `isPaused` accumulate down the hierarchy.
@MainActor
open class Node {

    // MARK: - Properties

    public var name: String?

    public var position: Vector2 = .zero

    /// Rotation in radians, counter-clockwise.
    public var zRotation: Float = 0

    public var scale: Vector2 = .one

    /// Draw order relative to the parent; accumulated down the tree.
    public var zPosition: Float = 0

    public var alpha: Float = 1

    public var isHidden = false

    /// Pauses actions on this node and its descendants.
    public var isPaused = false

    /// Multiplier applied to actions on this node and its descendants.
    public var speed: Float = 1

    public private(set) weak var parent: Node?

    public private(set) var children: [Node] = []

    var actions: [RunningAction] = []

    // MARK: - Initialization

    public init() { }

    public convenience init(name: String? = nil, @Node2DBuilder children: () -> [Node] = { [] }) {
        self.init()
        self.name = name
        for child in children() {
            addChild(child)
        }
    }

    // MARK: - Transform

    public var xScale: Float {
        get { scale.x }
        set { scale.x = newValue }
    }

    public var yScale: Float {
        get { scale.y }
        set { scale.y = newValue }
    }

    public var transform: Transform2D {
        get { Transform2D(position: position, rotation: zRotation, scale: scale) }
        set {
            position = newValue.position
            zRotation = newValue.rotation
            scale = newValue.scale
        }
    }

    /// Node-to-parent matrix.
    public var localMatrix: Matrix3x3 {
        transform.matrix
    }

    /// Node-to-root matrix.
    public var worldMatrix: Matrix3x3 {
        var matrix = localMatrix
        var ancestor = parent
        while let node = ancestor {
            matrix = node.localMatrix * matrix
            ancestor = node.parent
        }
        return matrix
    }

    /// Converts a point in this node's coordinate space to that of `node`.
    public func convert(_ point: Vector2, to node: Node) -> Vector2 {
        let world = worldMatrix.transform(point: point)
        return node.worldMatrix.inverse?.transform(point: world) ?? world
    }

    /// Converts a point in `node`'s coordinate space to this node's.
    public func convert(_ point: Vector2, from node: Node) -> Vector2 {
        node.convert(point, to: self)
    }

    // MARK: - Bounds

    /// Content bounds in this node's own coordinate space, or `nil` if it draws nothing.
    open var localBounds: Rect? {
        nil
    }

    /// Content bounds in the parent's coordinate space.
    public var frame: Rect {
        localBounds?.applying(localMatrix) ?? Rect(origin: position, size: .zero)
    }

    /// Bounds of this node and all descendants in the parent's coordinate space.
    public func calculateAccumulatedFrame() -> Rect {
        var bounds = localBounds
        for child in children {
            let childFrame = child.calculateAccumulatedFrame()
            bounds = bounds?.union(childFrame) ?? childFrame
        }
        return bounds?.applying(localMatrix) ?? Rect(origin: position, size: .zero)
    }

    /// Whether `point` (in the parent's coordinate space) lies within this node's content.
    public func contains(_ point: Vector2) -> Bool {
        guard let bounds = localBounds, let inverse = localMatrix.inverse else { return false }
        return bounds.contains(inverse.transform(point: point))
    }

    /// Visible descendants whose content contains `point` (in this node's space), topmost first.
    public func nodes(at point: Vector2) -> [Node] {
        var hits = [(node: Node, z: Float, order: Int)]()
        func visit(_ node: Node, _ point: Vector2, _ z: Float) {
            for child in node.children where !child.isHidden {
                let childZ = z + child.zPosition
                if child.contains(point) {
                    hits.append((child, childZ, hits.count))
                }
                if let inverse = child.localMatrix.inverse {
                    visit(child, inverse.transform(point: point), childZ)
                }
            }
        }
        visit(self, point, 0)
        return hits.sorted { ($0.z, $0.order) > ($1.z, $1.order) }.map(\.node)
    }

    // MARK: - Hierarchy

    /// The scene containing this node, if any.
    public var scene: Scene? {
        var node: Node? = self
        while let current = node {
            if let scene = current as? Scene { return scene }
            node = current.parent
        }
        return nil
    }

    public func addChild(_ node: Node) {
        insertChild(node, at: children.count)
    }

    public func insertChild(_ node: Node, at index: Int) {
        precondition(node !== self, "A node cannot be its own child")
        precondition(!isDescendant(of: node), "Adding an ancestor as a child would create a cycle")
        node.removeFromParent()
        node.parent = self
        children.insert(node, at: index)
    }

    /// Adds children built with ``Node2DBuilder`` and returns `self` for chaining.
    @discardableResult
    public func addChildren(@Node2DBuilder _ build: () -> [Node]) -> Self {
        for child in build() {
            addChild(child)
        }
        return self
    }

    public func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        self.parent = nil
    }

    public func removeAllChildren() {
        for child in children {
            child.parent = nil
        }
        children.removeAll()
    }

    public func isDescendant(of node: Node) -> Bool {
        var ancestor = parent
        while let current = ancestor {
            if current === node { return true }
            ancestor = current.parent
        }
        return false
    }

    /// Finds a child by name. A `//` prefix searches all descendants depth-first.
    public func childNode(withName name: String) -> Node? {
        if name.hasPrefix("//") {
            let target = String(name.dropFirst(2))
            var found: Node?
            enumerateDescendants { node, stop in
                if node.name == target {
                    found = node
                    stop = true
                }
            }
            return found
        }
        return children.first { $0.name == name }
    }

    /// Visits all descendants depth-first, parents before children.
    public func enumerateDescendants(_ body: (Node, inout Bool) -> Void) {
        var stop = false
        func visit(_ node: Node) {
            for child in node.children {
                body(child, &stop)
                if stop { return }
                visit(child)
                if stop { return }
            }
        }
        visit(self)
    }

    // MARK: - Rendering

    /// Appends this node's own geometry (not its children) to `context`.
    ///
    /// `context` carries the accumulated world transform, alpha and z position.
    open func draw(in context: inout RenderContext) { }

    func render(into context: inout RenderContext, parentTransform: Matrix3x3, parentAlpha: Float, parentZ: Float) {
        guard !isHidden else { return }
        let world = parentTransform * localMatrix
        let accumulatedAlpha = parentAlpha * alpha
        let accumulatedZ = parentZ + zPosition
        context.transform = world
        context.alpha = accumulatedAlpha
        context.zPosition = accumulatedZ
        draw(in: &context)
        for child in children {
            child.render(into: &context, parentTransform: world, parentAlpha: accumulatedAlpha, parentZ: accumulatedZ)
        }
    }
}
