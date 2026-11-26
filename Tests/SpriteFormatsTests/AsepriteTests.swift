//
//  AsepriteTests.swift
//  SpriteFormatsTests
//

import Foundation
import Testing
import SpriteCore
import SpriteGraph
@testable import SpriteFormats

private func abs(_ duration: Duration) -> Duration {
    duration < .zero ? .zero - duration : duration
}

@Suite struct AsepriteTests {

    @Test(arguments: ["hero-hash", "hero-array"])
    func parsesSheet(_ name: String) throws {
        let sheet = try AsepriteSheet(json: Data(contentsOf: Fixtures.url("Aseprite/\(name).json")))
        #expect(sheet.imageName == "hero.png")
        // Hash keys are unordered; frames are ordered by their trailing number.
        #expect(sheet.frames.map(\.name) == ["hero 0.aseprite", "hero 1.aseprite", "hero 2.aseprite"])
        #expect(sheet.frames.map(\.duration) == [.milliseconds(100), .milliseconds(150), .milliseconds(200)])
        #expect(sheet.frames[2].region.trimOrigin == [2, 2])
        #expect(sheet.frames[2].region.sourceSize == [8, 8])
    }

    @Test func tagDirections() throws {
        let sheet = try AsepriteSheet(json: Data(contentsOf: Fixtures.url("Aseprite/hero-array.json")))
        let walk = try #require(sheet.tag(named: "walk"))
        #expect(walk.direction == .pingpong)
        #expect(sheet.frameIndices(for: walk) == [0, 1, 2, 1])
        let blink = try #require(sheet.tag(named: "blink"))
        #expect(sheet.frameIndices(for: blink) == [2, 1])
        #expect(blink.repeatCount == 3)
        var reversePingPong = walk
        reversePingPong.direction = .pingpongReverse
        #expect(sheet.frameIndices(for: reversePingPong) == [2, 1, 0, 1])
    }

    @Test func slicesProvideNinePatch() throws {
        let sheet = try AsepriteSheet(json: Data(contentsOf: Fixtures.url("Aseprite/hero-hash.json")))
        #expect(sheet.centerRect(slice: "panel") == Rect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        #expect(sheet.slices.first?.keys.first?.pivot == [4, 8])
        #expect(sheet.centerRect(slice: "missing") == nil)
    }

    @MainActor @Test func animationPlaysFramesWithDurations() async throws {
        let (sheet, decoded) = try await AsepriteSheet.decode(at: Fixtures.url("Aseprite/hero-hash.json"))
        let backend = MockBackend()
        let atlas = try #require(try decoded.makeTextureAtlases(backend: backend).first)

        // Trimmed frames are restored to their full size.
        let last = try #require(atlas["hero 2.aseprite"])
        #expect(last.size == [8, 8])
        #expect(backend.pixel(last, 0, 0) == .clear)
        #expect(backend.pixel(last, 2, 2) == .blue)
        #expect(backend.filters[last.id] == .nearest)

        let walk = try #require(sheet.animation(tag: "walk", atlas: atlas))
        #expect(abs(walk.duration! - .milliseconds(600)) < .microseconds(1))
        let blink = try #require(sheet.animation(tag: "blink", atlas: atlas))
        #expect(abs(blink.duration! - .milliseconds(1050)) < .microseconds(1))

        let sprite = Sprite(texture: atlas["hero 0.aseprite"]!)
        let scene = Scene(size: [10, 10])
        scene.addChild(sprite)
        sprite.run(walk)
        scene.advance(by: .milliseconds(120))
        #expect(sprite.texture == atlas["hero 1.aseprite"])
        scene.advance(by: .milliseconds(200))
        #expect(sprite.texture == atlas["hero 2.aseprite"])
    }
}
