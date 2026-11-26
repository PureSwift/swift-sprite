//
//  PhysicsCategory.swift
//  SpritePhysics
//

/// Type-safe 32-bit category mask for collision filtering and contact tests.
///
/// ```swift
/// extension PhysicsCategory {
///     static let player = PhysicsCategory(bit: 0)
///     static let enemy = PhysicsCategory(bit: 1)
/// }
/// body.contactTestBitMask = [.enemy]
/// ```
public struct PhysicsCategory: OptionSet, Hashable, Sendable {

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Category with a single bit set (`0..<32`).
    public init(bit: Int) {
        precondition((0 ..< 32).contains(bit), "Category bit must be in 0..<32")
        self.rawValue = 1 << UInt32(bit)
    }

    public static let none: PhysicsCategory = []

    public static let all = PhysicsCategory(rawValue: .max)

    /// Whether any bit is shared with `other`.
    public func intersects(_ other: PhysicsCategory) -> Bool {
        !intersection(other).isEmpty
    }
}
