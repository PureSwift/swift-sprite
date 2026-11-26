//
//  SpriteBatcherTests.swift
//  SpriteCoreTests
//

import Testing
@testable import SpriteCore

@Suite struct SpriteBatcherTests {

    let textureA = Texture(id: TextureID(rawValue: 1), textureSize: Vector2(16, 16))
    let textureB = Texture(id: TextureID(rawValue: 2), textureSize: Vector2(16, 16))

    @Test func quadGeometry() {
        var batcher = SpriteBatcher()
        let texture = textureA.subtexture(in: Rect(x: 0, y: 0, width: 8, height: 4))
        batcher.submit(SpriteQuad(
            texture: texture,
            transform: .translation(Vector2(100, 50)),
            anchorPoint: Vector2(0.5, 0.5),
            color: .red
        ))
        let frame = batcher.makeFrame()
        #expect(batcher.count == 0)
        #expect(frame.indices == [0, 1, 2, 0, 2, 3])
        #expect(frame.vertices.map(\.position) == [
            Vector2(96, 48), Vector2(104, 48), Vector2(104, 52), Vector2(96, 52),
        ])
        // Bottom of the quad samples the bottom of the region (v = 0.25).
        #expect(frame.vertices.map(\.texCoord) == [
            Vector2(0, 0.25), Vector2(0.5, 0.25), Vector2(0.5, 0), Vector2(0, 0),
        ])
        #expect(frame.vertices.allSatisfy { $0.color == .red })
        #expect(frame.batches == [DrawBatch(texture: textureA.id, blendMode: .alpha, indexRange: 0 ..< 6)])
    }

    @Test func anchorPointOffsetsQuad() {
        var batcher = SpriteBatcher()
        batcher.submit(SpriteQuad(size: Vector2(10, 10), anchorPoint: .zero))
        let frame = batcher.makeFrame()
        #expect(frame.vertices.first?.position == .zero)
        #expect(frame.vertices[2].position == Vector2(10, 10))
        #expect(frame.batches.first?.texture == TextureID.none)
    }

    @Test func viewTransformIsApplied() {
        var batcher = SpriteBatcher()
        batcher.submit(SpriteQuad(size: Vector2(2, 2), anchorPoint: .zero))
        let frame = batcher.makeFrame(viewTransform: .viewport(size: Vector2(100, 100)))
        #expect(frame.vertices[0].position == Vector2(0, 100))
        #expect(frame.vertices[2].position == Vector2(2, 98))
    }

    @Test func sortsByZPreservingSubmissionOrder() {
        var batcher = SpriteBatcher()
        batcher.submit(SpriteQuad(texture: textureA, color: .red, zPosition: 1))
        batcher.submit(SpriteQuad(texture: textureB, color: .green, zPosition: 0))
        batcher.submit(SpriteQuad(texture: textureA, color: .blue, zPosition: 0))
        let frame = batcher.makeFrame()
        let colors = stride(from: 0, to: frame.vertices.count, by: 4).map { frame.vertices[$0].color }
        #expect(colors == [.green, .blue, .red])
        // B, then A (z 0), then A (z 1) merges with the previous A batch.
        #expect(frame.batches.map(\.texture) == [textureB.id, textureA.id])
        #expect(frame.batches.map(\.indexRange) == [0 ..< 6, 6 ..< 18])
    }

    @Test func textureGroupingReducesBatches() {
        func build(_ mode: SpriteBatcher.SortMode) -> SpriteFrame {
            var batcher = SpriteBatcher(sortMode: mode)
            for i in 0 ..< 10 {
                batcher.submit(SpriteQuad(texture: i.isMultiple(of: 2) ? textureA : textureB))
            }
            return batcher.makeFrame()
        }
        #expect(build(.preserveOrder).batches.count == 10)
        let grouped = build(.textureGrouped)
        #expect(grouped.batches.count == 2)
        #expect(grouped.batches.map(\.indexRange.count) == [30, 30])
    }

    @Test func blendModeBreaksBatches() {
        var batcher = SpriteBatcher()
        batcher.submit(SpriteQuad(texture: textureA))
        batcher.submit(SpriteQuad(texture: textureA, blendMode: .add))
        batcher.submit(SpriteQuad(texture: textureA, blendMode: .add))
        let frame = batcher.makeFrame()
        #expect(frame.batches.map(\.blendMode) == [.alpha, .add])
        #expect(frame.batches.map(\.indexRange) == [0 ..< 6, 6 ..< 18])
    }

    @Test func shaderBreaksBatches() {
        var batcher = SpriteBatcher()
        batcher.submit(SpriteQuad(texture: textureA))
        batcher.submit(SpriteQuad(texture: textureA, shader: .distanceField(smoothing: 0.1)))
        let frame = batcher.makeFrame()
        #expect(frame.batches.map(\.shader) == [.standard, .distanceField(smoothing: 0.1)])
    }

    @Test func backendReceivesFrame() throws {
        let backend = MockBackend()
        var batcher = SpriteBatcher()
        batcher.submit(SpriteQuad(size: Vector2(4, 4)))
        try backend.render(batcher.makeFrame(), clearColor: .black)
        #expect(backend.renderedFrames.count == 1)
        #expect(backend.renderedFrames[0].vertices.count == 4)
    }
}
