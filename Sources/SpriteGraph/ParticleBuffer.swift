//
//  ParticleBuffer.swift
//  SpriteGraph
//

import SpriteCore

/// Structure-of-arrays particle storage: each attribute is a contiguous array.
///
/// Dead particles are swap-removed, so indices are not stable across updates.
struct ParticleBuffer {

    var position: [Vector2] = []
    var velocity: [Vector2] = []
    var age: [Float] = []
    var lifetime: [Float] = []
    var rotation: [Float] = []
    var rotationSpeed: [Float] = []
    var scale: [Float] = []
    var scaleSpeed: [Float] = []
    var alpha: [Float] = []
    var alphaSpeed: [Float] = []

    var count: Int {
        position.count
    }

    mutating func reserveCapacity(_ capacity: Int) {
        position.reserveCapacity(capacity)
        velocity.reserveCapacity(capacity)
        age.reserveCapacity(capacity)
        lifetime.reserveCapacity(capacity)
        rotation.reserveCapacity(capacity)
        rotationSpeed.reserveCapacity(capacity)
        scale.reserveCapacity(capacity)
        scaleSpeed.reserveCapacity(capacity)
        alpha.reserveCapacity(capacity)
        alphaSpeed.reserveCapacity(capacity)
    }

    mutating func append(
        position: Vector2,
        velocity: Vector2,
        age: Float,
        lifetime: Float,
        rotation: Float,
        rotationSpeed: Float,
        scale: Float,
        scaleSpeed: Float,
        alpha: Float,
        alphaSpeed: Float
    ) {
        self.position.append(position)
        self.velocity.append(velocity)
        self.age.append(age)
        self.lifetime.append(lifetime)
        self.rotation.append(rotation)
        self.rotationSpeed.append(rotationSpeed)
        self.scale.append(scale)
        self.scaleSpeed.append(scaleSpeed)
        self.alpha.append(alpha)
        self.alphaSpeed.append(alphaSpeed)
    }

    /// Removes a particle by moving the last particle into its slot.
    mutating func swapRemove(at index: Int) {
        position.swapAt(index, position.count - 1); position.removeLast()
        velocity.swapAt(index, velocity.count - 1); velocity.removeLast()
        age.swapAt(index, age.count - 1); age.removeLast()
        lifetime.swapAt(index, lifetime.count - 1); lifetime.removeLast()
        rotation.swapAt(index, rotation.count - 1); rotation.removeLast()
        rotationSpeed.swapAt(index, rotationSpeed.count - 1); rotationSpeed.removeLast()
        scale.swapAt(index, scale.count - 1); scale.removeLast()
        scaleSpeed.swapAt(index, scaleSpeed.count - 1); scaleSpeed.removeLast()
        alpha.swapAt(index, alpha.count - 1); alpha.removeLast()
        alphaSpeed.swapAt(index, alphaSpeed.count - 1); alphaSpeed.removeLast()
    }

    mutating func removeAll() {
        self = ParticleBuffer()
    }

    /// Ages and integrates all particles, removing those past their lifetime.
    mutating func update(dt: Float, acceleration: Vector2) {
        var i = 0
        while i < count {
            age[i] += dt
            if age[i] >= lifetime[i] {
                swapRemove(at: i)
                continue
            }
            velocity[i] += acceleration * dt
            position[i] += velocity[i] * dt
            rotation[i] += rotationSpeed[i] * dt
            scale[i] += scaleSpeed[i] * dt
            alpha[i] += alphaSpeed[i] * dt
            i += 1
        }
    }
}
