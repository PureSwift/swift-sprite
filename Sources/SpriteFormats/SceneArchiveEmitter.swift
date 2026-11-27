import SpriteCore
import SpriteGraph

struct ArchiveEmitter: Sendable {
    let values: [String: Float]
    let count: Int
    let position: Vector2
    let range: Vector2
    let size: Vector2
    let acceleration: Vector2
    let color: Color
    let blend: BlendMode
    let alphaSequence: KeyframeSequence<Float>?
    let scaleSequence: KeyframeSequence<Float>?

    init(_ fields: [String: PropertyValue], graph: KeyedArchive) throws {
        for key in ["_particleAction", "_particleColorSequence", "_particleColorBlendFactorSequence",
                    "_particleRotationSequence", "_particleSpeedSequence", "_fieldInfluenceSequence"] {
            guard try graph.isNull(fields[key]) else { throw SceneArchiveError.unsupported("Emitter \(key)") }
        }
        for key in ["_startColorVarianceR", "_startColorVarianceG", "_startColorVarianceB", "_startColorVarianceA",
                    "_colorSpeedR", "_colorSpeedG", "_colorSpeedB", "_colorSpeedA", "_startColorBlendVariance",
                    "_colorBlendSpeed", "_startZPositionVariance", "_zPositionSpeed", "_emissionDistance",
                    "_emissionDistanceRange", "_fieldBitMask"] {
            guard try graph.number(fields[key], default: 0) == 0 else {
                throw SceneArchiveError.unsupported("Emitter \(key)")
            }
        }
        let defaults: [String: Float] = ["_birthrate": 0, "_lifetime": 1, "_lifetimeVariance": 0,
            "_emissionAngle": 0, "_emissionAngleVariance": 0, "_startSpeed": 0, "_startSpeedVariance": 0,
            "_startRotation": 0, "_startRotationVariance": 0, "_rotationSpeed": 0,
            "_startOpacity": 1, "_startOpacityVariance": 0, "_opacitySpeed": 0,
            "_startScale": 1, "_startScaleVariance": 0, "_scaleSpeed": 0,
            "_startZPosition": 0, "_startColorMix": 0]
        var numbers: [String: Float] = [:]
        for (key, fallback) in defaults {
            let value = try graph.number(fields[key], default: fallback)
            guard abs(value) <= 1_000_000 else { throw SceneArchiveError.invalid("Emitter value out of range: \(key)") }
            if key.hasSuffix("Variance") || ["_birthrate", "_lifetime", "_startScale"].contains(key), value < 0 {
                throw SceneArchiveError.invalid("Negative emitter range or rate: \(key)")
            }
            numbers[key] = value
        }
        values = numbers
        let rawCount = try graph.resolve(fields["_numParticlesToEmit"])
        if case .null = rawCount { count = 0 }
        else {
            guard case let .number(value) = rawCount, value.isFinite, value >= 0,
                  value <= 1_000_000, value.rounded() == value else {
                throw SceneArchiveError.invalid("Invalid particle emission count")
            }
            count = Int(value)
        }
        position = try graph.vector(fields["_startPosition"], default: .zero)
        range = try graph.vector(fields["_startPositionVariance"], default: .zero)
        size = try graph.vector(fields["_startSize"], default: .zero)
        acceleration = try graph.vector(fields["_acceleration"], default: .zero)
        guard range.x >= 0, range.y >= 0, size.x >= 0, size.y >= 0 else {
            throw SceneArchiveError.invalid("Invalid emitter size or position range")
        }
        color = try graph.color(fields, prefix: "_startColor")
        blend = try graph.blend(fields["_particleBlendMode"])
        alphaSequence = try Self.sequence(fields["_particleAlphaSequence"], graph: graph)
        scaleSequence = try Self.sequence(fields["_particleScaleSequence"], graph: graph)
    }

    @MainActor func makeEmitter(texture: Texture?) -> ParticleEmitter {
        let emitter = ParticleEmitter()
        emitter.particleTexture = texture
        emitter.particleSize = size
        emitter.particlePosition = position
        emitter.particlePositionRange = range
        emitter.acceleration = acceleration
        emitter.particleColor = color
        emitter.particleBlendMode = blend
        emitter.numParticlesToEmit = count
        emitter.particleAlphaSequence = alphaSequence
        emitter.particleScaleSequence = scaleSequence
        let properties: [(String, ReferenceWritableKeyPath<ParticleEmitter, Float>)] = [
            ("_birthrate", \.particleBirthRate), ("_lifetime", \.particleLifetime),
            ("_lifetimeVariance", \.particleLifetimeRange), ("_emissionAngle", \.emissionAngle),
            ("_emissionAngleVariance", \.emissionAngleRange), ("_startSpeed", \.particleSpeed),
            ("_startSpeedVariance", \.particleSpeedRange), ("_startRotation", \.particleRotation),
            ("_startRotationVariance", \.particleRotationRange), ("_rotationSpeed", \.particleRotationSpeed),
            ("_startOpacity", \.particleAlpha), ("_startOpacityVariance", \.particleAlphaRange),
            ("_opacitySpeed", \.particleAlphaSpeed), ("_startScale", \.particleScale),
            ("_startScaleVariance", \.particleScaleRange), ("_scaleSpeed", \.particleScaleSpeed),
            ("_startZPosition", \.particleZPosition), ("_startColorMix", \.particleColorBlendFactor)]
        for (key, path) in properties {
            if let value = values[key] { emitter[keyPath: path] = value }
        }
        return emitter
    }

    private static func sequence(_ value: PropertyValue?, graph: KeyedArchive) throws -> KeyframeSequence<Float>? {
        if try graph.isNull(value) { return nil }
        let fields = try graph.dictionary(value)
        guard try graph.className(fields) == "SKKeyframeSequence",
              try graph.number(fields["_interpolationMode"], default: 1) == 1,
              try graph.number(fields["_repeatMode"], default: 1) == 1 else {
            throw SceneArchiveError.unsupported("Emitter keyframes require linear interpolation and clamping")
        }
        let times = try graph.array(fields["_times"])
        let values = try graph.array(fields["_values"])
        guard !times.isEmpty, times.count <= 1024, times.count == values.count else {
            throw SceneArchiveError.invalid("Invalid emitter keyframe count")
        }
        var frames: [KeyframeSequence<Float>.Keyframe] = []
        for (time, value) in zip(times, values) {
            guard try !graph.isNull(time), try !graph.isNull(value) else {
                throw SceneArchiveError.invalid("Missing emitter keyframe value")
            }
            let t = try graph.number(time, default: 0)
            let v = try graph.number(value, default: 0)
            guard t >= 0, t <= 1, t > (frames.last?.time ?? -1), v >= 0, v <= 1_000_000 else {
                throw SceneArchiveError.invalid("Invalid emitter keyframe")
            }
            frames.append(.init(time: t, value: v))
        }
        return KeyframeSequence(frames)
    }
}
