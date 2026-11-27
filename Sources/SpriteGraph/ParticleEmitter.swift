//
//  ParticleEmitter.swift
//  SpriteGraph
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import SpriteCore

/// Node that emits and renders textured particles (like `SKEmitterNode`).
///
/// Ranges are full widths centered on the base value: `particleSpeed: 100,
/// particleSpeedRange: 20` yields speeds in `90...110`.
open class ParticleEmitter: Node {

    // MARK: - Emission

    public var particleTexture: Texture?

    /// Particle size before scaling; defaults to the texture size (or 8×8 without a texture).
    public var particleSize: Vector2?

    /// Particles emitted per second.
    public var particleBirthRate: Float = 0

    /// Multiplier on the birth rate over emitter time in seconds (an emission ramp).
    public var particleBirthRateSequence: KeyframeSequence<Float>?

    /// Total particles to emit before stopping; `0` emits forever.
    public var numParticlesToEmit = 0

    /// Upper bound on live particles.
    public var maxParticleCount = 10_000

    /// Seconds each particle lives.
    public var particleLifetime: Float = 1
    public var particleLifetimeRange: Float = 0

    /// Center of the spawn area in the emitter's local coordinates.
    public var particlePosition: Vector2 = .zero

    /// Spawn area around ``particlePosition``.
    public var particlePositionRange: Vector2 = .zero

    // MARK: - Motion

    /// Direction of emission in radians (counter-clockwise from +x).
    public var emissionAngle: Float = 0
    public var emissionAngleRange: Float = 0

    public var particleSpeed: Float = 0
    public var particleSpeedRange: Float = 0

    public var acceleration: Vector2 = .zero

    public var xAcceleration: Float {
        get { acceleration.x }
        set { acceleration.x = newValue }
    }

    public var yAcceleration: Float {
        get { acceleration.y }
        set { acceleration.y = newValue }
    }

    public var particleRotation: Float = 0
    public var particleRotationRange: Float = 0
    public var particleRotationSpeed: Float = 0

    // MARK: - Appearance

    public var particleColor: Color = .white

    /// Mixes white texture tint with particle color. Defaults to full tint for existing emitters.
    public var particleColorBlendFactor: Float = 1

    /// Color over normalized particle age (`0...1`), overriding ``particleColor``.
    public var particleColorSequence: KeyframeSequence<Color>?

    public var particleAlpha: Float = 1
    public var particleAlphaRange: Float = 0
    public var particleAlphaSpeed: Float = 0

    /// Alpha over normalized particle age, overriding the alpha properties.
    public var particleAlphaSequence: KeyframeSequence<Float>?

    public var particleScale: Float = 1
    public var particleScaleRange: Float = 0
    public var particleScaleSpeed: Float = 0

    /// Scale over normalized particle age, overriding the scale properties.
    public var particleScaleSequence: KeyframeSequence<Float>?

    public var particleBlendMode: BlendMode = .alpha

    /// Z offset of particles relative to the emitter.
    public var particleZPosition: Float = 0

    /// Node whose coordinate space particles live in once emitted, so they trail
    /// behind a moving emitter. `nil` keeps particles in the emitter's space.
    public weak var targetNode: Node?

    // MARK: - State

    var particles = ParticleBuffer()

    /// Seconds since emission started.
    public private(set) var elapsedTime: Float = 0

    public private(set) var emittedCount = 0

    private var pendingBirths: Float = 0

    public override init() {
        super.init()
    }

    /// Number of live particles.
    public var particleCount: Int {
        particles.count
    }

    /// Whether a finite emitter has emitted all of its particles.
    public var isEmissionFinished: Bool {
        numParticlesToEmit > 0 && emittedCount >= numParticlesToEmit
    }

    /// Removes all particles and restarts emission.
    public func resetSimulation() {
        particles.removeAll()
        elapsedTime = 0
        emittedCount = 0
        pendingBirths = 0
    }

