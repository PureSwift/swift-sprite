import Foundation
import Testing
import SpriteCore
import SpriteGraph
@testable import SpriteFormats

@Suite struct SceneArchiveEmitterTests {
    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresAndSimulatesNativeEmitters(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/emitters." + format)))
        var requests = 0
        let scene = try #require(archive.makeNode(textureResolver: { reference in
            requests += 1
            #expect(reference.imageName == "../SpriteKit/sample.atlas/wide.png")
            return Texture(id: TextureID(rawValue: 8), textureSize: [80, 40])
        }) as? Scene)
        let emitter = try #require(scene.children.first as? ParticleEmitter)
        #expect(requests == 1)
        #expect(emitter.targetNode === scene)
        #expect(emitter.position == [20, 30] && emitter.particlePosition == [3, 4])
        #expect(emitter.particlePositionRange == [10, 20] && emitter.particleSize == [10, 12])
        #expect(emitter.particleBirthRate == 8 && emitter.numParticlesToEmit == 12)
        #expect(emitter.particleLifetime == 4)
        #expect(emitter.particleSpeed == 30 && emitter.particleSpeedRange == 4)
        #expect(emitter.emissionAngle == 0.5 && emitter.emissionAngleRange == 0.2)
        #expect(emitter.acceleration == [2, -3])
        #expect(emitter.particleRotation == 0.3 && emitter.particleRotationRange == 0.1)
        #expect(emitter.particleRotationSpeed == 0.4)
        #expect(emitter.particleScale == 1.5 && emitter.particleScaleRange == 0.5 && emitter.particleScaleSpeed == -0.2)
        #expect(emitter.particleAlpha == 0.7 && emitter.particleAlphaRange == 0.2 && emitter.particleAlphaSpeed == -0.1)
        #expect(emitter.particleColorBlendFactor == 0.5 && emitter.particleBlendMode == .add)
        #expect(emitter.particleZPosition == 2)
        #expect(emitter.particleAlphaSequence?.value(at: 0.5) == 0.5)
        #expect(emitter.particleScaleSequence?.value(at: 0.5) == 1.5)
        #expect(emitter.particleCount == 0)
        scene.advance(by: .seconds(0.5))
        #expect(emitter.particleCount == 4)
        #expect(!scene.makeFrame(viewportSize: [320, 240]).vertices.isEmpty)
        scene.advance(by: .seconds(1))
        #expect(emitter.emittedCount == 12 && emitter.isEmissionFinished)
        scene.advance(by: .seconds(5))
        #expect(emitter.particleCount == 0)
        let other = try #require(archive.makeNode(textureResolver: { _ in
            Texture(id: TextureID(rawValue: 9), textureSize: [80, 40])
        }) as? Scene)
        let fresh = try #require(other.children.first as? ParticleEmitter)
        #expect(fresh.emittedCount == 0 && fresh.targetNode === other)
    }

    @MainActor @Test func missingTextureFails() throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/emitters.sks")))
        #expect(throws: SceneArchiveError.missingTexture("../SpriteKit/sample.atlas/wide.png")) {
            try archive.makeNode()
        }
    }

    private func graph() throws -> KeyedArchive {
        try KeyedArchive(ArchivePropertyList.decode(Data(contentsOf: Fixtures.url("SceneArchives/emitters.xml"))))
    }

    @Test func rejectsUnsupportedEmitterFeatures() throws {
        let graph = try graph()
        for key in ["_particleAction", "_particleColorSequence", "_particleSpeedSequence"] {
            #expect(throws: SceneArchiveError.self) { try ArchiveEmitter([key: .string("unsupported")], graph: graph) }
        }
        for key in ["_colorSpeedR", "_startColorVarianceA", "_fieldBitMask", "_zPositionSpeed"] {
            #expect(throws: SceneArchiveError.self) { try ArchiveEmitter([key: .number(1)], graph: graph) }
        }
    }

    @Test func rejectsMalformedEmitterValues() throws {
        let graph = try graph()
        for fields: [String: PropertyValue] in [["_birthrate": .number(-1)], ["_birthrate": .number(.infinity)],
            ["_numParticlesToEmit": .number(1.5)], ["_numParticlesToEmit": .number(-1)],
            ["_startSpeedVariance": .number(-1)], ["_startSize": .string("{-1, 3}")],
            ["_startPositionVariance": .string("{nan, 0}")]] {
            #expect(throws: SceneArchiveError.self) { try ArchiveEmitter(fields, graph: graph) }
        }
    }

    @Test func rejectsMalformedAndUnsupportedKeyframes() throws {
        let graph = try graph()
        let id = try #require(graph.objects.firstIndex { $0.dictionary?["$classname"]?.string == "SKKeyframeSequence" })
        let base: [String: PropertyValue] = ["$class": .uid(id), "_times": .array([.number(0), .number(1)]),
            "_values": .array([.number(1), .number(0)])]
        for changes: [String: PropertyValue] in [["_times": .array([])], ["_values": .array([])],
            ["_times": .array([.number(0.5), .number(0.5)])], ["_interpolationMode": .number(2)],
            ["_repeatMode": .number(2)], ["_values": .array([.number(.nan), .number(0)])]] {
            let sequence = base.merging(changes) { _, new in new }
            #expect(throws: SceneArchiveError.self) {
                try ArchiveEmitter(["_particleAlphaSequence": .dictionary(sequence)], graph: graph)
            }
        }
    }

    @MainActor @Test func standaloneEmitterAndInvalidTarget() throws {
        func data(target: Int?) throws -> Data {
            var root: [String: Any] = ["$class": ["CF$UID": 2], "_birthrate": 2, "_lifetime": 5,
                "_startSize": "{4, 4}"]
            if let target { root["_target"] = ["CF$UID": target] }
            return try PropertyListSerialization.data(fromPropertyList: [
                "$archiver": "NSKeyedArchiver", "$version": 100_000,
                "$top": ["root": ["CF$UID": 1]],
                "$objects": ["$null", root, ["$classname": "SKEmitterNode"], ["$class": ["CF$UID": 2]]]
            ], format: .xml, options: 0)
        }
        let emitter = try #require(SpriteKitSceneArchive.decode(data(target: nil)).makeNode() as? ParticleEmitter)
        emitter.advanceSimulationTime(.seconds(0.5))
        #expect(emitter.emittedCount == 1)
        #expect(emitter.targetNode == nil)
        for target in [3, 999] {
            let archive = try data(target: target)
            #expect(throws: SceneArchiveError.self) { try SpriteKitSceneArchive.decode(archive) }
        }
    }
}
