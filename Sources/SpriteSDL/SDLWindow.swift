import SDL3Swift
import SpriteCore

/// SDL3 window and renderer managed by PureSwift/SDL.
/// Video and rendering operations must run on the main thread.
public final class SDLWindow {
    private var ownedWindow: SDL3Swift.SDLWindow?
    private var ownedRenderer: SDLRenderer?

    var renderer: SDLRenderer {
        guard let ownedRenderer else { preconditionFailure("Renderer has been released") }
        return ownedRenderer
    }

    public init(title: String, width: Int, height: Int, resizable: Bool = true, vsync: Bool = true) throws {
        guard width > 0, height > 0, Int32(exactly: width) != nil, Int32(exactly: height) != nil else {
            throw SDLError("SDLWindow", message: "Invalid window dimensions")
        }
        try SDL.initialize(subSystem: .video)
        do {
            var options: BitMaskOptionSet<SDL3Swift.SDLWindow.Option> = [.highPixelDensity]
            if resizable { options.insert(.resizable) }
            let window = try SDL3Swift.SDLWindow(title: title, width: width, height: height, options: options)
            ownedWindow = window
            ownedRenderer = try SDLRenderer(window: window)
            // VSync is best-effort, as in the original backend.
            try? renderer.setVSync(vsync ? .every(1) : .disabled)
        } catch {
            ownedRenderer = nil
            ownedWindow = nil
            SDL.quit(subSystems: [.video])
            throw error
        }
    }

    deinit {
        // The wrappers own their handles; release them before quitting the video subsystem.
        ownedRenderer = nil
        ownedWindow = nil
        SDL.quit(subSystems: [.video])
    }

    public var title: String {
        get { ownedWindow?.title ?? "" }
        set { ownedWindow?.title = newValue }
    }

    public var drawableSize: Vector2 {
        guard let size = renderer.currentOutputSize else { return .zero }
        return Vector2(Float(size.width), Float(size.height))
    }

    public func pollEvents() -> [InputEvent] {
        var events: [InputEvent] = []
        while let event = SDL.pollEvent() {
            if let input = InputEvent(event, drawableSize: drawableSize, windowToRender: { point in
                let converted = renderer.renderCoordinates(fromWindow: (point.x, point.y))
                return Vector2(converted.x, converted.y)
            }) {
                events.append(input)
            }
        }
        return events
    }
}

extension InputEvent {
    init?(_ event: SDLEvent, drawableSize: Vector2, windowToRender: (Vector2) -> Vector2) {
        switch event {
        case .quit, .window(_, .closeRequested):
            self = .quit
        case .window(_, .pixelSizeChanged):
            self = .resized(drawableSize)
        case let .keyDown(_, _, key, _, isRepeat):
            self = .keyDown(KeyCode(rawValue: key.rawValue), isRepeat: isRepeat)
        case let .keyUp(_, _, key, _, _):
            self = .keyUp(KeyCode(rawValue: key.rawValue))
        case let .mouseMotion(_, _, _, x, y, _, _):
            self = .mouseMoved(windowToRender([x, y]))
        case let .mouseButtonDown(_, _, button, _, x, y):
            self = .mouseDown(MouseButton(rawValue: button.rawValue), windowToRender([x, y]))
        case let .mouseButtonUp(_, _, button, _, x, y):
            self = .mouseUp(MouseButton(rawValue: button.rawValue), windowToRender([x, y]))
        case let .mouseWheel(_, _, x, y, _, _, _):
            self = .mouseWheel([x, y])
        case let .fingerDown(_, _, finger, x, y):
            self = .touchDown(finger: finger.rawValue, Vector2(x, y) * drawableSize)
        case let .fingerMotion(_, _, finger, x, y):
            self = .touchMoved(finger: finger.rawValue, Vector2(x, y) * drawableSize)
        case let .fingerUp(_, _, finger, x, y), let .fingerCanceled(_, _, finger, x, y):
            self = .touchUp(finger: finger.rawValue, Vector2(x, y) * drawableSize)
        default:
            return nil
        }
    }
}
