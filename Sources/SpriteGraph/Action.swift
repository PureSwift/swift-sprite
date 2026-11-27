//
//  Action.swift
//  SpriteGraph
//

import SpriteCore

/// Value-type description of an animation or behavior run by a ``Node``.
///
/// Actions are immutable and reusable; each ``Node/run(_:withKey:completion:)``
/// creates independent running state.
///
/// ```swift
/// let pulse = Action.sequence([
///     .scale(to: 1.2, duration: .milliseconds(150)),
///     .scale(to: 1.0, duration: .milliseconds(150)),
/// ]).timingMode(.easeInEaseOut)
/// node.run(.repeatForever(pulse))
/// ```
public struct Action: Sendable {

    /// Easing applied to an action's progress.
    public enum TimingMode: Hashable, Sendable {
        case linear
        case easeIn
        case easeOut
        case easeInEaseOut

        /// Maps linear progress `t` in `0...1` to eased progress.
        public func apply(_ t: Double) -> Double {
            switch self {
            case .linear: t
            case .easeIn: t * t
            case .easeOut: t * (2 - t)
            case .easeInEaseOut: t * t * (3 - 2 * t)
            }
        }
    }

    /// Callback invoked on the main actor with the node running the action.
    public typealias Block = @MainActor @Sendable (Node) -> Void

    /// Callback invoked with the node and elapsed time of a custom action.
    public typealias CustomBlock = @MainActor @Sendable (Node, Duration) -> Void

    indirect enum Kind: Sendable {
        case move(by: Vector2)
        case moveTo(x: Float?, y: Float?)
        case rotate(by: Float)
        case rotateTo(Float, shortestUnitArc: Bool)
        case scale(by: Vector2)
        case scaleTo(x: Float?, y: Float?)
        case scaleToSize(Vector2)
        case fade(by: Float)
        case fadeTo(Float)
        case changeSpeed(Float, relative: Bool)
        case resize(width: Float?, height: Float?)
        case resizeBy(Vector2)
        case colorize(Color?, blendFactor: Float)
        case animate([Texture], resize: Bool, restore: Bool)
        case setTexture(Texture, resize: Bool)
        case hide(Bool)
        case wait
        case run(Block)
        case custom(CustomBlock)
        case removeFromParent
        case sequence([Action])
        case group([Action])
        case `repeat`(Action, count: Int?)
    }

    let kind: Kind

    /// Duration in seconds; `.infinity` for ``repeatForever(_:)``.
    let seconds: Double

    public private(set) var timingMode: TimingMode = .linear

    public private(set) var speed: Double = 1

    init(_ kind: Kind, seconds: Double) {
        self.kind = kind
        self.seconds = max(seconds, 0)
    }

    init(_ kind: Kind, duration: Duration) {
        self.init(kind, seconds: duration.seconds)
    }

    /// Total duration at normal speed; `nil` if the action repeats forever.
    public var duration: Duration? {
        guard seconds.isFinite else { return nil }
        return .seconds(seconds / speed)
    }

    /// Effective duration in seconds including ``speed``.
    var scaledSeconds: Double {
        speed > 0 ? seconds / speed : .infinity
    }
}

// MARK: - Modifiers

public extension Action {

    /// Returns a copy with the given easing applied over its whole duration.
    func timingMode(_ mode: TimingMode) -> Action {
        var copy = self
        copy.timingMode = mode
        return copy
    }

    /// Returns a copy that runs `speed` times faster.
    func speed(_ speed: Double) -> Action {
        var copy = self
        copy.speed = max(speed, 0)
        return copy
    }
}

// MARK: - Transform

public extension Action {

    static func move(by delta: Vector2, duration: Duration) -> Action {
        Action(.move(by: delta), duration: duration)
    }

    static func move(to point: Vector2, duration: Duration) -> Action {
        Action(.moveTo(x: point.x, y: point.y), duration: duration)
    }

    static func moveTo(x: Float, duration: Duration) -> Action {
        Action(.moveTo(x: x, y: nil), duration: duration)
    }

    static func moveTo(y: Float, duration: Duration) -> Action {
        Action(.moveTo(x: nil, y: y), duration: duration)
    }

