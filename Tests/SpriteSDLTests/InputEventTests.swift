import Testing
import SpriteCore
import SDL3Swift
@testable import SpriteSDL

@Suite struct InputEventTests {
    private func convert(_ event: SDLEvent) -> InputEvent? {
        InputEvent(event, drawableSize: [800, 600], windowToRender: { $0 * 2 })
    }

    @Test func mouseCoordinatesUseRendererConversion() {
        let motion = SDLEvent.mouseMotion(windowID: 1, which: .init(rawValue: 0), buttons: [],
            x: 10, y: 20, relativeX: 1, relativeY: 2)
        #expect(convert(motion) == .mouseMoved([20, 40]))
        let button = SDLEvent.mouseButtonDown(windowID: 1, which: .init(rawValue: 0),
            button: .right, clicks: 1, x: 10, y: 20)
        #expect(convert(button) == .mouseDown(.right, [20, 40]))
    }

    @Test func touchCoordinatesStayNormalizedUntilConversion() {
        let touch = SDLEvent.fingerDown(windowID: 1, touchID: .init(rawValue: 2),
            fingerID: .init(rawValue: 3), x: 0.25, y: 0.5)
        #expect(convert(touch) == .touchDown(finger: 3, [200, 300]))
        let cancelled = SDLEvent.fingerCanceled(windowID: 1, touchID: .init(rawValue: 2),
            fingerID: .init(rawValue: 3), x: 0.25, y: 0.5)
        #expect(convert(cancelled) == .touchUp(finger: 3, [200, 300]))
    }

    @Test func keyboardAndWindowEvents() {
        let key = SDLEvent.keyDown(windowID: 1, scancode: .init(rawValue: 0),
            keycode: .init(rawValue: 27), modifiers: [], isRepeat: true)
        #expect(convert(key) == .keyDown(.escape, isRepeat: true))
        #expect(convert(.window(windowID: 1, event: .pixelSizeChanged(width: 800, height: 600))) == .resized([800, 600]))
        #expect(convert(.window(windowID: 1, event: .closeRequested)) == .quit)
        #expect(convert(.unknown(123)) == nil)
    }

    @MainActor @Test func softwareRendererLifecycle() throws {
        SDL.setHint("SDL_VIDEO_DRIVER", "dummy")
        SDL.setHint("SDL_RENDER_DRIVER", "software")
        // Reopening exercises teardown order as well as initialization.
        for _ in 0..<2 {
            let window = try SpriteSDL.SDLWindow(title: "Test", width: 32, height: 32, vsync: false)
            let backend = SDLRenderBackend(window: window)
            var pixels = PixelBuffer(width: 2, height: 2, fill: .red)
            let texture = try backend.makeTexture(pixels, filtering: .nearest)
            pixels[0, 0] = .blue
            try backend.updateTexture(texture, with: pixels)
            var batcher = SpriteBatcher()
            batcher.submit(SpriteQuad(texture: texture, size: [16, 16]))
            batcher.submit(SpriteQuad(size: [4, 4], color: .green))
            try backend.render(batcher.makeFrame(), clearColor: .black)
            #expect(backend.drawableSize == [32, 32])
            backend.destroyTexture(texture)
        }
    }
}
