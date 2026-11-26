//
//  BitmapFont.swift
//  SpriteGraph
//

import SpriteCore

/// Glyph atlas used by ``Label``, following AngelCode BMFont metrics.
///
/// Fonts may be plain bitmaps or signed distance fields (SDF), which stay sharp
/// at any scale on backends that support ``SpriteShader/distanceField(smoothing:)``.
public struct BitmapFont: Sendable {

    public struct Glyph: Hashable, Sendable {

        /// Region of the font texture in pixels, origin at the top-left.
        public var region: Rect

        /// Offset of the glyph's top-left from the pen position at the top of the line (Y-down).
        public var offset: Vector2

        /// Horizontal pen advance after drawing this glyph.
        public var advance: Float

        public init(region: Rect, offset: Vector2 = .zero, advance: Float) {
            self.region = region
            self.offset = offset
            self.advance = advance
        }
    }

    public struct KerningPair: Hashable, Sendable {
        public var first: Character
        public var second: Character

        public init(_ first: Character, _ second: Character) {
            self.first = first
            self.second = second
        }
    }

    public var texture: Texture

    public var glyphs: [Character: Glyph]

    /// Distance between consecutive baselines, in font pixels.
    public var lineHeight: Float

    /// Distance from the top of a line to its baseline, in font pixels.
    public var baseline: Float

    /// Nominal size in font pixels that corresponds to ``Label/fontSize``.
    public var size: Float

    public var kerning: [KerningPair: Float]

    /// Edge smoothing for SDF fonts, or `nil` for plain bitmap fonts.
    public var distanceFieldSmoothing: Float?

    public init(
        texture: Texture,
        glyphs: [Character: Glyph],
        lineHeight: Float,
        baseline: Float,
        size: Float? = nil,
        kerning: [KerningPair: Float] = [:],
        distanceFieldSmoothing: Float? = nil
    ) {
        self.texture = texture
        self.glyphs = glyphs
        self.lineHeight = lineHeight
        self.baseline = baseline
        self.size = size ?? lineHeight
        self.kerning = kerning
        self.distanceFieldSmoothing = distanceFieldSmoothing
    }

    /// Creates a font from a fixed grid of equally sized cells.
    ///
    /// - Parameters:
    ///   - characters: Characters in cell order, left-to-right then top-to-bottom.
    ///   - cellSize: Size of each cell in pixels.
    ///   - advance: Pen advance; defaults to the cell width.
    public static func monospaced(
        texture: Texture,
        characters: String,
        cellSize: Vector2,
        advance: Float? = nil,
        baseline: Float? = nil
    ) -> BitmapFont {
        let columns = max(Int(texture.size.x / cellSize.x), 1)
        var glyphs = [Character: Glyph]()
        for (index, character) in characters.enumerated() {
            let origin = Vector2(Float(index % columns), Float(index / columns)) * cellSize
            glyphs[character] = Glyph(region: Rect(origin: origin, size: cellSize), advance: advance ?? cellSize.x)
        }
        return BitmapFont(texture: texture, glyphs: glyphs, lineHeight: cellSize.y, baseline: baseline ?? cellSize.y)
    }

    /// Glyph for a character, falling back to its uppercase form and then `?`.
    public func glyph(for character: Character) -> Glyph? {
        if let glyph = glyphs[character] { return glyph }
        if let upper = character.uppercased().first, let glyph = glyphs[upper] { return glyph }
        return glyphs["?"]
    }

    public func kerning(_ first: Character, _ second: Character) -> Float {
        kerning[KerningPair(first, second)] ?? 0
    }

    var shader: SpriteShader {
        distanceFieldSmoothing.map { .distanceField(smoothing: $0) } ?? .standard
    }
}
