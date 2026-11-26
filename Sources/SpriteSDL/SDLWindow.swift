//
//  SDLWindow.swift
//  SpriteSDL
//

import CSDL3
import SpriteCore

/// SDL3 window paired with an accelerated renderer.
///
/// SDL video APIs must be called from the main thread.
public final class SDLWindow {

    /// `SDL_Window *`
    let window: OpaquePointer

    /// `SDL_Renderer *`
    let renderer: OpaquePointer

    /// `SDL_WINDOW_RESIZABLE`; the `SDL_UINT64_C` macro is not importable.
    private static let resizable: UInt64 = 0x0000_0000_0000_0020

    /// `SDL_WINDOW_HIGH_PIXEL_DENSITY`
    private static let highPixelDensity: UInt64 = 0x0000_0000_0000_2000

    public init(
        title: String,
        width: Int,
        height: Int,
        resizable: Bool = true,
        vsync: Bool = true
    ) throws {
        try SDL_InitSubSystem(SDL_INIT_VIDEO).check("SDL_InitSubSystem")
        var flags = Self.highPixelDensity
        if resizable {
            flags |= Self.resizable
        }
        var window: OpaquePointer?
        var renderer: OpaquePointer?
        guard SDL_CreateWindowAndRenderer(title, Int32(width), Int32(height), flags, &window, &renderer),
              let window, let renderer else {
            let error = SDLError.last("SDL_CreateWindowAndRenderer")
            SDL_QuitSubSystem(SDL_INIT_VIDEO)
            throw error
        }
        self.window = window
        self.renderer = renderer
        SDL_SetRenderVSync(renderer, vsync ? 1 : 0)
    }

    deinit {
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
        SDL_QuitSubSystem(SDL_INIT_VIDEO)
    }

    public var title: String {
        get { String(cString: SDL_GetWindowTitle(window)) }
        set { SDL_SetWindowTitle(window, newValue) }
    }

    /// Size of the renderer output in pixels.
    public var drawableSize: Vector2 {
        var w: Int32 = 0, h: Int32 = 0
        SDL_GetCurrentRenderOutputSize(renderer, &w, &h)
        return Vector2(Float(w), Float(h))
    }

    /// Drains the SDL event queue.
    public func pollEvents() -> [InputEvent] {
        var events = [InputEvent]()
        var event = SDL_Event()
        while SDL_PollEvent(&event) {
            // Map window coordinates (points) to renderer coordinates (pixels).
            SDL_ConvertEventToRenderCoordinates(renderer, &event)
            if let input = InputEvent(event, drawableSize: drawableSize) {
                events.append(input)
            }
        }
        return events
    }
}

extension InputEvent {

    init?(_ event: SDL_Event, drawableSize: Vector2) {
        switch SDL_EventType(rawValue: event.type) {
        case SDL_EVENT_QUIT, SDL_EVENT_WINDOW_CLOSE_REQUESTED:
            self = .quit
        case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
            self = .resized(drawableSize)
        case SDL_EVENT_KEY_DOWN:
            self = .keyDown(KeyCode(rawValue: event.key.key), isRepeat: event.key.repeat)
        case SDL_EVENT_KEY_UP:
            self = .keyUp(KeyCode(rawValue: event.key.key))
        case SDL_EVENT_MOUSE_MOTION:
            self = .mouseMoved(Vector2(event.motion.x, event.motion.y))
        case SDL_EVENT_MOUSE_BUTTON_DOWN:
            self = .mouseDown(MouseButton(rawValue: event.button.button), Vector2(event.button.x, event.button.y))
        case SDL_EVENT_MOUSE_BUTTON_UP:
            self = .mouseUp(MouseButton(rawValue: event.button.button), Vector2(event.button.x, event.button.y))
        case SDL_EVENT_MOUSE_WHEEL:
            self = .mouseWheel(Vector2(event.wheel.x, event.wheel.y))
        case SDL_EVENT_FINGER_DOWN:
            self = .touchDown(finger: event.tfinger.fingerID, Self.touchPosition(event, drawableSize))
        case SDL_EVENT_FINGER_MOTION:
            self = .touchMoved(finger: event.tfinger.fingerID, Self.touchPosition(event, drawableSize))
        case SDL_EVENT_FINGER_UP:
            self = .touchUp(finger: event.tfinger.fingerID, Self.touchPosition(event, drawableSize))
        default:
            return nil
        }
    }

    /// Touch coordinates are normalized (0...1) unless converted by the renderer.
    private static func touchPosition(_ event: SDL_Event, _ size: Vector2) -> Vector2 {
        let p = Vector2(event.tfinger.x, event.tfinger.y)
        return (p.x <= 1 && p.y <= 1) ? p * size : p
    }
}
