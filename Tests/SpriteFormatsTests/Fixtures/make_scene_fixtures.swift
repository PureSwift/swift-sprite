// Regenerate on macOS from the repository root: swift Tests/SpriteFormatsTests/Fixtures/make_scene_fixtures.swift
import Foundation
import SpriteKit
import AppKit
let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("SceneArchives")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let scene = SKScene(size: CGSize(width: 320, height: 240))
scene.name = "Fixture"
scene.scaleMode = .aspectFit
scene.anchorPoint = CGPoint(x: 0.25, y: 0.5)
scene.backgroundColor = NSColor(srgbRed: 0.1, green: 0.2, blue: 0.3, alpha: 0.8)
let node = SKNode()
node.name = "parent"
node.position = CGPoint(x: 12, y: -8)
node.xScale = 2
node.yScale = 0.5
node.zRotation = 0.25
node.alpha = 0.75
node.speed = 1.5
scene.addChild(node)
let sprite = SKSpriteNode(color: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8), size: CGSize(width: 40, height: 24))
sprite.name = "sprite"
sprite.anchorPoint = CGPoint(x: 0.2, y: 0.8)
sprite.position = CGPoint(x: 5, y: 7)
sprite.zPosition = 3
sprite.centerRect = CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5)
sprite.blendMode = .add
node.addChild(sprite)
let camera = SKCameraNode()
camera.name = "camera"
camera.position = CGPoint(x: 160, y: 120)
scene.addChild(camera)
scene.camera = camera
let label = SKLabelNode(fontNamed: "Menlo")
label.name = "label"
label.text = "Hello 🦊"
label.fontSize = 18
label.fontColor = NSColor(srgbRed: 0.9, green: 0.7, blue: 0.5, alpha: 0.6)
label.horizontalAlignmentMode = .left
label.verticalAlignmentMode = .top
label.numberOfLines = 2
label.preferredMaxLayoutWidth = 100
scene.addChild(label)
let imagePath = directory.appendingPathComponent("../SpriteKit/sample.atlas/wide.png").standardizedFileURL.path
let textured = SKSpriteNode(texture: SKTexture(imageNamed: imagePath))
textured.name = "textured"
textured.position = CGPoint(x: 100, y: 80)
scene.addChild(textured)
let shared = SKSpriteNode(texture: textured.texture)
shared.name = "sharedTexture"
shared.position = CGPoint(x: 200, y: 80)
scene.addChild(shared)
let data = try NSKeyedArchiver.archivedData(withRootObject: scene, requiringSecureCoding: true)
// Keep the native archive fields, replacing only the machine-specific resource path.
guard var plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
      var objects = plist["$objects"] as? [Any] else {
    fatalError("SpriteKit did not produce a keyed archive")
}
for index in objects.indices where (objects[index] as? String) == imagePath {
    objects[index] = "../SpriteKit/sample.atlas/wide.png"
}
plist["$objects"] = objects
let binary = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
try binary.write(to: directory.appendingPathComponent("scene.sks"))
let xml = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
try xml.write(to: directory.appendingPathComponent("scene.xml"))