    /// Advances the simulation, e.g. to pre-warm an emitter before it is shown.
    public func advanceSimulationTime(_ duration: Duration, step: Duration = .milliseconds(16)) {
        let (seconds, attoseconds) = duration.components
        var remaining = Double(seconds) + Double(attoseconds) * 1e-18
        let stepSeconds = max(step.seconds, 1e-3)
        while remaining > 0 {
            let dt = min(remaining, stepSeconds)
            simulate(seconds: dt)
            remaining -= dt
        }
    }

    // MARK: - Simulation

    override func simulate(seconds: Double) {
        let dt = Float(seconds)
        guard dt > 0 else { return }
        elapsedTime += dt
        particles.update(dt: dt, acceleration: acceleration)
        emit(dt)
    }

    private func emit(_ dt: Float) {
        guard particleBirthRate > 0, !isEmissionFinished else { return }
        let rate = particleBirthRate * (particleBirthRateSequence?.value(at: elapsedTime) ?? 1)
        pendingBirths += max(rate, 0) * dt
        var births = Int(pendingBirths)
        pendingBirths -= Float(births)
        if numParticlesToEmit > 0 {
            births = min(births, numParticlesToEmit - emittedCount)
        }
        births = min(births, maxParticleCount - particles.count)
        guard births > 0 else { return }

        // Emitter-to-target transform for particles living in another node's space.
        let toTarget: Matrix3x3 = targetNode.flatMap { target in
            target.worldMatrix.inverse.map { $0 * worldMatrix }
        } ?? .identity

        particles.reserveCapacity(particles.count + births)
        for k in 0 ..< births {
            let local = Vector2(
                Self.spread(particlePosition.x, particlePositionRange.x),
                Self.spread(particlePosition.y, particlePositionRange.y)
            )
            let angle = Self.spread(emissionAngle, emissionAngleRange)
            let speed = Self.spread(particleSpeed, particleSpeedRange)
            let velocity = toTarget.transform(vector: Vector2(cosf(angle), sinf(angle)) * speed)
            // Stagger births across the frame so bursts do not clump.
            let age = dt * Float(k) / Float(births)
            particles.append(
                position: toTarget.transform(point: local) + velocity * age,
                velocity: velocity,
                age: age,
                lifetime: max(Self.spread(particleLifetime, particleLifetimeRange), .ulpOfOne),
                rotation: Self.spread(particleRotation, particleRotationRange),
                rotationSpeed: particleRotationSpeed,
                scale: Self.spread(particleScale, particleScaleRange),
                scaleSpeed: particleScaleSpeed,
                alpha: Self.spread(particleAlpha, particleAlphaRange),
                alphaSpeed: particleAlphaSpeed
            )
            emittedCount += 1
        }
    }

    /// `base` plus a uniform random offset within `±range / 2`.
    static func spread(_ base: Float, _ range: Float) -> Float {
        range > 0 ? base + Float.random(in: -range / 2 ... range / 2) : base
    }

    // MARK: - Rendering

    open override func draw(in context: inout RenderContext) {
        guard particles.count > 0 else { return }
        let size = particleSize ?? particleTexture?.size ?? Vector2(8, 8)
        let texture = particleTexture ?? .none
        // Particles in a target's space are drawn relative to that node.
        let base: Matrix3x3 = targetNode.flatMap { target in
            context.transform.inverse.map { $0 * target.worldMatrix }
        } ?? .identity

        let emitterZ = context.zPosition
        context.zPosition = emitterZ + particleZPosition
        defer { context.zPosition = emitterZ }

        for i in 0 ..< particles.count {
            let t = particles.age[i] / particles.lifetime[i]
            var color = particleColorSequence?.value(at: t) ?? particleColor
            color = Color.white.mix(with: color, fraction: min(max(particleColorBlendFactor, 0), 1))
            color.alpha *= max(particleAlphaSequence?.value(at: t) ?? particles.alpha[i], 0)
            let scale = particleScaleSequence?.value(at: t) ?? particles.scale[i]
            guard color.alpha > 0, scale > 0 else { continue }
            let transform = Transform2D(position: particles.position[i], rotation: particles.rotation[i], scale: Vector2(repeating: scale))
            context.submit(
                texture: texture,
                size: size,
                offset: base * transform.matrix,
                color: color,
                blendMode: particleBlendMode
            )
        }
    }
}
