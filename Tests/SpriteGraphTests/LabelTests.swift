//
//  LabelTests.swift
//  SpriteGraphTests
//

import Testing
import SpriteCore
@testable import SpriteGraph

@MainActor @Suite struct LabelTests {

    /// Debug font with a placeholder texture; metrics are what matter here.
    var font: BitmapFont {
        let (image, glyphs) = DebugFont.makeImage()
        return DebugFont.font(texture: Texture(id: TextureID(rawValue: 1), textureSize: image.size), glyphs: glyphs)
    }

    @Test func debugFontRasterizesGlyphs() throws {
        let (image, glyphs) = DebugFont.makeImage()
        #expect(glyphs.count == DebugFont.patterns.count)
        for (character, pattern) in DebugFont.patterns {
            #expect(pattern.count == 15, "Glyph \(character) must be 3×5")
        }
        // "I" top row is fully lit; its second row only in the middle.
        let glyph = try #require(glyphs["I"])
        let x = Int(glyph.region.minX), y = Int(glyph.region.minY)
        #expect(image[x, y] == .white && image[x + 2, y] == .white)
        #expect(image[x, y + 1] == .clear && image[x + 1, y + 1] == .white)
    }

    @Test func leftAlignedBaselineLayout() {
        let label = Label(text: "AB", font: font)
        label.horizontalAlignmentMode = .left
        let layout = label.layout
        #expect(layout.count == 2)
        // Glyph bottoms sit on the baseline at y = 0; advance is 4 px.
        #expect(layout[0].rect == Rect(x: 0, y: 0, width: 3, height: 5))
        #expect(layout[1].rect == Rect(x: 4, y: 0, width: 3, height: 5))
    }

    @Test func alignmentModes() throws {
        let label = Label(text: "ABC", font: font, fontSize: 10)
        // Width = 3 glyphs × 4 advance × scale 2 = 24.
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        let bounds = try #require(label.localBounds)
        #expect(approx(bounds.minX, -12))
        #expect(approx(bounds.maxX, 10))
        // Line spans baseline - 2 (descender space) to baseline + 5, scaled by 2, centered.
        #expect(approx(bounds.midY, 2))

        label.horizontalAlignmentMode = .right
        label.verticalAlignmentMode = .top
        let topRight = try #require(label.localBounds)
        #expect(approx(topRight.maxY, 0))
        #expect(approx(topRight.minX, -24))
    }

    @Test func wrapsAndLimitsLines() {
        let label = Label(text: "AAA BBB CCC\nDDD", font: font)
        label.horizontalAlignmentMode = .left
        #expect(label.lines(font: font, scale: 1).count == 2)

        // 7 glyphs (28 px) fit "AAA BBB"; "CCC" wraps.
        label.preferredMaxLayoutWidth = 28
        #expect(label.lines(font: font, scale: 1).map { String($0) } == ["AAA BBB", "CCC", "DDD"])
        label.numberOfLines = 2
        #expect(label.lines(font: font, scale: 1).map { String($0) } == ["AAA BBB", "CCC"])

        // Second line baseline is one line height (7) below the first.
        let rects = label.layout.map(\.rect)
        #expect(rects.contains { $0.minY == -7 })
    }

    @Test func lowercaseFallsBackToUppercase() {
        let label = Label(text: "ab", font: font)
        #expect(label.layout.count == 2)
        #expect(label.layout[0].region == font.glyphs["A"]!.region)
    }

    @Test func kerningAdjustsAdvance() {
        var kerned = font
        kerned.kerning[BitmapFont.KerningPair("A", "V")] = -1
        let label = Label(text: "AV", font: kerned)
        label.horizontalAlignmentMode = .left
        #expect(label.layout[1].rect.minX == 3)
    }

    @Test func distanceFieldFontsUseSDFShader() {
        var sdf = font
        sdf.distanceFieldSmoothing = 0.1
        let scene = Scene(size: [100, 100])
        scene.addChild(Label(text: "HI", font: sdf))
        let frame = scene.makeFrame(viewportSize: [100, 100])
        #expect(frame.batches.map(\.shader) == [.distanceField(smoothing: 0.1)])
    }

    @Test func layoutInvalidatesOnChange() {
        let label = Label(text: "A", font: font)
        #expect(label.layout.count == 1)
        label.text = "AAA"
        #expect(label.layout.count == 3)
        label.text = ""
        #expect(label.localBounds == nil)
    }
}
