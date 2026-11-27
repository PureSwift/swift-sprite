import Foundation
import CoreFoundation

indirect enum PropertyValue: Sendable {
    case null, bool(Bool), number(Double), string(String), data(Data)
    case uid(Int), array([PropertyValue]), dictionary([String: PropertyValue])

    var dictionary: [String: PropertyValue]? {
        if case let .dictionary(value) = self { return value }
        return nil
    }
    var array: [PropertyValue]? {
        if case let .array(value) = self { return value }
        return nil
    }
    var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}

enum ArchivePropertyList {
    static func decode(_ data: Data) throws -> PropertyValue {
        guard data.count <= 64 * 1024 * 1024 else {
            throw SceneArchiveError.invalid("Archive exceeds 64 MiB")
        }
        do {
            let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
            // Foundation exposes binary UIDs as opaque objects. Its XML writer represents
            // them as CF$UID dictionaries, avoiding private CoreFoundation UID APIs.
            let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            // The XML reader otherwise turns CF$UID straight back into opaque UID objects.
            let readable = String(decoding: xml, as: UTF8.self)
                .replacingOccurrences(of: "<key>CF$UID</key>", with: "<key>SpriteArchiveUID</key>")
            let normalized = try PropertyListSerialization.propertyList(from: Data(readable.utf8), options: [], format: nil)
            var budget = 1_000_000
            return try convert(normalized, depth: 0, budget: &budget)
        } catch let error as SceneArchiveError {
            throw error
        } catch {
            throw SceneArchiveError.invalid("Invalid property list: \(error.localizedDescription)")
        }
    }

    private static func convert(_ value: Any, depth: Int, budget: inout Int) throws -> PropertyValue {
        guard depth < 128, budget > 0 else { throw SceneArchiveError.invalid("Property list nesting or size limit") }
        budget -= 1
        if let dictionary = value as? [String: Any] {
            if dictionary.count == 1, let number = dictionary["SpriteArchiveUID"] as? NSNumber {
                guard CFGetTypeID(number) != CFBooleanGetTypeID(),
                      let id = Int(number.stringValue), id >= 0 else {
                    throw SceneArchiveError.invalid("Invalid archive UID")
                }
                return .uid(id)
            }
            var result: [String: PropertyValue] = [:]
            for (key, value) in dictionary {
                result[key] = try convert(value, depth: depth + 1, budget: &budget)
            }
            return .dictionary(result)
        }
        if let array = value as? [Any] {
            return .array(try array.map { try convert($0, depth: depth + 1, budget: &budget) })
        }
        if let string = value as? String { return .string(string) }
        if let data = value as? Data { return .data(data) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
            return .number(number.doubleValue)
        }
        if let date = value as? Date { return .number(date.timeIntervalSinceReferenceDate) }
        throw SceneArchiveError.invalid("Unsupported property list value")
    }
}
