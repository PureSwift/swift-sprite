import Foundation
import SpriteCore
import SpriteGraph

/// Named action descriptions from SpriteKit editor `Actions.sks` libraries.
public struct SpriteKitActionArchive: Sendable {
    private let actions: [String: ArchiveAction]

    public var actionNames: [String] { actions.keys.sorted() }

    public static func decode(_ data: Data) throws -> SpriteKitActionArchive {
        let graph = try KeyedArchive(ArchivePropertyList.decode(data))
        func dictionary(_ value: PropertyValue) throws -> [String: PropertyValue] {
            let fields = try graph.dictionary(value)
            guard ["NSDictionary", "NSMutableDictionary"].contains(try graph.className(fields)) else {
                throw SceneArchiveError.invalid("Expected action library dictionary")
            }
            let keys = try graph.array(fields["NS.keys"])
            let values = try graph.array(fields["NS.objects"])
            guard keys.count == values.count, keys.count <= 10_000 else {
                throw SceneArchiveError.invalid("Invalid action library entry count")
            }
            var result: [String: PropertyValue] = [:]
            for (key, value) in zip(keys, values) {
                guard let name = try graph.string(key), !name.isEmpty, result[name] == nil else {
                    throw SceneArchiveError.invalid("Duplicate or invalid action library name")
                }
                result[name] = value
            }
            return result
        }
        let root = try dictionary(.uid(graph.rootID))
        guard let entries = root["actions"] else { throw SceneArchiveError.invalid("Missing action library entries") }
        var decoder = ArchiveActionDecoder(graph: graph)
        var actions: [String: ArchiveAction] = [:]
        for (name, value) in try dictionary(entries) {
            actions[name] = try decoder.decode(value)
        }
        return SpriteKitActionArchive(actions: actions)
    }

    public static func decode(at url: URL) async throws -> SpriteKitActionArchive {
        try await Task.detached { try decode(Data(contentsOf: url)) }.value
    }

    /// Materializes an action with backend-owned textures and host sound callbacks.
    /// Returns nil for an unknown name. Sound callbacks run at playback time, not resolution.
    /// Resolution is cached within this call. Playback state is created when a node runs it.
    @MainActor public func makeAction(named name: String,
        textureResolver: (SpriteKitSceneArchive.TextureReference) throws -> Texture? = { _ in nil },
        soundResolver: (String) throws -> Action.Block? = { _ in nil }
    ) throws -> Action? {
        guard let action = actions[name] else { return nil }
        var textures: [SpriteKitSceneArchive.TextureReference: Texture] = [:]
        var sounds: [String: Action.Block] = [:]
        return try action.makeAction(texture: { frame in
            if textures[frame.reference] == nil {
                guard let texture = try textureResolver(frame.reference) else {
                    throw SceneArchiveError.missingTexture(frame.reference.imageName)
                }
                textures[frame.reference] = texture
            }
            guard let texture = textures[frame.reference] else {
                throw SceneArchiveError.missingTexture(frame.reference.imageName)
            }
            return texture.subtexture(inUnitRect: frame.rect)
        }, sound: { name in
            if let playback = sounds[name] { return playback }
            guard let playback = try soundResolver(name) else { throw SceneArchiveError.missingSound(name) }
            sounds[name] = playback
            return playback
        })
    }
}

struct ArchiveNodeAction: Sendable {
    let action: ArchiveAction
    let key: String?
}

/// Keeps texture references unresolved until a scene's backend resources are available.
indirect enum ArchiveAction: Sendable {
    case ready(Action)
    case animation([ArchiveTexture], Duration, resize: Bool, restore: Bool)
    case sound(String, Duration)
    case sequence([ArchiveAction])
    case group([ArchiveAction])
    case repeated(ArchiveAction, count: Int?)
    case timed(ArchiveAction, Action.TimingMode)

    @MainActor func makeAction(texture: (ArchiveTexture) throws -> Texture,
        sound: (String) throws -> Action.Block) throws -> Action {
        switch self {
        case let .ready(action): return action
        case let .sound(name, duration):
            return .sequence([.run(try sound(name)), .wait(for: duration)])
        case let .animation(frames, time, resize, restore):
            return .animate(with: try frames.map(texture), timePerFrame: time, resize: resize, restore: restore)
        case let .sequence(children): return .sequence(try children.map { try $0.makeAction(texture: texture, sound: sound) })
        case let .group(children): return .group(try children.map { try $0.makeAction(texture: texture, sound: sound) })
        case let .repeated(child, count):
            let action = try child.makeAction(texture: texture, sound: sound)
            return count.map { .repeat(action, count: $0) } ?? .repeatForever(action)
        case let .timed(child, mode): return try child.makeAction(texture: texture, sound: sound).timingMode(mode)
        }
    }

    /// Texture-free actions used only to validate composite durations during decoding.
    var timingAction: Action {
        switch self {
        case let .ready(action): return action
        case let .sound(_, duration): return .wait(for: duration)
        case let .animation(frames, time, _, _): return .wait(for: time * frames.count)
        case let .sequence(children): return .sequence(children.map(\.timingAction))
        case let .group(children): return .group(children.map(\.timingAction))
        case let .repeated(child, count):
            return count.map { .repeat(child.timingAction, count: $0) } ?? .repeatForever(child.timingAction)
        case let .timed(child, mode): return child.timingAction.timingMode(mode)
        }
    }
}

