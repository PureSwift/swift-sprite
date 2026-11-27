import SpriteCore
import SpriteGraph

struct ArchiveNodeAction: Sendable {
    let action: Action
    let key: String?
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

    private mutating func decode(_ value: PropertyValue) throws -> Action {
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
        guard try !flag("_isReversed"), try !flag("_hasFired") else {
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
            guard try flag("_useX"), try flag("_useY"), try !flag("_isTargetSizeBased") else {
                throw SceneArchiveError.unsupported("Single-axis or size-based scale action")
            }
            let target = try Vector2(number("_scaleTargetX"), number("_scaleTargetY"))
            action = try flag("_isRelative") ? .scale(by: target, duration: duration) : .scale(to: target, duration: duration)
        case "SKFade":
            let alpha = try number("_alphaTarget")
            action = try flag("_isRelative") ? .fadeAlpha(by: alpha, duration: duration) : .fadeAlpha(to: alpha, duration: duration)
        case "SKWait": action = .wait(for: duration)
        case "SKHide", "SKRemove":
            guard seconds == 0 else { throw SceneArchiveError.unsupported("Retimed instantaneous action") }
            action = name == "SKRemove" ? .removeFromParent() : (try flag("_hiddenValue") ? .hide : .unhide)
        case "SKSequence", "SKGroup":
            let values = try graph.array(fields["_actions"])
            var children: [Action] = []
            for value in values { children.append(try decode(value)) }
            action = name == "SKSequence" ? .sequence(children) : .group(children)
        case "SKRepeat":
            guard let value = fields["_repeatedAction"] else { throw SceneArchiveError.invalid("Missing repeated action") }
            let child = try decode(value)
            if try flag("_forever") { action = .repeatForever(child) }
            else {
                let count = try number("_timesToRepeat")
                guard count >= 0, count <= 100_000, count.rounded() == count else {
                    throw SceneArchiveError.invalid("Invalid action repeat count")
                }
                action = .repeat(child, count: Int(count))
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
        return action.timingMode(mode)
    }
}
