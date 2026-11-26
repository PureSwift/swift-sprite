//
//  InputEvent.swift
//  SpriteSDL
//

import SpriteCore

/// Platform-neutral input event produced by ``SDLWindow/pollEvents()``.
///
/// Positions are in render-target pixels with the origin at the top-left.
public enum InputEvent: Equatable, Sendable {

    case quit

    /// The render output size changed (in pixels).
    case resized(Vector2)

    case keyDown(KeyCode, isRepeat: Bool)

    case keyUp(KeyCode)

    case mouseMoved(Vector2)

    case mouseDown(MouseButton, Vector2)

    case mouseUp(MouseButton, Vector2)

    case mouseWheel(Vector2)

    case touchDown(finger: UInt64, Vector2)

    case touchMoved(finger: UInt64, Vector2)

    case touchUp(finger: UInt64, Vector2)
}

/// Virtual key code (`SDL_Keycode`).
public struct KeyCode: RawRepresentable, Hashable, Sendable {

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public extension KeyCode {
    static let escape = KeyCode(rawValue: 0x1B)
    static let space = KeyCode(rawValue: 0x20)
    static let `return` = KeyCode(rawValue: 0x0D)
    static let right = KeyCode(rawValue: 0x4000_004F)
    static let left = KeyCode(rawValue: 0x4000_0050)
    static let down = KeyCode(rawValue: 0x4000_0051)
    static let up = KeyCode(rawValue: 0x4000_0052)

    /// Key code for a printable ASCII character (lowercase letters, digits).
    static func character(_ c: Character) -> KeyCode? {
        c.asciiValue.map { KeyCode(rawValue: UInt32($0)) }
    }
}

/// Mouse button index (`SDL_BUTTON_*`).
public struct MouseButton: RawRepresentable, Hashable, Sendable {

    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let left = MouseButton(rawValue: 1)
    public static let middle = MouseButton(rawValue: 2)
    public static let right = MouseButton(rawValue: 3)
}