/// Decodes action descriptions, never archived executable blocks or runtime objects.
struct ArchiveActionDecoder {
    let graph: KeyedArchive
    private var active = Set<Int>()
    private var budget = 10_000

    init(graph: KeyedArchive) { self.graph = graph }

    mutating func actions(_ fields: [String: PropertyValue]) throws -> [ArchiveNodeAction] {
        let actions = try graph.array(fields["_actions"])
        var keys: [Int: String] = [:]
        if try !graph.isNull(fields["_keyedActions"]) {
            let dictionary = try graph.dictionary(fields["_keyedActions"])
            guard ["NSDictionary", "NSMutableDictionary"].contains(try graph.className(dictionary)) else {
                throw SceneArchiveError.invalid("Invalid keyed actions dictionary")
            }
            let names = try graph.array(dictionary["NS.keys"])
            let values = try graph.array(dictionary["NS.objects"])
            guard names.count == values.count else { throw SceneArchiveError.invalid("Invalid keyed actions") }
            var seenKeys = Set<String>()
            for (name, value) in zip(names, values) {
                let id = try graph.reference(value, field: "_keyedActions")
                guard let key = try graph.string(name), seenKeys.insert(key).inserted, keys[id] == nil else {
                    throw SceneArchiveError.invalid("Duplicate or invalid action key")
                }
                keys[id] = key
            }
        }
        var seen = Set<Int>()
        var result: [ArchiveNodeAction] = []
        for value in actions {
            let id = try graph.reference(value, field: "_actions")
            guard seen.insert(id).inserted else { throw SceneArchiveError.invalid("Duplicate running action") }
            result.append(ArchiveNodeAction(action: try decode(value), key: keys.removeValue(forKey: id)))
        }
        guard keys.isEmpty else { throw SceneArchiveError.invalid("Keyed action missing from action list") }
        return result
    }

