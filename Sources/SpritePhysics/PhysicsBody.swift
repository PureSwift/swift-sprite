//
//  PhysicsBody.swift
//  SpritePhysics
//

import SpriteCore

/// Rigid body simulated by a ``PhysicsWorld``.
///
/// ``position`` and ``rotation`` describe the body's origin (the origin of its
/// ``shape``); velocities are those of the center of mass.
public final class PhysicsBody {

    // MARK: - Shape & mass

    public let shape: PhysicsShape

    let parts: [ConvexPart]

    /// Mass per unit area. Setting ``mass`` adjusts density.
    public var density: Float = 1 {
        didSet { updateMass() }
    }

    public var mass: Float {
        get { massValue }
        set {
            let area = self.area
            if area > 0 { density = newValue / area }
        }
    }

    public let area: Float

    /// Rotational inertia about the center of mass.
    public private(set) var inertia: Float = 0

    /// Center of mass in local coordinates.
    public private(set) var localCenter: Vector2 = .zero

    private var massValue: Float = 0

    // MARK: - State

    public var position: Vector2

    /// Rotation in radians, counter-clockwise.
    public var rotation: Float

    /// Linear velocity of the center of mass.
    public var velocity: Vector2 = .zero

    public var angularVelocity: Float = 0

    var force: Vector2 = .zero

    var torque: Float = 0

    // MARK: - Material

    public var friction: Float = 0.2

    /// Bounciness in `0...1`.
    public var restitution: Float = 0.2

    public var linearDamping: Float = 0.1

    public var angularDamping: Float = 0.1

    // MARK: - Behavior

    /// Dynamic bodies respond to forces and collisions; others act as immovable
    /// obstacles that can still be repositioned directly.
    public var isDynamic: Bool

    public var affectedByGravity = true

    public var allowsRotation = true

    /// Scales world gravity for this body.
    public var gravityScale: Float = 1

    // MARK: - Filtering

    /// Categories this body belongs to.
    public var categoryBitMask: PhysicsCategory = .all

    /// Categories that can push this body in a collision.
    public var collisionBitMask: PhysicsCategory = .all

    /// Categories whose contacts with this body are reported.
    public var contactTestBitMask: PhysicsCategory = .none

    // MARK: - Ownership

    /// Object represented by this body, such as a scene node.
    public weak var owner: AnyObject?

    public internal(set) weak var world: PhysicsWorld?

    // MARK: - Initialization

    public init(shape: PhysicsShape, position: Vector2 = .zero, rotation: Float = 0) {
        self.shape = shape
        self.parts = shape.parts
        self.position = position
        self.rotation = rotation
        self.area = parts.reduce(0) { $0 + $1.area }
        // Shapes without area (edges) cannot be simulated dynamically.
        self.isDynamic = area > 0
        updateMass()
    }

    public convenience init(circleOfRadius radius: Float, center: Vector2 = .zero) {
        self.init(shape: .circle(radius: radius, center: center))
    }

    public convenience init(rectangleOf size: Vector2, center: Vector2 = .zero) {
        self.init(shape: .rectangle(size: size, center: center))
    }

    public convenience init(edgeLoopFrom rect: Rect) {
        self.init(shape: .edgeLoop(rect: rect))
    }

    private func updateMass() {
        var mass: Float = 0
        var weightedCenter = Vector2.zero
        var originInertia: Float = 0
        for part in parts {
            let data = part.massData(density: density)
            mass += data.mass
            weightedCenter += data.mass * data.center
            originInertia += data.inertia
        }
        massValue = mass
        localCenter = mass > 0 ? weightedCenter / mass : .zero
        inertia = max(originInertia - mass * dot(localCenter, localCenter), 0)
    }

    // MARK: - Derived

    var invMass: Float {
        isDynamic && massValue > 0 ? 1 / massValue : 0
    }

    var invInertia: Float {
        isDynamic && allowsRotation && inertia > 0 ? 1 / inertia : 0
    }

    var transform: RigidTransform {
        RigidTransform(position: position, angle: rotation)
    }

    /// Center of mass in world coordinates.
    public var worldCenter: Vector2 {
        get { position + Rotation(rotation).apply(localCenter) }
        set { position = newValue - Rotation(rotation).apply(localCenter) }
    }

    /// Velocity of a world point attached to the body.
    public func velocity(atPoint point: Vector2) -> Vector2 {
        velocity + cross(angularVelocity, point - worldCenter)
    }

    /// Axis-aligned bounds of the body in world coordinates.
    public var bounds: Rect? {
        let transform = transform
        return parts.map { $0.transformed(by: transform).bounds }.reduce(nil) { $0?.union($1) ?? $1 }
    }

    /// Whether a world point lies inside the body's shape.
    public func contains(_ point: Vector2) -> Bool {
        let local = Rotation(rotation).applyInverse(point - position)
        return parts.contains { $0.contains(local) }
    }

    // MARK: - Forces

    /// Applies a force (for the next step) at a world point, or the center of mass.
    public func applyForce(_ force: Vector2, at point: Vector2? = nil) {
        self.force += force
        if let point {
            torque += cross(point - worldCenter, force)
        }
    }

    public func applyTorque(_ torque: Float) {
        self.torque += torque
    }

    /// Instantly changes momentum, applied at a world point or the center of mass.
    public func applyImpulse(_ impulse: Vector2, at point: Vector2? = nil) {
        velocity += impulse * invMass
        if let point {
            angularVelocity += invInertia * cross(point - worldCenter, impulse)
        }
    }

    public func applyAngularImpulse(_ impulse: Float) {
        angularVelocity += invInertia * impulse
    }

    /// Bodies currently touching this body.
    public func allContactedBodies() -> [PhysicsBody] {
        world?.contactedBodies(of: self) ?? []
    }
}
