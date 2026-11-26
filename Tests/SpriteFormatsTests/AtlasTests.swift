//
//  AtlasTests.swift
//  SpriteFormatsTests
//

import Foundation
import Testing
import SpriteCore
@testable import SpriteFormats

/// In-memory backend recording uploaded textures.
final class MockBackend: SpriteRenderBackend {

    var drawableSize = Vector2(320, 240)
    var uploads = [TextureID: PixelBuffer]()
    var filters = [TextureID: TextureFiltering]()
    private var nextID: UInt32 = 1

    func makeTexture(_ pixels: PixelBuffer, filtering: TextureFiltering) throws -> Texture {
        let id = TextureID(rawValue: nextID)
        nextID += 1
        uploads[id] = pixels
        filters[id] = filtering
        return Texture(id: id, textureSize: pixels.size)
    }

    func updateTexture(_ texture: Texture, with pixels: PixelBuffer) throws {
        uploads[texture.id] = pixels
    }

    func destroyTexture(_ texture: Texture) {
        uploads[texture.id] = nil
    }

    func render(_ frame: SpriteFrame, clearColor: Color) throws { }

    /// Pixel of an uploaded texture region at (x, y) relative to the region's top-left.
    func pixel(_ texture: Texture, _ x: Int, _ y: Int) -> Color? {
        uploads[texture.id].map { $0[Int(texture.region.minX) + x, Int(texture.region.minY) + y] }
    }
}

extension Color {
    static let yellow = Color(red: 1, green: 1, blue: 0)
}

@Suite struct SpriteKitAtlasTests {

    func document() throws -> AtlasDocument {
        try SpriteKitAtlas.parse(propertyList: Data(contentsOf: Fixtures.url("SpriteKit/sample.atlasc/sample.plist")))
    }

    @Test func parsesCompiledAtlas() throws {
        let page = try #require(try document().pages.first)
        #expect(page.imageName == "sample.1.png")
        let regions = Dictionary(uniqueKeysWithValues: page.regions.map { ($0.name, $0) })
        #expect(Set(regions.keys) == ["tall", "wide", "corner"])

        let tall = try #require(regions["tall"])
        #expect(tall.rotation == .clockwise)
        #expect(tall.sourceSize == [16, 64])
        #expect(tall.contentSize == [16, 64])

        // Content spans x 2..<10, y 4..<12 of a 32×32 image.
        let corner = try #require(regions["corner"])
        #expect(corner.sourceSize == [32, 32])
        #expect(corner.trimOrigin == [2, 4])
        #expect(regions["wide"]?.isUntransformed == true)
    }

    @Test func extractsRotatedAndTrimmedRegions() throws {
        let image = try PixelBuffer(png: Fixtures.bytes("SpriteKit/sample.atlasc/sample.1.png"))
        let regions = Dictionary(uniqueKeysWithValues: try document().pages[0].regions.map { ($0.name, $0) })

        let tall = try regions["tall"]!.extract(from: image)
        #expect(tall.width == 16 && tall.height == 64)
        #expect(tall[0, 0] == .green)
        #expect(tall[8, 10] == .red)
        #expect(tall[8, 40] == .blue)

        let corner = try regions["corner"]!.extract(from: image)
        #expect(corner.width == 32 && corner.height == 32)
        #expect(corner[2, 4] == .yellow && corner[9, 11] == .yellow)
        #expect(corner[1, 4] == .clear && corner[10, 12] == .clear)
    }

    @Test func loadsCompiledAtlas() async throws {
        let decoded = try await SpriteKitAtlas.decode(at: Fixtures.url("SpriteKit/sample.atlasc"))
        let backend = MockBackend()
        let atlases = try decoded.makeTextureAtlases(backend: backend)
        #expect(atlases.textureNames == ["corner", "tall", "wide"])
        let tall = try #require(atlases[texture: "tall"])
        #expect(tall.size == [16, 64])
        #expect(backend.pixel(tall, 0, 0) == .green)
        #expect(backend.pixel(tall, 8, 40) == .blue)
    }

    @Test func loadsSourceFolder() async throws {
        let decoded = try await SpriteKitAtlas.decode(at: Fixtures.url("SpriteKit/sample.atlas"))
        #expect(decoded.pages.isEmpty)
        let atlases = try decoded.makeTextureAtlases(backend: MockBackend(), filtering: .nearest)
        #expect(atlases.textureNames == ["corner", "tall", "wide"])
        #expect(atlases[texture: "wide"]?.size == [80, 40])
    }

    @Test func textureNamesStripExtensionAndScale() {
        #expect(SpriteKitAtlas.textureName("hero@2x.png") == "hero")
        #expect(SpriteKitAtlas.textureName("hero.png") == "hero")
        #expect(SpriteKitAtlas.parseRect("{{1, 41}, {16, 16}}") == Rect(x: 1, y: 41, width: 16, height: 16))
        #expect(SpriteKitAtlas.parseVector("{-2.5, 3}") == [-2.5, 3])
    }
}

@Suite struct TextAtlasTests {

    func document(_ name: String) throws -> AtlasDocument {
        try TextAtlas.parse(String(decoding: Data(contentsOf: Fixtures.url("LibGDX/\(name).atlas")), as: UTF8.self))
    }

    @Test func legacyAndCurrentFormatsAgree() throws {
        let legacy = try document("legacy")
        let current = try document("current")
        #expect(legacy == current)
        let page = try #require(legacy.pages.first)
        #expect(page.imageName == "page.png")
        #expect(page.filtering == .nearest)
        #expect(page.regions.map(\.name) == ["arrow", "trimmed", "walk_0", "walk_1"])
        #expect(page.regions[0].rotation == .counterClockwise)
        #expect(page.regions[0].frame == Rect(x: 2, y: 2, width: 16, height: 8))
        #expect(page.regions[1].trimOrigin == [3, 2])
        #expect(page.regions[1].sourceSize == [16, 12])
    }

    @Test func extractsCounterClockwiseRegions() throws {
        let image = try PixelBuffer(png: Fixtures.bytes("LibGDX/page.png"))
        let regions = try document("current").pages[0].regions

        let arrow = try regions[0].extract(from: image)
        #expect(arrow.width == 8 && arrow.height == 16)
        #expect(arrow[0, 0] == .green && arrow[1, 1] == .green)
        #expect(arrow[5, 3] == .red)
        #expect(arrow[5, 12] == .blue)

        let trimmed = try regions[1].extract(from: image)
        #expect(trimmed.width == 16 && trimmed.height == 12)
        #expect(trimmed[3, 2] == .yellow && trimmed[8, 5] == .yellow)
        #expect(trimmed[2, 2] == .clear && trimmed[3, 6] == .clear)
    }

    @Test func loadsAtlasFile() async throws {
        let decoded = try await TextAtlas.decode(at: Fixtures.url("LibGDX/legacy.atlas"))
        let backend = MockBackend()
        let atlases = try decoded.makeTextureAtlases(backend: backend)
        #expect(atlases.textureNames == ["arrow", "trimmed", "walk_0", "walk_1"])
        let walk = try #require(atlases[texture: "walk_1"])
        #expect(backend.pixel(walk, 0, 0) == .blue)
        #expect(backend.filters[walk.id] == .nearest)
    }

    @Test func rejectsEmptyInput() {
        #expect(throws: AtlasError.self) { try TextAtlas.parse("\n\n") }
    }
}
