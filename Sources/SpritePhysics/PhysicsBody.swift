//
//  PhysicsBody.swift
//  SpritePhysics
//

import CBox2D
import SpriteCore

/// Rigid body simulated by a ``PhysicsWorld`` (backed by a Box2D body).
///
/// Properties can be configured before the body is added to a world; they are
/// applied to the Box2D body when it is created and forwarded afterwards.
/// ``position`` and ``rotation`` describe the body's origin (the origin of its ``shape``).
public final class PhysicsBody {

    // MARK: - Shape & mass

    public let shape: PhysicsShape

    let primitives: [ShapePrimitive]

    public let area: Float

    /// Mass per unit area. Setting ``mass`` adjusts density.
    public var density: Float = 1 {
        didSet {
            for shapeID in shapeIDs {
                b2Shape_SetDensity(shapeID, density, true)
            }
            updateMassData()
        }
    }

    public var mass: Float {
        get { massData.mass }
        set { if area > 0 { density = newValue / area } }
    }

    /// Rotational inertia about the center of mass.
    public var inertia: Float {
        massData.inertia
    }

    /// Center of mass in local coordinates.
    public var localCenter: Vector2 {
        massData.center
    }

    private var massData: (mass: Float, center: Vector2, inertia: Float) = (0, .zero, 0)

    // MARK: - Material

    public var friction: Float = 0.2 {
        didSet { shapeIDs.forEach { b2Shape_SetFriction($0, friction) } }
    }

    /// Bounciness in `0...1`.
    public var restitution: Float = 0.2 {
        didSet { shapeIDs.forEach { b2Shape_SetRestitution($0, restitution) } }
    }

    public var linearDamping: Float = 0.1 {
        didSet { bodyID.map { b2Body_SetLinearDamping($0, linearDamping) } }
    }

    public var angularDamping: Float = 0.1 {
        didSet { bodyID.map { b2Body_SetAngularDamping($0, angularDamping) } }
    }

    // MARK: - Behavior

    /// Dynamic bodies respond to forces and collisions; others are static obstacles
    /// that can still be repositioned directly.
    public var isDynamic: Bool {
        didSet {
            bodyID.map { b2Body_SetType($0, bodyType) }
            if isDynamic != oldValue { updatePin() }
        }
    }

    /// Enables Box2D bullet collision sweeps against non-bullet dynamic bodies.
    /// Static collisions already use continuous detection. Sensors and bullet pairs
    /// are not covered, and this does not guarantee identical SpriteKit timing.
    public var usesContinuousCollisionDetection = false {
        didSet { bodyID.map { b2Body_SetBullet($0, usesContinuousCollisionDetection) } }
    }

    /// Holds the body's origin at its current position while allowing rotation.
    /// Assigning a new position moves the pivot. Scene nodes therefore follow
    /// explicit parent transform changes; use a PinJoint to couple two dynamic bodies.
    public var isPinned = false {
        didSet {
            guard isPinned != oldValue else { return }
            updatePin()
        }
    }

    public var affectedByGravity = true {
        didSet { updateGravityScale() }
    }

    public var allowsRotation = true {
        didSet { bodyID.map { b2Body_SetMotionLocks($0, motionLocks) } }
    }

    /// Scales world gravity for this body.
    public var gravityScale: Float = 1 {
        didSet { updateGravityScale() }
    }

    // MARK: - Filtering

    /// Categories this body belongs to.
    public var categoryBitMask: PhysicsCategory = .all {
        didSet { updateFilter() }
    }

    /// Categories this body collides with.
    ///
    /// Box2D collisions are mutual: two bodies collide only if each one's mask contains the
    /// other's category. A body with an empty mask becomes a sensor that passes through
    /// everything but still reports contacts.
    public var collisionBitMask: PhysicsCategory = .all {
        didSet {
            if collisionBitMask.isEmpty != oldValue.isEmpty {
                rebuildShapes()
            } else {
                updateFilter()
            }
        }
    }

    /// Categories whose contacts with this body are reported.
    public var contactTestBitMask: PhysicsCategory = .none

    /// Whether the body's shapes are Box2D sensors (no collision response).
    var isSensor: Bool {
        collisionBitMask.isEmpty
    }

