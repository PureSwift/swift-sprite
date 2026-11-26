//
//  MathTests.swift
//  SpriteCoreTests
//

import Testing
@testable import SpriteCore

@Suite struct MathTests {

    func approx(_ a: Vector2, _ b: Vector2, tolerance: Float = 1e-5) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    @Test func identityLeavesPointsUnchanged() {
        let p = Vector2(3, -7)
        #expect(Matrix3x3.identity.transform(point: p) == p)
        #expect(Matrix3x3.identity * Matrix3x3.identity == .identity)
    }

    @Test func translationAffectsPointsNotVectors() {
        let m = Matrix3x3.translation(Vector2(10, 20))
        #expect(m.transform(point: Vector2(1, 2)) == Vector2(11, 22))
        #expect(m.transform(vector: Vector2(1, 2)) == Vector2(1, 2))
        #expect(m.translation == Vector2(10, 20))
    }

    @Test func rotationIsCounterClockwise() {
        let m = Matrix3x3.rotation(.pi / 2)
        #expect(approx(m.transform(point: Vector2(1, 0)), Vector2(0, 1)))
    }

    @Test func transformComposesTranslateRotateScale() {
        let t = Transform2D(position: Vector2(5, 5), rotation: .pi / 2, scale: Vector2(2, 3))
        let expected = Matrix3x3.translation(t.position) * .rotation(t.rotation) * .scale(t.scale)
        let p = Vector2(1, 1)
        #expect(approx(t.matrix.transform(point: p), expected.transform(point: p)))
        // Scale (2, 3) → rotate 90° → translate (5, 5)
        #expect(approx(t.matrix.transform(point: p), Vector2(2, 7)))
    }

    @Test func inverseRoundTrips() throws {
        let m = Transform2D(position: Vector2(-4, 9), rotation: 0.7, scale: Vector2(1.5, 0.5)).matrix
        let inverse = try #require(m.inverse)
        let p = Vector2(12, -3)
        #expect(approx(inverse.transform(point: m.transform(point: p)), p, tolerance: 1e-4))
        #expect(Matrix3x3.scale(.zero).inverse == nil)
    }

    @Test func rowsAreTransposeOfColumns() {
        let m = Matrix3x3(rows: SIMD3(1, 2, 3), SIMD3(4, 5, 6), SIMD3(7, 8, 9))
        #expect(m.columns.0 == SIMD3(1, 4, 7))
        #expect(m.rows.1 == SIMD3(4, 5, 6))
    }

    @Test func viewportFlipsY() {
        let m = Matrix3x3.viewport(size: Vector2(100, 50))
        #expect(m.transform(point: Vector2(0, 0)) == Vector2(0, 50))
        #expect(m.transform(point: Vector2(100, 50)) == Vector2(100, 0))
    }

    @Test func rectQueries() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 5, y: 5, width: 10, height: 10)
        #expect(a.contains(Vector2(5, 5)))
        #expect(!a.contains(Vector2(10, 10)))
        #expect(a.intersects(b))
        #expect(!a.intersects(Rect(x: 10, y: 0, width: 5, height: 5)))
        #expect(a.union(b) == Rect(x: 0, y: 0, width: 15, height: 15))
        #expect(a.insetBy(dx: 1, dy: 2) == Rect(x: 1, y: 2, width: 8, height: 6))
        let rotated = a.applying(.rotation(.pi / 2))
        #expect(approx(rotated.origin, Vector2(-10, 0)))
        #expect(approx(rotated.size, Vector2(10, 10)))
    }

    @Test func colorFromHex() {
        let c = Color(rgba: 0xFF_00_80_FF)
        #expect(c.red == 1 && c.green == 0 && c.alpha == 1)
        #expect(abs(c.blue - 128.0 / 255.0) < 1e-6)
        #expect(Color.white * Color.red == .red)
    }
}
