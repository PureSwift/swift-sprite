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


// Physics fixture has no external resources; values exercise units, masks and body behavior.
let physicsScene = SKScene(size: CGSize(width: 640, height: 480))
physicsScene.physicsWorld.gravity = CGVector(dx: 2, dy: -4)
physicsScene.physicsWorld.speed = 0.5
let polygon = CGMutablePath()
polygon.move(to: CGPoint(x: -10, y: -10))
polygon.addLine(to: CGPoint(x: 20, y: -10))
polygon.addLine(to: CGPoint(x: 0, y: 20))
polygon.closeSubpath()
let physicsBodies: [(String, SKPhysicsBody)] = [
    ("circle", SKPhysicsBody(circleOfRadius: 12, center: CGPoint(x: 2, y: 3))),
    ("rectangle", SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 20), center: CGPoint(x: 4, y: 5))),
    ("polygon", SKPhysicsBody(polygonFrom: polygon))
]
for (index, entry) in physicsBodies.enumerated() {
    let node = SKNode()
    node.name = entry.0
    node.position = CGPoint(x: index * 100, y: 200)
    let body = entry.1
    body.mass = 2
    body.friction = 0.3
    body.restitution = 0.4
    body.linearDamping = 0.2
    body.angularDamping = 0.6
    body.velocity = CGVector(dx: 7, dy: 8)
    body.angularVelocity = 0.7
    body.categoryBitMask = 0x80000001
    body.collisionBitMask = 3
    body.contactTestBitMask = 4
    body.allowsRotation = false
    body.affectedByGravity = index == 0
    body.isDynamic = index != 2
    node.physicsBody = body
    physicsScene.addChild(node)
    // Attaching an offset body can change its center-of-mass velocity. Set the archived
    // velocity after attachment so the fixture has a stable, explicit expectation.
    body.velocity = CGVector(dx: 7, dy: 8)
}
let physicsData = try NSKeyedArchiver.archivedData(withRootObject: physicsScene, requiringSecureCoding: true)
try physicsData.write(to: directory.appendingPathComponent("physics.sks"))
let physicsPlist = try PropertyListSerialization.propertyList(from: physicsData, options: [], format: nil)
try PropertyListSerialization.data(fromPropertyList: physicsPlist, format: .xml, options: 0)
    .write(to: directory.appendingPathComponent("physics.xml"))


let actionScene = SKScene(size: CGSize(width: 320, height: 240))
let actionCases: [(String, SKAction)] = [
    ("move", .moveBy(x: 12, y: 24, duration: 2)),
    ("moveTo", .move(to: CGPoint(x: 20, y: 30), duration: 2)),
    ("moveX", .moveTo(x: 16, duration: 2)),
    ("rotate", .rotate(byAngle: 1, duration: 2)),
    ("rotateTo", .rotate(toAngle: 2, duration: 2, shortestUnitArc: true)),
    ("scale", .scale(to: 2, duration: 2)),
    ("scaleBy", .scale(by: 3, duration: 2)),
    ("fade", .fadeAlpha(to: 0.2, duration: 2)),
    ("wait", .wait(forDuration: 2)),
    ("sequence", .sequence([.moveBy(x: 10, y: 0, duration: 1), .moveBy(x: 0, y: 10, duration: 1)])),
    ("group", .group([.moveBy(x: 10, y: 20, duration: 2), .fadeOut(withDuration: 2)])),
    ("repeat", .repeat(.moveBy(x: 10, y: 0, duration: 1), count: 3)),
    ("forever", .repeatForever(.moveBy(x: 10, y: 0, duration: 1))),
    ("remove", .sequence([.wait(forDuration: 1), .removeFromParent()])),
    ("hide", .hide()),
    ("unhide", .unhide())
]
for (name, action) in actionCases {
    let node = SKNode()
    node.name = name
    node.isHidden = name == "unhide"
    node.run(action, withKey: "animation")
    actionScene.addChild(node)
}
let unkeyed = SKNode()
unkeyed.name = "unkeyed"
let eased = SKAction.moveBy(x: 20, y: 0, duration: 2)
eased.timingMode = .easeIn
unkeyed.run(eased)
actionScene.addChild(unkeyed)
let actionData = try NSKeyedArchiver.archivedData(withRootObject: actionScene, requiringSecureCoding: true)
try actionData.write(to: directory.appendingPathComponent("actions.sks"))
let actionPlist = try PropertyListSerialization.propertyList(from: actionData, options: [], format: nil)
try PropertyListSerialization.data(fromPropertyList: actionPlist, format: .xml, options: 0)
    .write(to: directory.appendingPathComponent("actions.xml"))


let emitterScene = SKScene(size: CGSize(width: 320, height: 240))
let emitter = SKEmitterNode()
emitter.name = "emitter"
emitter.position = CGPoint(x: 20, y: 30)
emitter.particleTexture = SKTexture(imageNamed: imagePath)
emitter.particleBirthRate = 8
emitter.numParticlesToEmit = 12
emitter.particleLifetime = 4
emitter.particlePosition = CGPoint(x: 3, y: 4)
emitter.particlePositionRange = CGVector(dx: 10, dy: 20)
emitter.particleSpeed = 30
emitter.particleSpeedRange = 4
emitter.emissionAngle = 0.5
emitter.emissionAngleRange = 0.2
emitter.xAcceleration = 2
emitter.yAcceleration = -3
emitter.particleRotation = 0.3
emitter.particleRotationRange = 0.1
emitter.particleRotationSpeed = 0.4
emitter.particleColor = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
emitter.particleColorBlendFactor = 0.5
emitter.particleAlpha = 0.7
emitter.particleAlphaRange = 0.2
emitter.particleAlphaSpeed = -0.1
emitter.particleScale = 1.5
emitter.particleScaleRange = 0.5
emitter.particleScaleSpeed = -0.2
emitter.particleSize = CGSize(width: 10, height: 12)
emitter.particleZPosition = 2
emitter.particleBlendMode = .add
emitter.particleAlphaSequence = SKKeyframeSequence(keyframeValues: [1.0, 0.0], times: [0.0, 1.0])
emitter.particleScaleSequence = SKKeyframeSequence(keyframeValues: [1.0, 2.0], times: [0.0, 1.0])
emitter.targetNode = emitterScene
emitterScene.addChild(emitter)
let secondEmitter = SKEmitterNode()
secondEmitter.name = "second"
secondEmitter.particleTexture = emitter.particleTexture
emitterScene.addChild(secondEmitter)
let emitterData = try NSKeyedArchiver.archivedData(withRootObject: emitterScene, requiringSecureCoding: true)
guard var emitterPlist = try PropertyListSerialization.propertyList(from: emitterData, format: nil) as? [String: Any],
      var emitterObjects = emitterPlist["$objects"] as? [Any] else { fatalError("Invalid emitter archive") }
for index in emitterObjects.indices where (emitterObjects[index] as? String) == imagePath {
    emitterObjects[index] = "../SpriteKit/sample.atlas/wide.png"
}
emitterPlist["$objects"] = emitterObjects
try PropertyListSerialization.data(fromPropertyList: emitterPlist, format: .binary, options: 0)
    .write(to: directory.appendingPathComponent("emitters.sks"))
try PropertyListSerialization.data(fromPropertyList: emitterPlist, format: .xml, options: 0)
    .write(to: directory.appendingPathComponent("emitters.xml"))
