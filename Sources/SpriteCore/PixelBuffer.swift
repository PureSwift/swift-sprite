//
//  PixelBuffer.swift
//  SpriteCore
//

/// CPU-side RGBA8 image, rows stored top-to-bottom.
public struct PixelBuffer: Equatable, Hashable, Sendable {

    public let width: Int

    public let height: Int

    /// Tightly packed RGBA bytes, `width * height * 4` in length.
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(width >= 0 && height >= 0, "Invalid pixel buffer size")
        precondition(pixels.count == width * height * 4, "Pixel data must be width * height * 4 bytes")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Creates a buffer filled with a single color.
    public init(width: Int, height: Int, fill color: Color = .clear) {
        let rgba = Self.pack(color)
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height * 4)
        for _ in 0 ..< width * height {
            pixels.append(contentsOf: rgba)
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    public var size: Vector2 {
        Vector2(Float(width), Float(height))
    }

    /// Number of bytes per row.
    public var pitch: Int {
        width * 4
    }

    public subscript(x: Int, y: Int) -> Color {
        get {
            let i = (y * width + x) * 4
            return Color(
                red: Float(pixels[i]) / 255,
                green: Float(pixels[i + 1]) / 255,
                blue: Float(pixels[i + 2]) / 255,
                alpha: Float(pixels[i + 3]) / 255
            )
        }
        set {
            let i = (y * width + x) * 4
            let rgba = Self.pack(newValue)
            pixels[i] = rgba[0]
            pixels[i + 1] = rgba[1]
            pixels[i + 2] = rgba[2]
            pixels[i + 3] = rgba[3]
        }
    }

    /// Copies `source` into this buffer with its top-left corner at `(x, y)`.
    public mutating func blit(_ source: PixelBuffer, x: Int, y: Int) {
        precondition(x >= 0 && y >= 0 && x + source.width <= width && y + source.height <= height,
                     "Blit out of bounds")
        for row in 0 ..< source.height {
            let src = row * source.pitch
            let dst = ((y + row) * width + x) * 4
            pixels.replaceSubrange(dst ..< dst + source.pitch, with: source.pixels[src ..< src + source.pitch])
        }
    }

    private static func pack(_ color: Color) -> [UInt8] {
        func byte(_ value: Float) -> UInt8 {
            UInt8((Swift.min(Swift.max(value, 0), 1) * 255).rounded())
        }
        return [byte(color.red), byte(color.green), byte(color.blue), byte(color.alpha)]
    }
}