    mutating func decode(_ value: PropertyValue) throws -> ArchiveAction {
        let id = try graph.reference(value, field: "action")
        guard active.count < 64, budget > 0, active.insert(id).inserted else {
            throw SceneArchiveError.invalid("Cyclic or excessive action graph")
        }
        defer { active.remove(id) }
        budget -= 1
        let fields = try graph.dictionary(value)
        let name = try graph.className(fields)
        func number(_ key: String, _ fallback: Float = 0) throws -> Float {
            try graph.number(fields[key], default: fallback)
        }
        func flag(_ key: String, _ fallback: Bool = false) throws -> Bool {
            try graph.boolean(fields[key], default: fallback)
        }
        for key in ["_lastRatio", "_timesRepeated", "_mycaction->_animIndex"] {
            guard try number(key) == 0 else { throw SceneArchiveError.unsupported("Partially executed action") }
        }
        guard try !flag("_isReversed"), try !flag("_hasFired"), try !flag("_finished") else {
            throw SceneArchiveError.unsupported("Reversed or already fired action")
        }
        let seconds = try number("_duration")
        guard seconds >= 0, seconds <= 31_536_000 else { throw SceneArchiveError.invalid("Invalid action duration") }
        let duration = Duration.seconds(Double(seconds))
        let mode: Action.TimingMode
        switch try number("_timingMode") {
        case 0: mode = .linear
        case 1: mode = .easeIn
        case 2: mode = .easeOut
        case 3: mode = .easeInEaseOut
        default: throw SceneArchiveError.unsupported("Action timing mode")
        }
        let action: Action
        var deferred: ArchiveAction?
        switch name {
        case "SKMove":
            let x = try number("_posTarget.x"), y = try number("_posTarget.y")
            let useX = try flag("_useX"), useY = try flag("_useY")
            if try flag("_isRelative") {
                action = .move(by: [useX ? x : 0, useY ? y : 0], duration: duration)
            } else if useX && useY {
                action = .move(to: [x, y], duration: duration)
            } else if useX {
                action = .moveTo(x: x, duration: duration)
            } else if useY {
                action = .moveTo(y: y, duration: duration)
            } else { throw SceneArchiveError.invalid("Move action without axes") }
        case "SKRotate":
            guard try !flag("_useX"), try !flag("_useY"), try flag("_useZ") else {
                throw SceneArchiveError.unsupported("Non-planar rotation action")
            }
            let angle = try number("_rotZ")
            action = try flag("_isRelative") ? .rotate(by: angle, duration: duration)
                : .rotate(to: angle, duration: duration, shortestUnitArc: flag("_isUnitArc"))
        case "SKScale":
            guard try !flag("_isTargetSizeBased") else {
                throw SceneArchiveError.unsupported("Size-based scale action")
            }
            let useX = try flag("_useX"), useY = try flag("_useY")
            guard useX || useY else { throw SceneArchiveError.invalid("Scale action without axes") }
            let target = try Vector2(number("_scaleTargetX"), number("_scaleTargetY"))
            if try flag("_isRelative") {
                guard useX && useY else {
                    throw SceneArchiveError.unsupported("Single-axis relative scale action")
                }
                action = .scale(by: target, duration: duration)
            } else if useX && useY {
                action = .scale(to: target, duration: duration)
            } else {
                action = useX ? .scaleTo(x: target.x, duration: duration) : .scaleTo(y: target.y, duration: duration)
            }
        case "SKFade":
            let alpha = try number("_alphaTarget")
            action = try flag("_isRelative") ? .fadeAlpha(by: alpha, duration: duration) : .fadeAlpha(to: alpha, duration: duration)
        case "SKColorize":
            guard try !graph.isNull(fields["_colorMix"]), try !graph.isNull(fields["_isMixOnly"]) else {
                throw SceneArchiveError.invalid("Missing color action settings")
            }
            let blend = try number("_colorMix")
            guard (0...1).contains(blend) else { throw SceneArchiveError.invalid("Invalid color blend factor") }
            if try flag("_isMixOnly") {
                action = .colorize(withBlendFactor: blend, duration: duration)
            } else {
                for key in ["_colorBlendR", "_colorBlendG", "_colorBlendB", "_colorBlendA"] {
                    guard try !graph.isNull(fields[key]), try (0...1).contains(number(key)) else {
                        throw SceneArchiveError.invalid("Invalid action color component")
                    }
                }
                action = .colorize(with: try graph.color(fields, prefix: "_colorBlend"),
                    blendFactor: blend, duration: duration)
            }
        case "SKWait": action = .wait(for: duration)
        case "SKHide", "SKRemove":
            guard seconds == 0 else { throw SceneArchiveError.unsupported("Retimed instantaneous action") }
            action = name == "SKRemove" ? .removeFromParent() : (try flag("_hiddenValue") ? .hide : .unhide)
        case "SKPlaySound":
            guard let filename = try graph.string(fields["_fileName"]), !filename.isEmpty else {
                throw SceneArchiveError.invalid("Missing sound filename")
            }
            guard try graph.vector(fields["_position"], default: .zero) == .zero else {
                throw SceneArchiveError.unsupported("Positioned sound action")
            }
            let waits = try flag("_wait")
            guard waits || seconds == 0 else { throw SceneArchiveError.unsupported("Retimed nonwaiting sound action") }
            deferred = .sound(filename, waits ? duration : .zero)
            action = .wait(for: waits ? duration : .zero)
        case "SKAnimate":
            let values = try graph.array(fields["_textures"])
            guard !values.isEmpty, values.count <= 4096, values.count <= budget else {
                throw SceneArchiveError.invalid("Invalid animation frame count")
            }
            budget -= values.count
            guard case let .number(time) = try graph.resolve(fields["_timePerFrame"]),
                  time.isFinite, time >= 1e-9, time <= 31_536_000,
                  abs(time * Double(values.count) - Double(seconds)) < max(0.00001, Double(seconds) * 0.00001) else {
                throw SceneArchiveError.unsupported("Invalid or retimed texture animation")
            }
            let frames = try values.map { try ArchiveTexture($0, graph: graph) }
            let animation = ArchiveAction.animation(frames, .seconds(time),
                resize: try flag("_resize"), restore: try flag("_restore"))
            deferred = animation
            action = animation.timingAction
        case "SKSequence", "SKGroup":
            let values = try graph.array(fields["_actions"])
            var children: [ArchiveAction] = []
            for value in values { children.append(try decode(value)) }
            let composite: ArchiveAction = name == "SKSequence" ? .sequence(children) : .group(children)
            deferred = composite
            action = composite.timingAction
        case "SKRepeat":
            guard let value = fields["_repeatedAction"] else { throw SceneArchiveError.invalid("Missing repeated action") }
            let child = try decode(value)
            if try flag("_forever") { action = .repeatForever(child.timingAction); deferred = .repeated(child, count: nil) }
            else {
                let count = try number("_timesToRepeat")
                guard count >= 0, count <= 100_000, count.rounded() == count else {
                    throw SceneArchiveError.invalid("Invalid action repeat count")
                }
                action = .repeat(child.timingAction, count: Int(count))
                deferred = .repeated(child, count: Int(count))
            }
        default: throw SceneArchiveError.unsupported("Action class \(name)")
        }
        if ["SKSequence", "SKGroup", "SKRepeat"].contains(name),
           let computed = action.duration {
            let parts = computed.components
            let total = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
            guard abs(total - Double(seconds)) < max(0.00001, Double(seconds) * 0.00001) else {
                throw SceneArchiveError.unsupported("Retimed composite action")
            }
        }
        return .timed(deferred ?? .ready(action), mode)
    }
}
