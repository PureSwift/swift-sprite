//
//  Color.swift
//  SpriteCore
//

/// Linear RGBA color with straight (non-premultiplied) alpha.
public struct Color: Equatable, Hashable, Sendable {

    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(white: Float, alpha: Float = 1) {
        self.init(red: white, green: white, blue: white, alpha: alpha)
    }

    /// Creates a color from a packed `0xRRGGBBAA` value.
    public init(rgba hex: UInt32) {
        self.init(
            red: Float((hex >> 24) & 0xFF) / 255,
            green: Float((hex >> 16) & 0xFF) / 255,
            blue: Float((hex >> 8) & 0xFF) / 255,
            alpha: Float(hex & 0xFF) / 255
        )
    }
}

public extension Color {

    static let clear = Color(white: 0, alpha: 0)
    static let black = Color(white: 0)
    static let white = Color(white: 1)
    static let red = Color(red: 1, green: 0, blue: 0)
    static let green = Color(red: 0, green: 1, blue: 0)
    static let blue = Color(red: 0, green: 0, blue: 1)

    var simd: SIMD4<Float> {
        SIMD4(red, green, blue, alpha)
    }

    var premultiplied: Color {
        Color(red: red * alpha, green: green * alpha, blue: blue * alpha, alpha: alpha)
    }

    /// Component-wise product, used for tinting.
    static func * (lhs: Color, rhs: Color) -> Color {
        Color(
            red: lhs.red * rhs.red,
            green: lhs.green * rhs.green,
            blue: lhs.blue * rhs.blue,
            alpha: lhs.alpha * rhs.alpha
        )
    }

    /// Linear interpolation between two colors.
    func mix(with other: Color, fraction t: Float) -> Color {
        Color(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }
}
