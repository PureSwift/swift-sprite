//
//  Box2D+Conversions.swift
//  SpritePhysics
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import CBox2D
import Foundation
import SpriteCore

extension b2Vec2 {

    init(_ v: Vector2) {
        self.init(x: v.x, y: v.y)
    }
}

extension Vector2 {

    init(_ v: b2Vec2) {
        self.init(v.x, v.y)
    }
}

extension b2Rot {

    init(angle: Float) {
        self.init(c: cosf(angle), s: sinf(angle))
    }

    var angle: Float {
        atan2f(s, c)
    }

    func apply(_ v: Vector2) -> Vector2 {
        Vector2(c * v.x - s * v.y, s * v.x + c * v.y)
    }
}

extension PhysicsCategory {

    /// Box2D 64-bit category bits (the upper 32 bits are unused).
    var box2DBits: UInt64 {
        UInt64(rawValue)
    }
}

/// Small vector helpers.
@inline(__always)
func dot(_ a: Vector2, _ b: Vector2) -> Float {
    (a * b).sum()
}

@inline(__always)
func cross(_ a: Vector2, _ b: Vector2) -> Float {
    a.x * b.y - a.y * b.x
}

@inline(__always)
func length(_ v: Vector2) -> Float {
    dot(v, v).squareRoot()
}

@inline(__always)
func normalize(_ v: Vector2) -> Vector2 {
    let len = length(v)
    return len > .ulpOfOne ? v / len : .zero
}

/// Serializes `b2CreateWorld` / `b2DestroyWorld`, which update Box2D's global world
/// table without synchronization. Separate worlds may otherwise be used concurrently.
let box2DWorldLock = NSLock()

/// Box2D is tuned for meters; scene units are points with 100 points per meter.
///
/// This sets Box2D's global length scale and must happen before any Box2D object
/// (including default definitions) is created.
let configureBox2DUnits: Void = {
    b2SetLengthUnitsPerMeter(PhysicsWorld.pointsPerMeter)
}()
