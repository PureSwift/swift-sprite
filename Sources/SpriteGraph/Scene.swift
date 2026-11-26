//
//  Scene.swift
//  SpriteGraph
//

import SpriteCore
import SpritePhysics

/// Root node of a scene tree that advances actions and produces frames for a viewport.
open class Scene: Node {

    /// How the scene's ``size`` is mapped onto the viewport.
    public enum ScaleMode: Hashable, Sendable {
        /// Stretches each axis independently to fill the viewport.
        case fill
        /// Uniformly scales to fill the viewport, cropping overflow.
        case aspectFill
        /// Uniformly scales to fit inside the viewport, letterboxing the rest.
        case aspectFit
        /// Resizes the scene to match the viewport at 1:1 scale.
        case resizeFill
    }

    /// Size of the scene's coordinate space.
    public var size: Vector2 {
        didSet {
            if size != oldValue { didChangeSize(oldValue) }
        }
    }

    public var scaleMode: ScaleMode = .aspectFill

    public var backgroundColor = Color(red: 0.15, green: 0.15, blue: 0.15)

    /// Point of the viewport, in unit coordinates, where the scene origin is placed.
    /// Ignored when a ``camera`` is set.
    public var anchorPoint: Vector2 = .zero

    /// Camera defining the visible region; typically also a child of the scene.
    public var camera: Camera?

    /// Sorts siblings with equal z by texture for fewer draw calls.
    public var ignoresSiblingOrder = false

    /// Viewport size in pixels used for the most recent frame.
    public private(set) var viewportSize: Vector2 = .zero

    private var context = RenderContext()

    /// Physics simulation for bodies attached to nodes in this scene.
    public let physicsWorld = PhysicsWorld()

    public init(size: Vector2) {
        self.size = size
        super.init()
    }

    // MARK: - Overridable hooks

    /// Called once per frame before actions are evaluated.
    open func update(_ deltaTime: Duration) { }

    /// Called after actions are evaluated each frame.
    open func didEvaluateActions() { }

    /// Called after physics is simulated each frame.
    open func didSimulatePhysics() { }

    /// Called at the end of each ``advance(by:)``.
    open func didFinishUpdate() { }

    /// Called when ``size`` changes.
    open func didChangeSize(_ oldSize: Vector2) { }

    // MARK: - Update loop

    /// Advances the scene by one frame: `update`, actions, physics, then `didFinishUpdate`.
    public func advance(by deltaTime: Duration) {
        guard !isPaused else { return }
        update(deltaTime)
        let seconds = max(deltaTime.seconds, 0)
        evaluateActions(seconds: seconds)
        didEvaluateActions()
        simulatePhysics(seconds: seconds)
        didSimulatePhysics()
        didFinishUpdate()
    }

    // MARK: - Rendering

    /// Scene-to-pixel transform for a viewport (Y-down, origin at top-left).
    public func viewTransform(viewportSize viewport: Vector2) -> Matrix3x3 {
        guard size.x > 0, size.y > 0, viewport.x > 0, viewport.y > 0 else {
            return .viewport(size: viewport)
        }
        let ratio = viewport / size
        let scale: Vector2
        switch scaleMode {
        case .fill: scale = ratio
        case .aspectFill: scale = Vector2(repeating: max(ratio.x, ratio.y))
        case .aspectFit: scale = Vector2(repeating: min(ratio.x, ratio.y))
        case .resizeFill: scale = .one
        }
        let offset = (viewport - size * scale) * 0.5
        let sceneToRect: Matrix3x3
        if let camera, let inverse = camera.worldMatrix.inverse {
            sceneToRect = .translation(size * 0.5) * inverse
        } else {
            sceneToRect = .translation(anchorPoint * size)
        }
        return .viewport(size: viewport) * .translation(offset) * .scale(scale) * sceneToRect
    }

    /// Converts a viewport point in pixels (Y-down) to scene coordinates.
    public func convertPoint(fromView point: Vector2) -> Vector2 {
        viewTransform(viewportSize: viewportSize).inverse?.transform(point: point) ?? point
    }

    /// Converts a scene point to viewport pixels (Y-down).
    public func convertPoint(toView point: Vector2) -> Vector2 {
        viewTransform(viewportSize: viewportSize).transform(point: point)
    }

    /// Builds the frame geometry for the given viewport size in pixels.
    public func makeFrame(viewportSize viewport: Vector2) -> SpriteFrame {
        viewportSize = viewport
        if scaleMode == .resizeFill, size != viewport {
            size = viewport
        }
        context.batcher.sortMode = ignoresSiblingOrder ? .textureGrouped : .preserveOrder
        let view = viewTransform(viewportSize: viewport)
        // The scene's own transform is the root; children are drawn relative to it.
        render(into: &context, parentTransform: .identity, parentAlpha: 1, parentZ: 0)
        return context.batcher.makeFrame(viewTransform: view)
    }

    /// Advances the scene, then renders and presents it through `backend`.
    public func present(on backend: some SpriteRenderBackend, deltaTime: Duration) throws {
        advance(by: deltaTime)
        try backend.render(makeFrame(viewportSize: backend.drawableSize), clearColor: backgroundColor)
    }
}

extension Duration {

    /// Duration in seconds as a floating point value.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) * 1e-18
    }
}
