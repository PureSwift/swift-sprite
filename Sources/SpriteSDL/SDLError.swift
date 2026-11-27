//
//  SDLError.swift
//  SpriteSDL
//

import SDL3Swift

/// Error raised when an SDL call fails, carrying `SDL_GetError()`.
public struct SDLError: Error, CustomStringConvertible, Sendable {

    public let function: String

    public let message: String

    public init(_ function: String, message: String) {
        self.function = function
        self.message = message
    }

    /// Captures the current SDL error string for the failing function.
    static func last(_ function: String = #function) -> SDLError {
        SDLError(function, message: SDL3Swift.SDLError.current()?.errorMessage ?? "SDL operation failed")
    }

    public var description: String {
        "\(function): \(message)"
    }
}

extension Bool {

    /// Throws ``SDLError`` if an SDL call returned `false`.
    func check(_ function: String) throws(SDLError) {
        guard self else { throw .last(function) }
    }
}
