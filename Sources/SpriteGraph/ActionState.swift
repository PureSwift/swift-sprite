//
//  ActionState.swift
//  SpriteGraph
//

import SpriteCore

/// Mutable running state of an ``Action`` on a specific node.
@MainActor
protocol ActionState: AnyObject {

    /// Advances by `dt` seconds.
    ///
    /// - Returns: Unused seconds once the action completes, or `nil` while still running.
    func advance(_ node: Node, by dt: Double) -> Double?

    func cancel(_ node: Node)
}

extension ActionState {
    func cancel(_ node: Node) { }
}

/// Tolerance for floating point accumulation when deciding completion.
private let epsilon = 1e-9

extension Action {

    @MainActor
    func makeState() -> any ActionState {
        let base = makeBaseState()
        guard speed != 1 || timingMode != .linear else { return base }
        return ModifiedState(base, seconds: seconds, speed: speed, timingMode: timingMode)
    }

    @MainActor
    private func makeBaseState() -> any ActionState {
        switch kind {
        case let .move(by: delta):
            return incremental { node, step in node.position += delta * step }
        case let .moveTo(x, y):
            return interpolating(from: { $0.position }) { node, start, t in
                let target = Vector2(x ?? start.x, y ?? start.y)
                node.position = start + (target - start) * t
            }
        case let .rotate(by: radians):
            return incremental { node, step in node.zRotation += radians * step }
        case let .rotateTo(target, shortestUnitArc):
            return interpolating(from: { $0.zRotation }) { node, start, t in
                var delta = target - start
                if shortestUnitArc {
                    let twoPi = 2 * Float.pi
                    delta = delta - twoPi * (delta / twoPi).rounded()
                }
                node.zRotation = start + delta * t
            }
        case let .scale(by: factor):
            return interpolating(from: { $0.scale }) { node, start, t in
                node.scale = start + (start * factor - start) * t
            }
        case let .scaleTo(x, y):
            return interpolating(from: { $0.scale }) { node, start, t in
                if let x { node.scale.x = start.x + (x - start.x) * t }
                if let y { node.scale.y = start.y + (y - start.y) * t }
            }
        case let .fade(by: delta):
            return incremental { node, step in node.alpha += delta * step }
        case let .fadeTo(target):
            return interpolating(from: { $0.alpha }) { node, start, t in
                node.alpha = start + (target - start) * t
            }
        case let .resize(width, height):
            return interpolating(from: { ($0 as? Sprite)?.size ?? .zero }) { node, start, t in
                guard let sprite = node as? Sprite else { return }
                if let width { sprite.size.x = start.x + (width - start.x) * t }
                if let height { sprite.size.y = start.y + (height - start.y) * t }
            }
        case let .resizeBy(delta):
            return incremental { node, step in
                guard let sprite = node as? Sprite else { return }
                sprite.size += delta * step
            }
        case let .colorize(color, blendFactor):
            return interpolating(from: { node -> (Color, Float) in
                switch node {
                case let sprite as Sprite: (sprite.color, sprite.colorBlendFactor)
                case let label as Label: (label.color, 1)
                default: (.white, 0)
                }
            }) { node, start, t in
                let targetColor = color ?? start.0
                let mixed = start.0.mix(with: targetColor, fraction: t)
                switch node {
                case let sprite as Sprite:
                    sprite.color = mixed
                    sprite.colorBlendFactor = start.1 + (blendFactor - start.1) * t
                case let label as Label:
                    label.color = mixed
                default:
                    break
                }
            }
        case let .animate(textures, resize, restore):
            return TextureAnimationState(textures: textures, seconds: seconds, resize: resize, restore: restore)
        case let .setTexture(texture, resize):
            return instant { node in
                guard let sprite = node as? Sprite else { return }
                sprite.texture = texture
                if resize { sprite.size = texture.size }
            }
        case let .hide(hidden):
            return instant { $0.isHidden = hidden }
        case .wait:
            return IntervalState(seconds: seconds) { _ in { _, _ in } }
        case let .run(block):
            return instant(block)
        case let .custom(block):
            let seconds = seconds
            return IntervalState(seconds: seconds) { _ in
                { node, t in block(node, .seconds(seconds * t)) }
            }
        case .removeFromParent:
            return instant { $0.removeFromParent() }
        case let .sequence(actions):
            return SequenceState(actions)
        case let .group(actions):
            return GroupState(actions)
        case let .repeat(action, count):
            return RepeatState(action, count: count)
        }
    }

    /// State applying `step` (the change in progress since the last frame) each frame.
    @MainActor
    private func incremental(_ apply: @escaping (Node, Float) -> Void) -> any ActionState {
        IntervalState(seconds: seconds) { _ in
            var last: Float = 0
            return { node, t in
                let progress = Float(t)
                apply(node, progress - last)
                last = progress
            }
        }
    }

    /// State capturing a starting value when first run, then interpolating from it.
    @MainActor
    private func interpolating<Value>(
        from start: @escaping (Node) -> Value,
        _ apply: @escaping (Node, Value, Float) -> Void
    ) -> any ActionState {
        IntervalState(seconds: seconds) { node in
            let initial = start(node)
            return { node, t in apply(node, initial, Float(t)) }
        }
    }

    @MainActor
    private func instant(_ apply: @escaping @MainActor (Node) -> Void) -> any ActionState {
        IntervalState(seconds: 0) { _ in { node, _ in apply(node) } }
    }
}

// MARK: - States

/// Captures the original texture only when playback actually starts.
@MainActor
final class TextureAnimationState: ActionState {
    private let textures: [Texture]
    private let seconds: Double
    private let resize: Bool
    private let restore: Bool
    private var original: Texture?
    private var started = false
    private var finished = false
    private var elapsed: Double = 0

