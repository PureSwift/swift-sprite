/// A node-name pattern with stars, bracket character sets, and ascending scalar ranges.
/// Brackets accept `[abc]`, `[a,b]`, and `[0-9]`. Negation and escaping are unsupported.
public struct NodeNamePattern: Sendable {
    private enum Token: Sendable {
        case literal(Character)
        case star
        case set([ClosedRange<UInt32>])

        func matches(_ character: Character) -> Bool {
            switch self {
            case let .literal(value): return value == character
            case .star: return false
            case let .set(ranges):
                guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else { return false }
                return ranges.contains { $0.contains(scalar.value) }
            }
        }
    }

    private let tokens: [Token]
    private let allowsUnnamed: Bool

    public init?(_ pattern: String) {
        let characters = Array(pattern)
        var result: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                result.append(.star)
            } else if character == "[" {
                index += 1
                var ranges: [ClosedRange<UInt32>] = []
                while index < characters.count && characters[index] != "]" {
                    if characters[index] == "," { index += 1; continue }
                    let start = characters[index]
                    guard !"[!^\\-".contains(start), start.unicodeScalars.count == 1,
                          let lower = start.unicodeScalars.first?.value else { return nil }
                    index += 1
                    if index < characters.count && characters[index] == "-" {
                        index += 1
                        guard index < characters.count else { return nil }
                        let end = characters[index]
                        guard !"[],!^\\-".contains(end), end.unicodeScalars.count == 1,
                              let upper = end.unicodeScalars.first?.value, lower <= upper else { return nil }
                        ranges.append(lower...upper)
                        index += 1
                    } else {
                        ranges.append(lower...lower)
                    }
                }
                guard index < characters.count, !ranges.isEmpty else { return nil }
                result.append(.set(ranges))
            } else {
                guard character != "]" else { return nil }
                result.append(.literal(character))
            }
            index += 1
        }
        tokens = result
        allowsUnnamed = !result.isEmpty && result.allSatisfy { if case .star = $0 { return true }; return false }
    }

    /// Matches the entire name; patterns containing only stars also match unnamed nodes.
    public func matches(_ name: String?) -> Bool {
        guard let name else { return allowsUnnamed }
        let characters = Array(name)
        var index = 0, token = 0, retryIndex = 0
        var star: Int?
        while index < characters.count {
            if token < tokens.count, case .star = tokens[token] {
                star = token
                token += 1
                retryIndex = index
            } else if token < tokens.count && tokens[token].matches(characters[index]) {
                token += 1
                index += 1
            } else if let star {
                retryIndex += 1
                index = retryIndex
                token = star + 1
            } else {
                return false
            }
        }
        while token < tokens.count {
            guard case .star = tokens[token] else { return false }
            token += 1
        }
        return true
    }
}
