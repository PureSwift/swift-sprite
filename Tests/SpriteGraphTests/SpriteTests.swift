//
//  SpriteTests.swift
//  SpriteGraphTests
//

import Testing
import SpriteCore
@testable import SpriteGraph

@MainActor @Suite struct SpriteTests {

    let texture = Texture(id: TextureID(rawValue: 1), textureSize: [30, 30])

    @Test func defaultsToTextureSize() {
        let sprite = Sprite(texture: texture)
        #expect(sprite.size == [30, 30])
        #expect(sprite.localBounds == Rect(x: -15, y: -15, width: 30, height: 30))
        sprite.size = [10, 10]
        sprite.scaleToTextureSize()
        #expect(sprite.size == [30, 30])
    }

    @Test func tintMixesTowardColor() {
        let sprite = Sprite(texture: texture)
        sprite.color = Color(red: 1, green: 0, blue: 0)
        #expect(sprite.vertexColor == .white)
        sprite.colorBlendFactor = 0.5
        #expect(sprite.vertexColor == Color(red: 1, green: 0.5, blue: 0.5))
        // Untextured sprites draw their color directly.
        #expect(Sprite(color: .blue, size: [1, 1]).vertexColor == .blue)
    }

    @Test func nineSliceStretchesCenter() throws {
        let sprite = Sprite(texture: texture)
        sprite.centerRect = Rect(x: 1.0 / 3, y: 1.0 / 3, width: 1.0 / 3, height: 1.0 / 3)
        sprite.anchorPoint = .zero
        sprite.size = [100, 60]
        let quads = sprite.nineSliceQuads(texture: texture)
        #expect(quads.count == 9)

        // Bottom-left quad comes from the texture's bottom-left (top-down row 2, column 0).
        let bottomLeft = try #require(quads.first { approx($0.rect.origin, .zero) })
        #expect(approx(bottomLeft.rect.size, [10, 10]))
        #expect(approx(bottomLeft.texture.region.origin, [0, 20]))

        // Center stretches to fill the remainder.
        let center = try #require(quads.first { approx($0.rect.origin, [10, 10]) })
        #expect(approx(center.rect.size, [80, 40]))
        #expect(approx(center.texture.region.size, [10, 10]))

        // Top-right corner keeps its pixel size.
        let topRight = try #require(quads.first { approx($0.rect.origin, [90, 50]) })
        #expect(approx(topRight.rect.size, [10, 10]))
        #expect(approx(topRight.texture.region.origin, [20, 0]))
    }

    @Test func nineSliceShrinksCornersWhenSmall() {
        let sprite = Sprite(texture: texture)
        sprite.centerRect = Rect(x: 1.0 / 3, y: 1.0 / 3, width: 1.0 / 3, height: 1.0 / 3)
        sprite.size = [10, 30]
        let quads = sprite.nineSliceQuads(texture: texture)
        // Center column collapses; corners scale to 5 px wide each.
        #expect(quads.count == 6)
        #expect(quads.allSatisfy { approx($0.rect.width, 5) })
    }

    @Test func nineSliceRendersThroughScene() {
        let scene = Scene(size: [100, 100])
        let sprite = Sprite(texture: texture)
        sprite.centerRect = Rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        sprite.size = [60, 60]
        scene.addChild(sprite)
        let frame = scene.makeFrame(viewportSize: [100, 100])
        #expect(frame.vertices.count == 9 * 4)
        #expect(frame.batches.count == 1)
    }
}