    static func rotate(by radians: Float, duration: Duration) -> Action {
        Action(.rotate(by: radians), duration: duration)
    }

    static func rotate(to radians: Float, duration: Duration, shortestUnitArc: Bool = false) -> Action {
        Action(.rotateTo(radians, shortestUnitArc: shortestUnitArc), duration: duration)
    }

    /// Multiplies the node's scale by `factor` over the duration.
    static func scale(by factor: Float, duration: Duration) -> Action {
        Action(.scale(by: Vector2(repeating: factor)), duration: duration)
    }

    static func scale(by factor: Vector2, duration: Duration) -> Action {
        Action(.scale(by: factor), duration: duration)
    }

    static func scale(to value: Float, duration: Duration) -> Action {
        Action(.scaleTo(x: value, y: value), duration: duration)
    }

    static func scale(to value: Vector2, duration: Duration) -> Action {
        Action(.scaleTo(x: value.x, y: value.y), duration: duration)
    }

    /// Animates only the horizontal scale, leaving vertical scale untouched.
    static func scaleTo(x: Float, duration: Duration) -> Action {
        Action(.scaleTo(x: x, y: nil), duration: duration)
    }

    /// Animates only the vertical scale, leaving horizontal scale untouched.
    static func scaleTo(y: Float, duration: Duration) -> Action {
        Action(.scaleTo(x: nil, y: y), duration: duration)
    }
}

// MARK: - Appearance

public extension Action {

    static func fadeIn(duration: Duration) -> Action {
        fadeAlpha(to: 1, duration: duration)
    }

    static func fadeOut(duration: Duration) -> Action {
        fadeAlpha(to: 0, duration: duration)
    }

    static func fadeAlpha(by delta: Float, duration: Duration) -> Action {
        Action(.fade(by: delta), duration: duration)
    }

    static func fadeAlpha(to alpha: Float, duration: Duration) -> Action {
        Action(.fadeTo(alpha), duration: duration)
    }

    static var hide: Action {
        Action(.hide(true), seconds: 0)
    }

    static var unhide: Action {
        Action(.hide(false), seconds: 0)
    }

    /// Animates a sprite's scale to achieve a display size, using its base size
    /// when playback starts. Zero-sized dimensions retain their scale.
    /// Has no effect on other node types.
    static func scale(toSize size: Vector2, duration: Duration) -> Action {
        Action(.scaleToSize(size), duration: duration)
    }

    /// Changes a sprite's size by an additive amount.
    static func resize(by delta: Vector2, duration: Duration) -> Action {
        Action(.resizeBy(delta), duration: duration)
    }

    /// Animates only a sprite's width.
    static func resizeTo(width: Float, duration: Duration) -> Action {
        Action(.resize(width: width, height: nil), duration: duration)
    }

    /// Animates only a sprite's height.
    static func resizeTo(height: Float, duration: Duration) -> Action {
        Action(.resize(width: nil, height: height), duration: duration)
    }

    /// Animates a ``Sprite``'s size.
    static func resize(to size: Vector2, duration: Duration) -> Action {
        Action(.resize(width: size.x, height: size.y), duration: duration)
    }

    /// Animates a ``Sprite``'s (or ``Label``'s) color and blend factor.
    static func colorize(with color: Color, blendFactor: Float = 1, duration: Duration) -> Action {
        Action(.colorize(color, blendFactor: blendFactor), duration: duration)
    }

    /// Animates a ``Sprite``'s blend factor only.
    static func colorize(withBlendFactor blendFactor: Float, duration: Duration) -> Action {
        Action(.colorize(nil, blendFactor: blendFactor), duration: duration)
    }

    /// Flipbook animation of a ``Sprite``'s texture.
    static func animate(
        with textures: [Texture],
        timePerFrame: Duration,
        resize: Bool = false,
        restore: Bool = false
    ) -> Action {
        Action(.animate(textures, resize: resize, restore: restore),
               seconds: timePerFrame.seconds * Double(textures.count))
    }

    static func setTexture(_ texture: Texture, resize: Bool = false) -> Action {
        Action(.setTexture(texture, resize: resize), seconds: 0)
    }
}

