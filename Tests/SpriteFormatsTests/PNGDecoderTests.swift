//
//  PNGDecoderTests.swift
//  SpriteFormatsTests
//

import Testing
import SpriteCore
@testable import SpriteFormats

@Suite struct PNGDecoderTests {

    /// Each fixture covers a color type / bit depth, all five filters, split IDAT chunks
    /// and an ancillary chunk; `.rgba` files hold the expected straight-alpha pixels.
    @Test(arguments: [
        "rgba8", "rgba8-interlaced", "rgb16-trns", "gray1", "gray4-trns", "palette2-trns", "graya8-interlaced",
    ])
    func decodesFixture(_ name: String) throws {
        let image = try PixelBuffer(png: Fixtures.bytes("PNG/\(name).png"))
        #expect(image.width == 19 && image.height == 13)
        let expected = try Fixtures.bytes("PNG/\(name).rgba")
        #expect(image.pixels == expected)
    }

    @Test func decodesAppleTextureAtlasOutput() throws {
        // Written by Xcode's TextureAtlas tool.
        let image = try PixelBuffer(png: Fixtures.bytes("SpriteKit/sample.atlasc/sample.1.png"))
        #expect(image.width == 82 && image.height == 60)
    }

    @Test func rejectsInvalidData() throws {
        #expect(throws: PNGDecoder.Error.invalidSignature) { try PNGDecoder.decode([1, 2, 3]) }
        var data = try Fixtures.bytes("PNG/rgba8.png")
        data[20] ^= 0xFF // inside IHDR, breaking its CRC
        #expect(throws: PNGDecoder.Error.self) { try PNGDecoder.decode(data) }
        let truncated = Array(try Fixtures.bytes("PNG/rgba8.png").prefix(60))
        #expect(throws: PNGDecoder.Error.truncated) { try PNGDecoder.decode(truncated) }
    }
}
