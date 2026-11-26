//
//  KeyframeSequence.swift
//  SpriteGraph
//

import SpriteCore

/// Value that can be linearly interpolated.
public protocol Interpolatable: Sendable {
    static func interpolate(_ a: Self, _ b: Self, fraction: Float) -> Self
}

extension Float: Interpolatable {
    public static func interpolate(_ a: Float, _ b: Float, fraction: Float) -> Float {
        a + (b - a) * fraction
    }
}

extension SIMD2: Interpolatable where Scalar == Float {
    public static func interpolate(_ a: SIMD2<Float>, _ b: SIMD2<Float>, fraction: Float) -> SIMD2<Float> {
        a + (b - a) * fraction
    }
}

extension Color: Interpolatable {
    public static func interpolate(_ a: Color, _ b: Color, fraction: Float) -> Color {
        a.mix(with: b, fraction: fraction)
    }
}

/// Values keyed by time, sampled with linear interpolation (like `SKKeyframeSequence`).
///
/// ```swift
/// emitter.particleColorSequence = KeyframeSequence([
///     (0, .white), (0.5, .yellow), (1, Color(red: 1, green: 0, blue: 0, alpha: 0)),
/// ])
/// ```
public struct KeyframeSequence<Value: Interpolatable>: Sendable {

    public struct Keyframe: Sendable {
        public var time: Float
        public var value: Value

        public init(time: Float, value: Value) {
            self.time = time
            self.value = value
        }
    }

    /// Keyframes sorted by time.
    public private(set) var keyframes: [Keyframe]

    public init(_ keyframes: [Keyframe]) {
        precondition(!keyframes.isEmpty, "A keyframe sequence needs at least one keyframe")
        self.keyframes = keyframes.sorted { $0.time < $1.time }
    }

    public init(_ pairs: [(time: Float, value: Value)]) {
        self.init(pairs.map { Keyframe(time: $0.time, value: $0.value) })
    }

    /// Value at `time`, clamped to the first and last keyframes.
    public func value(at time: Float) -> Value {
        guard let first = keyframes.first, let last = keyframes.last else {
            preconditionFailure("Empty keyframe sequence")
        }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        // Few keyframes are typical, so a linear scan is fastest.
        var index = 1
        while keyframes[index].time < time { index += 1 }
        let a = keyframes[index - 1], b = keyframes[index]
        let span = b.time - a.time
        return Value.interpolate(a.value, b.value, fraction: span > 0 ? (time - a.time) / span : 1)
    }
}
