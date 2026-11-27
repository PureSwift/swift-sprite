import Foundation
import SpriteCore

/// Resolves NSKeyedArchiver objects without invoking NSKeyedUnarchiver.
struct KeyedArchive: Sendable {
    let objects: [PropertyValue]
    let rootID: Int

    init(_ value: PropertyValue) throws {
        guard let archive = value.dictionary, archive["$archiver"]?.string == "NSKeyedArchiver",
              case .number(100_000) = archive["$version"],
              let objects = archive["$objects"]?.array, !objects.isEmpty,
              objects[0].string == "$null", let top = archive["$top"]?.dictionary,
              case let .uid(root) = top["root"], root > 0, objects.indices.contains(root) else {
            throw SceneArchiveError.invalid("Invalid NSKeyedArchiver envelope")
        }
        self.objects = objects
        rootID = root
    }

    func reference(_ value: PropertyValue?, field: String) throws -> Int {
        guard case let .uid(id) = value, id > 0, objects.indices.contains(id) else {
            throw SceneArchiveError.invalid("Invalid object reference: \(field)")
        }
        return id
    }

    func resolve(_ value: PropertyValue?) throws -> PropertyValue {
        var value = value ?? .null
        var seen = Set<Int>()
        while case let .uid(id) = value {
            guard objects.indices.contains(id), seen.count < 128, seen.insert(id).inserted else {
                throw SceneArchiveError.invalid("Invalid or cyclic archive UID")
            }
            if id == 0 { return .null }
            value = objects[id]
        }
        return value
    }

    func dictionary(_ value: PropertyValue?) throws -> [String: PropertyValue] {
        guard let result = try resolve(value).dictionary else { throw SceneArchiveError.invalid("Expected dictionary") }
        return result
    }

    func className(_ fields: [String: PropertyValue]) throws -> String {
        let descriptor = try dictionary(fields["$class"])
        guard let name = descriptor["$classname"]?.string else { throw SceneArchiveError.invalid("Missing class name") }
        return name
    }

    func isNull(_ value: PropertyValue?) throws -> Bool {
        if case .null = try resolve(value) { return true }
        return false
    }

    func isEmpty(_ value: PropertyValue?) throws -> Bool {
        let value = try resolve(value)
        if case .null = value { return true }
        if let array = value.array { return array.isEmpty }
        if let fields = value.dictionary, let contents = fields["NS.objects"]?.array { return contents.isEmpty }
        return false
    }

    func string(_ value: PropertyValue?) throws -> String? {
        let value = try resolve(value)
        if case .null = value { return nil }
        guard let string = value.string else { throw SceneArchiveError.invalid("Expected string") }
        return string
    }

    func number(_ value: PropertyValue?, default fallback: Float) throws -> Float {
        switch try resolve(value) {
        case .null: return fallback
        case let .number(value):
            let result = Float(value)
            guard result.isFinite else { throw SceneArchiveError.invalid("Nonfinite number") }
            return result
        default: throw SceneArchiveError.invalid("Expected number")
        }
    }

    func boolean(_ value: PropertyValue?, default fallback: Bool) throws -> Bool {
        switch try resolve(value) {
        case .null: return fallback
        case let .bool(value): return value
        case .number(0): return false
        case .number(1): return true
        default: throw SceneArchiveError.invalid("Expected boolean")
        }
    }

    func array(_ value: PropertyValue?) throws -> [PropertyValue] {
        let value = try resolve(value)
        if case .null = value { return [] }
        if let array = value.array { return array }
        let fields = try dictionary(value)
        guard ["NSArray", "NSMutableArray"].contains(try className(fields)), let array = fields["NS.objects"]?.array else {
            throw SceneArchiveError.invalid("Expected archived array")
        }
        return array
    }

    func components(_ value: PropertyValue?, key: String, count: Int) throws -> [Float]? {
        let value = try resolve(value)
        if case .null = value { return nil }
        let text: String?
        if let direct = value.string { text = direct }
        else {
            let fields = try dictionary(value)
            guard try className(fields) == "NSValue" else { throw SceneArchiveError.unsupported("Geometry value class") }
            text = try string(fields[key])
        }
        guard let text else { throw SceneArchiveError.invalid("Missing geometry value") }
        let parts = text.split(whereSeparator: { "{} ,\t\n\r".contains($0) })
        let numbers = parts.compactMap { Float($0) }
        guard numbers.count == count, parts.count == count, numbers.allSatisfy(\.isFinite) else {
            throw SceneArchiveError.invalid("Invalid geometry value")
        }
        return numbers
    }

    func vector(_ value: PropertyValue?, default fallback: Vector2) throws -> Vector2 {
        guard let values = try components(value, key: "NS.pointval", count: 2) else { return fallback }
        return Vector2(values[0], values[1])
    }

    func rect(_ value: PropertyValue?, default fallback: Rect) throws -> Rect {
        guard let values = try components(value, key: "NS.rectval", count: 4) else { return fallback }
        return Rect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    func validateUnitRect(_ rect: Rect) throws {
        guard rect.width >= 0, rect.height >= 0, rect.minX >= 0, rect.minY >= 0,
              rect.maxX <= 1.000001, rect.maxY <= 1.000001 else { throw SceneArchiveError.invalid("Invalid unit rectangle") }
    }

    func color(_ fields: [String: PropertyValue], prefix: String) throws -> Color {
        try Color(red: number(fields[prefix + "R"], default: 1),
            green: number(fields[prefix + "G"], default: 1),
            blue: number(fields[prefix + "B"], default: 1),
            alpha: number(fields[prefix + "A"], default: 1))
    }

    func blend(_ value: PropertyValue?) throws -> BlendMode {
        switch try number(value, default: 0) {
        case 0: return .alpha
        case 1: return .add
        case 3: return .multiply
        case 5: return .screen
        case 6: return .replace
        default: throw SceneArchiveError.unsupported("Blend mode")
        }
    }
}
