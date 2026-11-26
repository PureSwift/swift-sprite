//
//  TextureTests.swift
//  SpriteCoreTests
//

import Testing
@testable import SpriteCore

/// In-memory backend that records uploaded textures.
final class MockBackend: SpriteRenderBackend {

    var drawableSize = Vector2(320, 240)
    var uploads = [TextureID: PixelBuffer]()
    var renderedFrames = [SpriteFrame]()
    private var nextID: UInt32 = 1

    func makeTexture(_ pixels: PixelBuffer, filtering: TextureFiltering) throws -> Texture {
        let id = TextureID(rawValue: nextID)
        nextID += 1
        uploads[id] = pixels
        return Texture(id: id, textureSize: pixels.size)
    }

    func updateTexture(_ texture: Texture, with pixels: PixelBuffer) throws {
        uploads[texture.id] = pixels
    }

    func destroyTexture(_ texture: Texture) {
        uploads[texture.id] = nil
    }

    func render(_ frame: SpriteFrame, clearColor: Color) throws {
        renderedFrames.append(frame)
    }
}

@Suite struct TextureTests {

    @Test func subtextureUVs() {
        let texture = Texture(id: TextureID(rawValue: 1), textureSize: Vector2(256, 128))
        #expect(texture.uvRect == .unit)
        let sub = texture.subtexture(in: Rect(x: 64, y: 32, width: 64, height: 32))
        #expect(sub.id == texture.id)
        #expect(sub.size == Vector2(64, 32))
        #expect(sub.uvRect == Rect(x: 0.25, y: 0.25, width: 0.25, height: 0.25))
        // Nested sub-textures are relative to their parent region.
        let nested = sub.subtexture(inUnitRect: Rect(x: 0.5, y: 0, width: 0.5, height: 1))
        #expect(nested.region == Rect(x: 96, y: 32, width: 32, height: 32))
    }

    @Test func pixelBufferBlitAndSubscript() {
        var dst = PixelBuffer(width: 4, height: 4, fill: .black)
        let src = PixelBuffer(width: 2, height: 2, fill: .red)
        dst.blit(src, x: 1, y: 2)
        #expect(dst[1, 2] == .red)
        #expect(dst[2, 3] == .red)
        #expect(dst[0, 2] == .black)
        #expect(dst[1, 1] == .black)
    }

    @Test func packerPlacesWithoutOverlap() throws {
        let sizes = [(width: 30, height: 10), (width: 20, height: 20), (width: 10, height: 30), (width: 25, height: 5)]
        let packer = AtlasPacker(maxWidth: 64, maxHeight: 64, padding: 1)
        let layout = try packer.pack(sizes)
        #expect(layout.placements.count == sizes.count)
        let rects = zip(layout.placements, sizes).map {
            Rect(x: Float($0.x), y: Float($0.y), width: Float($1.width), height: Float($1.height))
        }
        for i in rects.indices {
            #expect(rects[i].maxX <= Float(layout.width) && rects[i].maxY <= Float(layout.height))
            for j in rects.indices where j > i {
                #expect(!rects[i].intersects(rects[j]))
            }
        }
        #expect(layout.width.nonzeroBitCount == 1 && layout.height.nonzeroBitCount == 1)
    }

    @Test func packerRejectsOversizedInput() {
        let packer = AtlasPacker(maxWidth: 32, maxHeight: 32)
        #expect(throws: AtlasPacker.Error.doesNotFit) {
            try packer.pack([(width: 40, height: 4)])
        }
        #expect(throws: AtlasPacker.Error.doesNotFit) {
            try packer.pack(Array(repeating: (width: 16, height: 16), count: 5))
        }
    }

    @Test func atlasUploadsPackedImages() throws {
        let backend = MockBackend()
        let atlas = try TextureAtlas.make(
            images: [
                "red": PixelBuffer(width: 8, height: 8, fill: .red),
                "blue": PixelBuffer(width: 4, height: 16, fill: .blue),
            ],
            backend: backend
        )
        #expect(atlas.textureNames == ["blue", "red"])
        #expect(backend.uploads.count == 1)
        let buffer = try #require(backend.uploads[atlas.texture.id])
        let red = try #require(atlas["red"])
        let blue = try #require(atlas["blue"])
        #expect(red.size == Vector2(8, 8))
        #expect(blue.size == Vector2(4, 16))
        #expect(buffer[Int(red.region.minX), Int(red.region.minY)] == .red)
        #expect(buffer[Int(blue.region.maxX) - 1, Int(blue.region.maxY) - 1] == .blue)
        #expect(atlas["missing"] == nil)
    }
}
