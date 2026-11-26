//
//  ParticleTests.swift
//  SpriteGraphTests
//

import Testing
import SpriteCore
@testable import SpriteGraph

@MainActor @Suite struct ParticleTests {

    func makeEmitter() -> ParticleEmitter {
        let emitter = ParticleEmitter()
        emitter.particleBirthRate = 10
        emitter.particleLifetime = 100
        return emitter
    }

    func step(_ emitter: ParticleEmitter, seconds: Double, steps: Int = 60) {
        for _ in 0 ..< steps {
            emitter.evaluateActions(seconds: seconds / Double(steps))
        }
    }

    @Test func birthRateControlsEmission() {
        let emitter = makeEmitter()
        step(emitter, seconds: 1)
        #expect(emitter.particleCount == 10)
        #expect(emitter.emittedCount == 10)
    }

    @Test func finiteEmittersStop() {
        let emitter = makeEmitter()
        emitter.particleBirthRate = 100
        emitter.numParticlesToEmit = 25
        step(emitter, seconds: 1)
        #expect(emitter.particleCount == 25)
        #expect(emitter.isEmissionFinished)
    }

    @Test func particlesExpire() {
        let emitter = makeEmitter()
        emitter.particleLifetime = 0.5
        step(emitter, seconds: 2)
        // At steady state about birthRate × lifetime particles are alive.
        #expect((4 ... 6).contains(emitter.particleCount))
        emitter.particleBirthRate = 0
        step(emitter, seconds: 1)
        #expect(emitter.particleCount == 0)
    }

    @Test func motionIntegratesVelocityAndAcceleration() {
        let emitter = ParticleEmitter()
        emitter.particleBirthRate = 1000
        emitter.numParticlesToEmit = 1
        emitter.particleLifetime = 10
        emitter.particleSpeed = 100
        emitter.emissionAngle = .pi / 2
        emitter.acceleration = [10, 0]
        emitter.particleAlphaSpeed = -0.5
        step(emitter, seconds: 1.0 / 60.0, steps: 1)
        #expect(emitter.particleCount == 1)
        step(emitter, seconds: 1, steps: 100)
        let position = emitter.particles.position[0]
        // Born during the first step, then integrated for one second.
        #expect(approx(position.y, 100, tolerance: 0.5))
        #expect(approx(position.x, 5, tolerance: 0.5))
        #expect(approx(emitter.particles.alpha[0], 0.5, tolerance: 0.02))
    }

    @Test func rangesStayWithinBounds() {
        let emitter = makeEmitter()
        emitter.particleBirthRate = 1000
        emitter.particleSpeed = 100
        emitter.particleSpeedRange = 20
        emitter.particlePositionRange = [10, 0]
        step(emitter, seconds: 1.0 / 60.0, steps: 1)
        #expect(emitter.particleCount > 10)
        for velocity in emitter.particles.velocity {
            #expect((90 - 1e-3 ... 110 + 1e-3).contains(velocity.x))
        }
    }

    @Test func birthRateSequenceRampsEmission() {
        let emitter = makeEmitter()
        emitter.particleBirthRate = 100
        emitter.particleBirthRateSequence = KeyframeSequence([(0, 0), (0.5, 0), (0.5001, 1)])
        step(emitter, seconds: 0.5, steps: 30)
        #expect(emitter.particleCount == 0)
        step(emitter, seconds: 0.5, steps: 30)
        #expect((45 ... 50).contains(emitter.particleCount))
    }

    @Test func keyframeSequencesInterpolate() {
        let sequence = KeyframeSequence<Float>([(1, 10), (0, 0)])
        #expect(sequence.value(at: -1) == 0)
        #expect(sequence.value(at: 0.25) == 2.5)
        #expect(sequence.value(at: 2) == 10)
        let colors = KeyframeSequence<Color>([(0, .black), (1, .white)])
        #expect(colors.value(at: 0.5) == Color(white: 0.5))
        let points = KeyframeSequence<Vector2>([(0, [0, 0]), (1, [10, 20])])
        #expect(points.value(at: 0.5) == [5, 10])
    }

    @Test func renderingAppliesSequences() {
        let scene = Scene(size: [100, 100])
        let emitter = makeEmitter()
        emitter.particleBirthRate = 600
        emitter.numParticlesToEmit = 4
        emitter.particleSize = [2, 2]
        emitter.particleColorSequence = KeyframeSequence([(0, .red), (1, .blue)])
        emitter.particleAlphaSequence = KeyframeSequence([(0, 0.5), (1, 0.5)])
        emitter.particleBlendMode = .add
        scene.addChild(emitter)
        scene.advance(by: .milliseconds(10))
        let frame = scene.makeFrame(viewportSize: [100, 100])
        #expect(frame.vertices.count == 16)
        #expect(frame.batches.map(\.blendMode) == [.add])
        #expect(frame.vertices.allSatisfy { $0.color.alpha == 0.5 && $0.color.red > 0.9 })
    }

    @Test func targetNodeKeepsParticlesBehind() {
        let scene = Scene(size: [400, 400])
        let emitter = makeEmitter()
        emitter.particleBirthRate = 1000
        emitter.numParticlesToEmit = 1
        emitter.targetNode = scene
        emitter.position = [100, 100]
        scene.addChild(emitter)
        scene.advance(by: .milliseconds(16))
        // The particle spawned in scene space and stays put while the emitter moves.
        #expect(approx(emitter.particles.position[0], [100, 100]))
        emitter.position = [300, 100]
        scene.advance(by: .milliseconds(16))
        #expect(approx(emitter.particles.position[0], [100, 100]))
        let frame = scene.makeFrame(viewportSize: [400, 400])
        let center = frame.vertices.prefix(4).reduce(Vector2.zero) { $0 + $1.position } / 4
        // Viewport flips Y: scene (100, 100) is pixel (100, 300).
        #expect(approx(center, [100, 300]))
    }

    @Test func resetAndPrewarm() {
        let emitter = makeEmitter()
        emitter.advanceSimulationTime(.seconds(1))
        #expect((9 ... 11).contains(emitter.particleCount))
        emitter.resetSimulation()
        #expect(emitter.particleCount == 0 && emitter.elapsedTime == 0 && emitter.emittedCount == 0)
    }

    @Test func pausedEmittersFreeze() {
        let emitter = makeEmitter()
        emitter.isPaused = true
        step(emitter, seconds: 1)
        #expect(emitter.particleCount == 0)
    }
}