    init(textures: [Texture], seconds: Double, resize: Bool, restore: Bool) {
        self.textures = textures
        self.seconds = seconds
        self.resize = resize
        self.restore = restore
    }

    private func apply(_ texture: Texture?, to sprite: Sprite) {
        sprite.texture = texture
        if resize, let texture { sprite.size = texture.size }
    }

    func advance(_ node: Node, by dt: Double) -> Double? {
        guard !finished else { return dt }
        elapsed += dt
        let complete = elapsed >= seconds - epsilon
        if let sprite = node as? Sprite, !textures.isEmpty {
            if !started { original = sprite.texture; started = true }
            let progress = seconds > 0 ? min(elapsed / seconds, 1) : 1
            let frame = min(Int(progress * Double(textures.count)), textures.count - 1)
            apply(complete && restore ? original : textures[frame], to: sprite)
        }
        finished = complete
        return complete ? max(elapsed - seconds, 0) : nil
    }

    func cancel(_ node: Node) {
        guard !finished else { return }
        finished = true
        if started, restore, let sprite = node as? Sprite { apply(original, to: sprite) }
    }
}

/// Leaf action interpolating progress `0...1` over a fixed duration.
@MainActor
final class IntervalState: ActionState {

    typealias Update = (Node, Double) -> Void

    let seconds: Double
    private let start: (Node) -> Update
    private var update: Update?
    private var elapsed: Double = 0

    init(seconds: Double, start: @escaping (Node) -> Update) {
        self.seconds = seconds
        self.start = start
    }

    func advance(_ node: Node, by dt: Double) -> Double? {
        let update = self.update ?? start(node)
        self.update = update
        elapsed += dt
        let t = seconds > 0 ? min(elapsed / seconds, 1) : 1
        update(node, t)
        return elapsed >= seconds - epsilon ? max(elapsed - seconds, 0) : nil
    }
}

/// Runs actions one after another, carrying leftover time into the next.
@MainActor
final class SequenceState: ActionState {

    private let actions: [Action]
    private var index = 0
    private var current: (any ActionState)?

    init(_ actions: [Action]) {
        self.actions = actions
    }

    private var cancelled = false

    func cancel(_ node: Node) {
        cancelled = true
        current?.cancel(node)
    }

    func advance(_ node: Node, by dt: Double) -> Double? {
        guard !cancelled else { return nil }
        var remaining = dt
        while !cancelled, index < actions.count {
            let state = current ?? actions[index].makeState()
            current = state
            guard let leftover = state.advance(node, by: remaining) else { return nil }
            remaining = leftover
            index += 1
            current = nil
        }
        return remaining
    }
}

/// Runs actions simultaneously; completes when all have completed.
@MainActor
final class GroupState: ActionState {

    private var states: [any ActionState]
    private var finished: [Bool]

    init(_ actions: [Action]) {
        self.states = actions.map { $0.makeState() }
        self.finished = Array(repeating: false, count: actions.count)
    }

    private var cancelled = false

    func cancel(_ node: Node) {
        cancelled = true
        for index in states.indices where !finished[index] { states[index].cancel(node) }
    }

    func advance(_ node: Node, by dt: Double) -> Double? {
        guard !cancelled else { return nil }
        var leftover = dt
        for index in states.indices where !finished[index] {
            guard !cancelled else { return nil }
            if let remaining = states[index].advance(node, by: dt) {
                finished[index] = true
                leftover = min(leftover, remaining)
            }
        }
        return finished.allSatisfy { $0 } ? leftover : nil
    }
}

/// Repeats an action a fixed number of times, or forever when `count` is `nil`.
@MainActor
final class RepeatState: ActionState {

    private let action: Action
    private let count: Int?
    private var iteration = 0
    private var current: (any ActionState)?

    init(_ action: Action, count: Int?) {
        self.action = action
        self.count = count
    }

    private var cancelled = false

    func cancel(_ node: Node) {
        cancelled = true
        current?.cancel(node)
    }

    func advance(_ node: Node, by dt: Double) -> Double? {
        guard !cancelled else { return nil }
        var remaining = dt
        while !cancelled, count.map({ iteration < $0 }) ?? true {
            let state = current ?? action.makeState()
            current = state
            guard let leftover = state.advance(node, by: remaining) else { return nil }
            iteration += 1
            current = nil
            remaining = leftover
            // An instantaneous action repeated forever runs once per frame.
            if count == nil, action.scaledSeconds <= epsilon { return nil }
        }
        return remaining
    }
}

/// Applies an action's speed and timing mode by remapping time passed to its base state.
@MainActor
final class ModifiedState: ActionState {

    private let base: any ActionState
    private let seconds: Double
    private let speed: Double
    private let timingMode: Action.TimingMode
    private var elapsed: Double = 0
    private var warped: Double = 0

    init(_ base: any ActionState, seconds: Double, speed: Double, timingMode: Action.TimingMode) {
        self.base = base
        self.seconds = seconds
        self.speed = speed
        self.timingMode = timingMode
    }

    func cancel(_ node: Node) { base.cancel(node) }

    func advance(_ node: Node, by dt: Double) -> Double? {
        guard speed > 0 else { return nil }
        // Timing curves only apply to finite, non-zero durations.
        guard seconds.isFinite, seconds > 0, timingMode != .linear else {
            return base.advance(node, by: dt * speed).map { $0 / speed }
        }
        let wallDuration = seconds / speed
        elapsed += dt
        let t = min(elapsed / wallDuration, 1)
        let target = timingMode.apply(t) * seconds
        let step = target - warped
        warped = target
        let result = base.advance(node, by: t >= 1 ? step + epsilon : step)
        if t >= 1 {
            return elapsed - wallDuration
        }
        return result.map { _ in 0 }
    }
}