// MARK: - Control

public extension Action {

    /// Animates the node's playback speed to a nonnegative target.
    /// The node's current speed also controls this action's progress.
    static func changeSpeed(to value: Float, duration: Duration) -> Action {
        Action(.changeSpeed(max(value, 0), relative: false), duration: duration)
    }

    /// Multiplies the node's speed at playback start by a nonnegative factor.
    static func changeSpeed(by factor: Float, duration: Duration) -> Action {
        Action(.changeSpeed(max(factor, 0), relative: true), duration: duration)
    }

    static func wait(for duration: Duration) -> Action {
        Action(.wait, duration: duration)
    }

    /// Waits a random duration in `duration ± range / 2`.
    static func wait(for duration: Duration, withRange range: Duration) -> Action {
        let jitter = Double.random(in: -0.5 ... 0.5) * range.seconds
        return Action(.wait, seconds: duration.seconds + jitter)
    }

    /// Starts an independent action on the first match for a child path.
    /// A leading slash starts at the tree root. Other paths start at the receiving node.
    /// Components are exact names, `.` (current node), or `..` (parent).
    /// A `//` prefix searches from the root; `.//` searches this node's descendants.
    /// Within a path, `//` searches descendants of the preceding matches.
    /// `*` matches zero or more characters in a name, including unnamed nodes for `*`. Bracket sets and ranges match one character.
    /// Lookup happens at playback time. A missing child is a no-op.
    /// This action completes immediately without waiting for the child's action.
    static func run(_ action: Action, onChildWithName name: String) -> Action {
        let fromRoot = name.hasPrefix("/")
        let path = fromRoot ? String(name.dropFirst()) : name
        let components = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        return .run { node in
            guard components.indices.allSatisfy({ index in
                !components[index].isEmpty || (index + 1 < components.count
                    && !components[index + 1].isEmpty
                    && components[index + 1] != "." && components[index + 1] != "..")
            }) else { return }
            var start = node
            if fromRoot {
                while let parent = start.parent { start = parent }
            }
            var candidates = [start]
            var recursive = false
            for component in components {
                if component.isEmpty {
                    recursive = true
                    continue
                }
                guard let pattern = NodeNamePattern(component) else { return }
                if recursive {
                    var matches: [Node] = []
                    var seen = Set<ObjectIdentifier>()
                    for candidate in candidates {
                        candidate.enumerateDescendants { descendant, _ in
                            if pattern.matches(descendant.name), seen.insert(ObjectIdentifier(descendant)).inserted {
                                matches.append(descendant)
                            }
                        }
                    }
                    candidates = matches
                    recursive = false
                    if candidates.isEmpty { return }
                    continue
                }
                if component == "." { continue }
                if component == ".." {
                    var seen = Set<ObjectIdentifier>()
                    candidates = candidates.compactMap(\.parent).filter { seen.insert(ObjectIdentifier($0)).inserted }
                } else {
                    candidates = candidates.flatMap { parent in
                        parent.children.filter { pattern.matches($0.name) }
                    }
                }
                if candidates.isEmpty { return }
            }
            candidates.first?.run(action)
        }
    }

    static func run(_ block: @escaping Block) -> Action {
        Action(.run(block), seconds: 0)
    }

    static func customAction(duration: Duration, _ block: @escaping CustomBlock) -> Action {
        Action(.custom(block), duration: duration)
    }

    static func removeFromParent() -> Action {
        Action(.removeFromParent, seconds: 0)
    }

    static func sequence(_ actions: [Action]) -> Action {
        Action(.sequence(actions), seconds: actions.reduce(0) { $0 + $1.scaledSeconds })
    }

    static func group(_ actions: [Action]) -> Action {
        Action(.group(actions), seconds: actions.map(\.scaledSeconds).max() ?? 0)
    }

    static func `repeat`(_ action: Action, count: Int) -> Action {
        Action(.repeat(action, count: max(count, 0)), seconds: action.scaledSeconds * Double(max(count, 0)))
    }

    static func repeatForever(_ action: Action) -> Action {
        Action(.repeat(action, count: nil), seconds: .infinity)
    }
}
