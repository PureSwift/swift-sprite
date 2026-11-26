//
//  Softness.swift
//  SpritePhysics
//
//  Soft constraint formulation adapted from Box2D v3 (MIT License, Copyright 2023 Erin Catto).
//

/// Spring-damper coefficients turning a rigid constraint into a soft one.
///
/// A soft constraint corrects position error like a critically tuned spring instead
/// of Baumgarte stabilization, which keeps stacks stable without adding energy.
struct Softness {

    /// Fraction of the position error converted to velocity bias per second.
    var biasRate: Float

    /// Scales the constraint's effective mass.
    var massScale: Float

    /// Scales the accumulated impulse fed back into the solve.
    var impulseScale: Float

    /// Rigid constraint (no softness, no bias).
    static let rigid = Softness(biasRate: 0, massScale: 1, impulseScale: 0)

    init(biasRate: Float, massScale: Float, impulseScale: Float) {
        self.biasRate = biasRate
        self.massScale = massScale
        self.impulseScale = impulseScale
    }

    /// - Parameters:
    ///   - hertz: Stiffness as an oscillation frequency.
    ///   - dampingRatio: `1` is critically damped.
    ///   - h: Substep duration in seconds.
    init(hertz: Float, dampingRatio: Float, h: Float) {
        guard hertz > 0 else {
            self = .rigid
            return
        }
        let omega = 2 * Float.pi * hertz
        let a1 = 2 * dampingRatio + h * omega
        let a2 = h * omega * a1
        let a3 = 1 / (1 + a2)
        self.init(biasRate: omega / a1, massScale: a2 * a3, impulseScale: a3)
    }
}

/// Per-step solver parameters shared by contacts and joints.
struct SolverContext {

    /// Substep duration and its inverse.
    var h: Float
    var invH: Float

    /// Softness for contacts between two movable bodies.
    var contactSoftness: Softness

    /// Stiffer softness for contacts against static bodies.
    var staticSoftness: Softness

    var jointSoftness: Softness

    /// Maximum velocity used to push overlapping bodies apart.
    var maxBiasVelocity: Float

    var restitutionThreshold: Float
}
