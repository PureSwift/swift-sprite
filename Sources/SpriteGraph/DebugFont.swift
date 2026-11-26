//
//  DebugFont.swift
//  SpriteGraph
//

import SpriteCore

public extension BitmapFont {

    /// Uploads the built-in 3×5 pixel font (uppercase ASCII, digits and common punctuation).
    ///
    /// Intended for debug overlays; render with nearest filtering and integral `fontSize` multiples of 5.
    static func debug(backend: some SpriteRenderBackend) throws -> BitmapFont {
        let (image, glyphs) = DebugFont.makeImage()
        let texture = try backend.makeTexture(image, filtering: .nearest)
        return DebugFont.font(texture: texture, glyphs: glyphs)
    }
}

enum DebugFont {

    static let glyphWidth = 3
    static let glyphHeight = 5
    static let columns = 16

    /// Each cell pads the glyph by one pixel to avoid sampling neighbors.
    static let cellWidth = glyphWidth + 2
    static let cellHeight = glyphHeight + 2

    static func font(texture: Texture, glyphs: [Character: BitmapFont.Glyph]) -> BitmapFont {
        BitmapFont(
            texture: texture,
            glyphs: glyphs,
            lineHeight: Float(glyphHeight + 2),
            baseline: Float(glyphHeight),
            size: Float(glyphHeight)
        )
    }

    /// Rasterizes ``patterns`` into a white-on-transparent atlas.
    static func makeImage() -> (PixelBuffer, [Character: BitmapFont.Glyph]) {
        let characters = patterns.keys.sorted()
        let rows = (characters.count + columns - 1) / columns
        var image = PixelBuffer(width: columns * cellWidth, height: rows * cellHeight)
        var glyphs = [Character: BitmapFont.Glyph]()
        for (index, character) in characters.enumerated() {
            let x = (index % columns) * cellWidth + 1
            let y = (index / columns) * cellHeight + 1
            for (offset, pixel) in patterns[character]!.enumerated() where pixel == "#" {
                image[x + offset % glyphWidth, y + offset / glyphWidth] = .white
            }
            glyphs[character] = BitmapFont.Glyph(
                region: Rect(x: Float(x), y: Float(y), width: Float(glyphWidth), height: Float(glyphHeight)),
                advance: Float(glyphWidth + 1)
            )
        }
        return (image, glyphs)
    }

    /// 3×5 glyph bitmaps, rows top to bottom.
    static let patterns: [Character: String] = [
        " ": "..." + "..." + "..." + "..." + "...",
        "A": ".#." + "#.#" + "###" + "#.#" + "#.#",
        "B": "##." + "#.#" + "##." + "#.#" + "##.",
        "C": ".##" + "#.." + "#.." + "#.." + ".##",
        "D": "##." + "#.#" + "#.#" + "#.#" + "##.",
        "E": "###" + "#.." + "##." + "#.." + "###",
        "F": "###" + "#.." + "##." + "#.." + "#..",
        "G": ".##" + "#.." + "#.#" + "#.#" + ".##",
        "H": "#.#" + "#.#" + "###" + "#.#" + "#.#",
        "I": "###" + ".#." + ".#." + ".#." + "###",
        "J": "..#" + "..#" + "..#" + "#.#" + ".#.",
        "K": "#.#" + "#.#" + "##." + "#.#" + "#.#",
        "L": "#.." + "#.." + "#.." + "#.." + "###",
        "M": "#.#" + "###" + "###" + "#.#" + "#.#",
        "N": "##." + "#.#" + "#.#" + "#.#" + "#.#",
        "O": ".#." + "#.#" + "#.#" + "#.#" + ".#.",
        "P": "##." + "#.#" + "##." + "#.." + "#..",
        "Q": ".#." + "#.#" + "#.#" + "##." + ".##",
        "R": "##." + "#.#" + "##." + "#.#" + "#.#",
        "S": ".##" + "#.." + ".#." + "..#" + "##.",
        "T": "###" + ".#." + ".#." + ".#." + ".#.",
        "U": "#.#" + "#.#" + "#.#" + "#.#" + "###",
        "V": "#.#" + "#.#" + "#.#" + "#.#" + ".#.",
        "W": "#.#" + "#.#" + "###" + "###" + "#.#",
        "X": "#.#" + "#.#" + ".#." + "#.#" + "#.#",
        "Y": "#.#" + "#.#" + ".#." + ".#." + ".#.",
        "Z": "###" + "..#" + ".#." + "#.." + "###",
        "0": "###" + "#.#" + "#.#" + "#.#" + "###",
        "1": ".#." + "##." + ".#." + ".#." + "###",
        "2": "##." + "..#" + ".#." + "#.." + "###",
        "3": "##." + "..#" + ".#." + "..#" + "##.",
        "4": "#.#" + "#.#" + "###" + "..#" + "..#",
        "5": "###" + "#.." + "##." + "..#" + "##.",
        "6": ".##" + "#.." + "###" + "#.#" + "###",
        "7": "###" + "..#" + ".#." + ".#." + ".#.",
        "8": "###" + "#.#" + "###" + "#.#" + "###",
        "9": "###" + "#.#" + "###" + "..#" + "##.",
        ".": "..." + "..." + "..." + "..." + ".#.",
        ",": "..." + "..." + "..." + ".#." + "#..",
        ":": "..." + ".#." + "..." + ".#." + "...",
        ";": "..." + ".#." + "..." + ".#." + "#..",
        "-": "..." + "..." + "###" + "..." + "...",
        "_": "..." + "..." + "..." + "..." + "###",
        "+": "..." + ".#." + "###" + ".#." + "...",
        "=": "..." + "###" + "..." + "###" + "...",
        "!": ".#." + ".#." + ".#." + "..." + ".#.",
        "?": "##." + "..#" + ".#." + "..." + ".#.",
        "/": "..#" + "..#" + ".#." + "#.." + "#..",
        "(": ".#." + "#.." + "#.." + "#.." + ".#.",
        ")": ".#." + "..#" + "..#" + "..#" + ".#.",
        "%": "#.#" + "..#" + ".#." + "#.." + "#.#",
        "'": ".#." + ".#." + "..." + "..." + "...",
        "\"": "#.#" + "#.#" + "..." + "..." + "...",
        "#": "#.#" + "###" + "#.#" + "###" + "#.#",
        "<": "..#" + ".#." + "#.." + ".#." + "..#",
        ">": "#.." + ".#." + "..#" + ".#." + "#..",
        "*": "..." + "#.#" + ".#." + "#.#" + "...",
    ]
}
