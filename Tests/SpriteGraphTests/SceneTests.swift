//
//  SceneTests.swift
//  SpriteGraphTests
//

import Testing
import SpriteCore
@testable import SpriteGraph

@MainActor @Suite struct SceneTests {

    @Test func fillStretchesEachAxis() {
        let scene = Scene(size: [100, 50])
        scene.scaleMode = .fill
        let view = scene.viewTransform(viewportSize: [200, 200])
        #expect(approx(view.transform(point: .zero), [0, 200]))
        #expect(approx(view.transform(point: [100, 50]), [200, 0]))
    }

    @Test func aspectFitLetterboxes() {
        let scene = Scene(size: [100, 50])
        scene.scaleMode = .aspectFit
        let view = scene.viewTransform(viewportSize: [200, 200])
        // Scale 2, centered vertically with 50 px bars.
        #expect(approx(view.transform(point: .zero), [0, 150]))
        #expect(approx(view.transform(point: [100, 50]), [200, 50]))
    }

    @Test func aspectFillCrops() {
        let scene = Scene(size: [100, 50])
        scene.scaleMode = .aspectFill
        let view = scene.viewTransform(viewportSize: [200, 200])
        // Scale 4, centered horizontally with 100 px cropped each side.
        #expect(approx(view.transform(point: .zero), [-100, 200]))
        #expect(approx(view.transform(point: [100, 50]), [300, 0]))
    }

    @Test func resizeFillMatchesViewport() {
        final class SizeScene: Scene {
            var oldSizes = [Vector2]()
            override func didChangeSize(_ oldSize: Vector2) { oldSizes.append(oldSize) }
        }
        let scene = SizeScene(size: [10, 10])
        scene.scaleMode = .resizeFill
        _ = scene.makeFrame(viewportSize: [320, 240])
        #expect(scene.size == [320, 240])
        #expect(scene.oldSizes == [[10, 10]])
    }

    @Test func anchorPointMovesOrigin() {
        let scene = Scene(size: [100, 100])
        scene.scaleMode = .fill
        scene.anchorPoint = [0.5, 0.5]
        let view = scene.viewTransform(viewportSize: [100, 100])
        #expect(approx(view.transform(point: .zero), [50, 50]))
    }

    @Test func cameraCentersView() {
        let scene = Scene(size: [100, 100])
        scene.scaleMode = .fill
        let camera = Camera()
        camera.position = [500, 500]
        camera.scale = [2, 2]
        scene.addChild(camera)
        scene.camera = camera
        let view = scene.viewTransform(viewportSize: [100, 100])
        #expect(approx(view.transform(point: [500, 500]), [50, 50]))
        // Camera scale 2 zooms out: 50 scene units span 25 pixels.
        #expect(approx(view.transform(point: [550, 500]), [75, 50]))
        #expect(camera.visibleRect == Rect(x: 400, y: 400, width: 200, height: 200))

        let near = Sprite(color: .red, size: [10, 10])
        near.position = [550, 550]
        let far = Sprite(color: .red, size: [10, 10])
        far.position = [0, 0]
        scene.addChild(near)
        scene.addChild(far)
        #expect(camera.contains(near))
        #expect(!camera.contains(far))
    }

    @Test func viewPointConversionRoundTrips() {
        let scene = Scene(size: [100, 100])
        scene.scaleMode = .aspectFit
        _ = scene.makeFrame(viewportSize: [200, 100])
        let point = scene.convertPoint(fromView: [100, 50])
        #expect(approx(point, [50, 50]))
        #expect(approx(scene.convertPoint(toView: point), [100, 50]))
    }

    @Test func ignoresSiblingOrderGroupsTextures() {
        let a = Texture(id: TextureID(rawValue: 1), textureSize: [4, 4])
        let b = Texture(id: TextureID(rawValue: 2), textureSize: [4, 4])
        let scene = Scene(size: [10, 10])
        for i in 0 ..< 6 {
            scene.addChild(Sprite(texture: i.isMultiple(of: 2) ? a : b))
        }
        #expect(scene.makeFrame(viewportSize: [10, 10]).batches.count == 6)
        scene.ignoresSiblingOrder = true
        #expect(scene.makeFrame(viewportSize: [10, 10]).batches.count == 2)
    }
}