    // MARK: - Ownership

    /// Object represented by this body, such as a scene node.
    public weak var owner: AnyObject?

    public internal(set) weak var world: PhysicsWorld?

    // MARK: - Box2D state

    private(set) var bodyID: b2BodyId?

    private(set) var shapeIDs: [b2ShapeId] = []

    private var pinAnchorID: b2BodyId?

    // Detached state, used while the body is not in a world.
    private var storedPosition: Vector2
    private var storedRotation: Float
    private var storedVelocity: Vector2 = .zero
    private var storedAngularVelocity: Float = 0

    // MARK: - Initialization

    public init(shape: PhysicsShape, position: Vector2 = .zero, rotation: Float = 0) {
        _ = configureBox2DUnits
        self.shape = shape
        self.primitives = shape.primitives
        self.area = primitives.reduce(0) { $0 + $1.area }
        self.storedPosition = position
        self.storedRotation = rotation
        // Shapes without area (edges) cannot be simulated dynamically.
        self.isDynamic = area > 0
        updateMassData()
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

    // MARK: - Transform & velocity

    public var position: Vector2 {
        get { bodyID.map { Vector2(b2Body_GetPosition($0)) } ?? storedPosition }
        set {
            storedPosition = newValue
            setTransform(position: newValue, rotation: rotation)
        }
    }

    /// Rotation in radians, counter-clockwise.
    public var rotation: Float {
        get { bodyID.map { b2Body_GetRotation($0).angle } ?? storedRotation }
        set {
            storedRotation = newValue
            setTransform(position: position, rotation: newValue)
        }
    }

    /// Linear velocity of the center of mass.
    public var velocity: Vector2 {
        get { bodyID.map { Vector2(b2Body_GetLinearVelocity($0)) } ?? storedVelocity }
        set {
            storedVelocity = newValue
            bodyID.map { b2Body_SetLinearVelocity($0, b2Vec2(newValue)) }
        }
    }

    public var angularVelocity: Float {
        get { bodyID.map { b2Body_GetAngularVelocity($0) } ?? storedAngularVelocity }
        set {
            storedAngularVelocity = newValue
            bodyID.map { b2Body_SetAngularVelocity($0, newValue) }
        }
    }

    /// Center of mass in world coordinates.
    public var worldCenter: Vector2 {
        position + b2Rot(angle: rotation).apply(localCenter)
    }

    /// Velocity of a world point attached to the body.
    public func velocity(atPoint point: Vector2) -> Vector2 {
        let r = point - worldCenter
        return velocity + Vector2(-angularVelocity * r.y, angularVelocity * r.x)
    }

    /// Axis-aligned bounds of the body in world coordinates.
    public var bounds: Rect? {
        let rotation = b2Rot(angle: self.rotation)
        let position = self.position
        var lo = Vector2(repeating: .infinity)
        var hi = Vector2(repeating: -.infinity)
        for primitive in primitives {
            if case let .circle(circle) = primitive {
                let center = position + rotation.apply(Vector2(circle.center))
                lo = pointwiseMin(lo, center - circle.radius)
                hi = pointwiseMax(hi, center + circle.radius)
            } else {
                for point in primitive.boundsPoints {
                    let p = position + rotation.apply(point)
                    lo = pointwiseMin(lo, p)
                    hi = pointwiseMax(hi, p)
                }
            }
        }
        guard lo.x <= hi.x else { return nil }
        return Rect(origin: lo, size: hi - lo)
    }

    /// Whether a world point lies inside the body's shape.
    public func contains(_ point: Vector2) -> Bool {
        let rotation = b2Rot(angle: self.rotation)
        let d = point - position
        let local = Vector2(rotation.c * d.x + rotation.s * d.y, -rotation.s * d.x + rotation.c * d.y)
        return primitives.contains { primitive in
            switch primitive {
            case let .circle(circle):
                return length(local - Vector2(circle.center)) <= circle.radius
            case let .polygon(polygon):
                return withUnsafeBytes(of: polygon.vertices) { vertices in
                    withUnsafeBytes(of: polygon.normals) { normals in
                        let v = vertices.bindMemory(to: b2Vec2.self)
                        let n = normals.bindMemory(to: b2Vec2.self)
                        return (0 ..< Int(polygon.count)).allSatisfy { dot(Vector2(n[$0]), local - Vector2(v[$0])) <= 0 }
                    }
                }
            case .segment:
                return false
            }
        }
    }

    // MARK: - Forces

    /// Applies a force for the next step at a world point, or the center of mass.
    /// Has no effect until the body is in a world.
    public func applyForce(_ force: Vector2, at point: Vector2? = nil) {
        guard let bodyID else { return }
        if let point {
            b2Body_ApplyForce(bodyID, b2Vec2(force), b2Vec2(point), true)
        } else {
            b2Body_ApplyForceToCenter(bodyID, b2Vec2(force), true)
        }
    }

    public func applyTorque(_ torque: Float) {
        guard let bodyID else { return }
        b2Body_ApplyTorque(bodyID, torque, true)
    }

    /// Instantly changes momentum, applied at a world point or the center of mass.
    public func applyImpulse(_ impulse: Vector2, at point: Vector2? = nil) {
        guard isDynamic, mass > 0 else { return }
        if let bodyID {
            if let point {
                b2Body_ApplyLinearImpulse(bodyID, b2Vec2(impulse), b2Vec2(point), true)
            } else {
                b2Body_ApplyLinearImpulseToCenter(bodyID, b2Vec2(impulse), true)
            }
        } else {
            storedVelocity += impulse / mass
            if let point, allowsRotation, inertia > 0 {
                storedAngularVelocity += cross(point - worldCenter, impulse) / inertia
            }
        }
    }

    public func applyAngularImpulse(_ impulse: Float) {
        guard isDynamic, allowsRotation, inertia > 0 else { return }
        if let bodyID {
            b2Body_ApplyAngularImpulse(bodyID, impulse, true)
        } else {
            storedAngularVelocity += impulse / inertia
        }
    }

    /// Bodies currently touching this body.
    public func allContactedBodies() -> [PhysicsBody] {
        guard let bodyID else { return [] }
        let capacity = b2Body_GetContactCapacity(bodyID)
        guard capacity > 0 else { return [] }
        var contacts = [b2ContactData](repeating: b2ContactData(), count: Int(capacity))
        let count = b2Body_GetContactData(bodyID, &contacts, capacity)
        var result = [PhysicsBody]()
        for contact in contacts.prefix(Int(count)) where contact.manifold.pointCount > 0 {
            for shapeID in [contact.shapeIdA, contact.shapeIdB] {
                if let body = PhysicsBody.from(shape: shapeID), body !== self, !result.contains(where: { $0 === body }) {
                    result.append(body)
                }
            }
        }
        return result
    }

    // MARK: - Box2D lifecycle

    /// Looks up the Swift body that owns a Box2D shape.
    static func from(shape: b2ShapeId) -> PhysicsBody? {
        guard b2Shape_IsValid(shape) else { return nil }
        return from(body: b2Shape_GetBody(shape))
    }

    static func from(body: b2BodyId) -> PhysicsBody? {
        guard b2Body_IsValid(body), let pointer = b2Body_GetUserData(body) else { return nil }
        return Unmanaged<PhysicsBody>.fromOpaque(pointer).takeUnretainedValue()
    }

    /// Creates the Box2D body and shapes in `world`.
    func attach(to worldID: b2WorldId) {
        guard bodyID == nil else { return }
        var definition = b2DefaultBodyDef()
        definition.type = bodyType
        definition.position = b2Vec2(storedPosition)
        definition.rotation = b2Rot(angle: storedRotation)
        definition.linearVelocity = b2Vec2(storedVelocity)
        definition.angularVelocity = storedAngularVelocity
        definition.linearDamping = linearDamping
        definition.angularDamping = angularDamping
        definition.gravityScale = effectiveGravityScale
        definition.motionLocks = motionLocks
        definition.isBullet = usesContinuousCollisionDetection
        definition.userData = Unmanaged.passUnretained(self).toOpaque()
        bodyID = b2CreateBody(worldID, &definition)
        createShapes()
        updatePin()
    }

    /// Destroys the Box2D body (and its joints), keeping state for re-adding later.
    func detach() {
        guard let bodyID else { return }
        storedPosition = position
        storedRotation = rotation
        storedVelocity = velocity
        storedAngularVelocity = angularVelocity
        destroyPin()
        b2DestroyBody(bodyID)
        self.bodyID = nil
        shapeIDs = []
    }

    private func destroyPin() {
        if let pinAnchorID {
            // Destroying the anchor also destroys its revolute joint.
            b2DestroyBody(pinAnchorID)
            self.pinAnchorID = nil
        }
    }

    private func updatePin() {
        destroyPin()
        guard let bodyID else { return }
        b2Body_SetAwake(bodyID, true)
        guard isPinned, isDynamic, area > 0 else { return }
        let worldID = b2Body_GetWorld(bodyID)
        var anchor = b2DefaultBodyDef()
        anchor.position = b2Body_GetPosition(bodyID)
        let anchorID = b2CreateBody(worldID, &anchor)
        pinAnchorID = anchorID
        var joint = b2DefaultRevoluteJointDef()
        joint.base.bodyIdA = anchorID
        joint.base.bodyIdB = bodyID
        joint.base.localFrameA = b2Transform(p: b2Vec2(x: 0, y: 0), q: b2Rot(c: 1, s: 0))
        joint.base.localFrameB = joint.base.localFrameA
        _ = b2CreateRevoluteJoint(worldID, &joint)
        b2Body_SetAwake(bodyID, true)
    }

    private func createShapes() {
        guard let bodyID else { return }
        var definition = b2DefaultShapeDef()
        definition.density = density
        definition.material.friction = friction
        definition.material.restitution = restitution
        definition.filter = filter
        definition.isSensor = isSensor
        definition.enableSensorEvents = true
        definition.enableContactEvents = true
        shapeIDs = primitives.map { $0.create(on: bodyID, definition: &definition) }
    }

    private func rebuildShapes() {
        for shapeID in shapeIDs {
            b2DestroyShape(shapeID, false)
        }
        shapeIDs = []
        createShapes()
    }

    private func setTransform(position: Vector2, rotation: Float) {
        guard let bodyID else { return }
        b2Body_SetTransform(bodyID, b2Vec2(position), b2Rot(angle: rotation))
        if let pinAnchorID {
            b2Body_SetTransform(pinAnchorID, b2Vec2(position), b2Rot(c: 1, s: 0))
        }
        if isDynamic {
            b2Body_SetAwake(bodyID, true)
        }
    }

    private var bodyType: b2BodyType {
        isDynamic ? b2_dynamicBody : b2_staticBody
    }

    private var effectiveGravityScale: Float {
        affectedByGravity ? gravityScale : 0
    }

    private var motionLocks: b2MotionLocks {
        b2MotionLocks(linearX: false, linearY: false, angularZ: !allowsRotation)
    }

    private var filter: b2Filter {
        // Sensors must accept every category to detect overlaps; contact tests filter reports.
        b2Filter(
            categoryBits: categoryBitMask.box2DBits,
            maskBits: isSensor ? UInt64.max : collisionBitMask.box2DBits,
            groupIndex: 0
        )
    }

    private func updateFilter() {
        let filter = self.filter
        shapeIDs.forEach { b2Shape_SetFilter($0, filter) }
    }

    private func updateGravityScale() {
        bodyID.map { b2Body_SetGravityScale($0, effectiveGravityScale) }
    }

    private func updateMassData() {
        var mass: Float = 0
        var weightedCenter = Vector2.zero
        var parts = [(mass: Float, center: Vector2, inertia: Float)]()
        for primitive in primitives {
            let data = primitive.massData(density: density)
            mass += data.mass
            weightedCenter += data.mass * Vector2(data.center)
            parts.append((data.mass, Vector2(data.center), data.rotationalInertia))
        }
        let center = mass > 0 ? weightedCenter / mass : .zero
        // Parallel axis theorem: each part's inertia about its centroid, shifted to the body center.
        let inertia = parts.reduce(0) { $0 + $1.inertia + $1.mass * dot($1.center - center, $1.center - center) }
        massData = (mass, center, inertia)
    }
}
