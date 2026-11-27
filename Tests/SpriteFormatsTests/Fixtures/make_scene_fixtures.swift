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


let tileTexture = SKTexture(imageNamed: imagePath)
let tileA = SKTileDefinition(texture: tileTexture, size: CGSize(width: 16, height: 16))
let tileB = SKTileDefinition(texture: tileTexture, size: CGSize(width: 16, height: 16))
let tileC = SKTileDefinition(texture: tileTexture, size: CGSize(width: 16, height: 16))
let rule = SKTileGroupRule(adjacency: .adjacencyAll, tileDefinitions: [tileA, tileB])
let groupA = SKTileGroup(rules: [rule])
let groupB = SKTileGroup(tileDefinition: tileC)
let sharedGroup = SKTileGroup(tileDefinition: tileA)
let tileSet = SKTileSet(tileGroups: [groupA, groupB, sharedGroup], tileSetType: .grid)
tileSet.name = "Terrain"
let tileMap = SKTileMapNode(tileSet: tileSet, columns: 3, rows: 2, tileSize: CGSize(width: 16, height: 16))
tileMap.enableAutomapping = false
tileMap.name = "grid"
tileMap.position = CGPoint(x: 20, y: 30)
tileMap.anchorPoint = CGPoint(x: 0.25, y: 0.75)
tileMap.color = NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)
tileMap.colorBlendFactor = 0.5
tileMap.setTileGroup(groupA, andTileDefinition: tileA, forColumn: 0, row: 0)
tileMap.setTileGroup(groupA, andTileDefinition: tileB, forColumn: 1, row: 0)
tileMap.setTileGroup(groupB, andTileDefinition: tileC, forColumn: 0, row: 1)
tileMap.setTileGroup(sharedGroup, andTileDefinition: tileA, forColumn: 1, row: 1)
func tilePlist(_ root: Any) throws -> [String: Any] {
    let data = try NSKeyedArchiver.archivedData(withRootObject: root, requiringSecureCoding: true)
    guard var plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          var objects = plist["$objects"] as? [Any] else { fatalError("Invalid tile archive") }
    for index in objects.indices where (objects[index] as? String) == imagePath {
        objects[index] = "../SpriteKit/sample.atlas/wide.png"
    }
    plist["$objects"] = objects
    return plist
}
let tileArchive = try tilePlist(tileMap)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: tileArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("tiles." + suffix))
}
try PropertyListSerialization.data(fromPropertyList: tilePlist([tileSet]), format: .binary, options: 0)
    .write(to: directory.appendingPathComponent("tilesets.sks"))
// Editor scenes store only a tile-set name; preserve native cells and replace the embedded reference.
var externalArchive = tileArchive
guard var tileObjects = externalArchive["$objects"] as? [Any],
      let nullReference = (tileObjects[1] as? [String: Any])?["_userData"] else { fatalError("Invalid tile objects") }
for index in tileObjects.indices {
    guard var object = tileObjects[index] as? [String: Any], object["_rawTiles"] != nil else { continue }
    object["_tileSet"] = nullReference
    object["_tileSetName"] = "Terrain"
    tileObjects[index] = object
}
externalArchive["$objects"] = tileObjects
try PropertyListSerialization.data(fromPropertyList: externalArchive, format: .binary, options: 0)
    .write(to: directory.appendingPathComponent("tiles-external.sks"))

let croppedTile = SKTexture(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1), in: tileTexture)
let animatedTile = SKTileDefinition(textures: [tileTexture, croppedTile],
    size: CGSize(width: 16, height: 16), timePerFrame: 0.25)
let animatedGroup = SKTileGroup(tileDefinition: animatedTile)
let animatedSet = SKTileSet(tileGroups: [animatedGroup, groupB], tileSetType: .grid)
let animatedMap = SKTileMapNode(tileSet: animatedSet, columns: 3, rows: 1,
    tileSize: CGSize(width: 16, height: 16))
animatedMap.enableAutomapping = false
animatedMap.setTileGroup(animatedGroup, forColumn: 0, row: 0)
animatedMap.setTileGroup(animatedGroup, forColumn: 1, row: 0)
animatedMap.setTileGroup(groupB, forColumn: 2, row: 0)
let animatedArchive = try tilePlist(animatedMap)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: animatedArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("tiles-animated." + suffix))
}

let colorEmitter = SKEmitterNode()
colorEmitter.particleBirthRate = 1
colorEmitter.particleLifetime = 2
colorEmitter.numParticlesToEmit = 1
colorEmitter.particleSize = CGSize(width: 8, height: 8)
colorEmitter.particleColorBlendFactor = 1
colorEmitter.particleColorSequence = SKKeyframeSequence(keyframeValues: [
    NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
    NSColor(calibratedWhite: 0.5, alpha: 0.5)
], times: [0, 1])
let colorArchive = try tilePlist(colorEmitter)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: colorArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("emitter-colors." + suffix))
}

colorEmitter.particleColorBlendFactorRange = 1
let blendArchive = try tilePlist(colorEmitter)
try PropertyListSerialization.data(fromPropertyList: blendArchive, format: .binary, options: 0)
    .write(to: directory.appendingPathComponent("emitter-blend.sks"))

let textureSizedEmitter = SKEmitterNode()
textureSizedEmitter.particleTexture = tileTexture
textureSizedEmitter.particleBirthRate = 1
textureSizedEmitter.numParticlesToEmit = 1
textureSizedEmitter.particleLifetime = 10
let textureSizedArchive = try tilePlist(textureSizedEmitter)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: textureSizedArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("emitter-texture-size." + suffix))
}

let animationScene = SKScene(size: CGSize(width: 100, height: 100))
for (name, restore) in [("once", false), ("restore", true), ("loop", false), ("fixed", false)] {
    let originalTexture = SKTexture(rect: CGRect(x: 0, y: 0, width: 0.25, height: 1), in: tileTexture)
    let sprite = SKSpriteNode(texture: originalTexture, size: CGSize(width: 12, height: 8))
    sprite.name = name
    let flipbook = SKAction.animate(with: [croppedTile, tileTexture], timePerFrame: 0.25,
        resize: name != "fixed", restore: restore)
    let action = name == "loop" ? SKAction.repeatForever(SKAction.group([flipbook]))
        : SKAction.sequence([SKAction.wait(forDuration: 0.25), flipbook])
    sprite.run(action, withKey: "flipbook")
    animationScene.addChild(sprite)
}
let animationArchive = try tilePlist(animationScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: animationArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("texture-actions." + suffix))
}

let screenScene = SKScene(size: CGSize(width: 100, height: 100))
let screenSprite = SKSpriteNode(texture: tileTexture)
screenSprite.blendMode = .screen
screenScene.addChild(screenSprite)
let screenEmitter = SKEmitterNode()
screenEmitter.particleBirthRate = 1
screenEmitter.particleLifetime = 10
screenEmitter.particleSize = CGSize(width: 8, height: 8)
screenEmitter.particleBlendMode = .screen
screenScene.addChild(screenEmitter)
let screenArchive = try tilePlist(screenScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: screenArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("screen-blend." + suffix))
}

let actionLibrary = try tilePlist(["actions": [
    "Move": SKAction.moveBy(x: 20, y: 10, duration: 1),
    "Flipbook": SKAction.animate(with: [croppedTile, tileTexture], timePerFrame: 0.25)
]])
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: actionLibrary, format: format, options: 0)
        .write(to: directory.appendingPathComponent("action-library." + suffix))
}

let referenceTarget = SKScene(size: CGSize(width: 100, height: 100))
let referencedSprite = SKSpriteNode(texture: tileTexture)
referencedSprite.name = "content"
referencedSprite.position = CGPoint(x: 5, y: 7)
referenceTarget.addChild(referencedSprite)
let referenceScene = SKScene(size: CGSize(width: 200, height: 100))
for x in [20, 80] {
    guard let reference = SKReferenceNode(fileNamed: "ReferenceTarget") else { fatalError("Missing reference node") }
    reference.name = "instance-\(x)"
    reference.position = CGPoint(x: x, y: 10)
    referenceScene.addChild(reference)
}
for (name, root) in [("references", referenceScene), ("reference-target", referenceTarget)] {
    let archive = try tilePlist(root)
    for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
        try PropertyListSerialization.data(fromPropertyList: archive, format: format, options: 0)
            .write(to: directory.appendingPathComponent(name + "." + suffix))
    }
}

// Set duration explicitly so generation does not depend on a bundled audio asset.
let waitingSound = SKAction.playSoundFileNamed("beep.wav", waitForCompletion: true)
waitingSound.duration = 0.25
let immediateSound = SKAction.playSoundFileNamed("beep.wav", waitForCompletion: false)
let soundScene = SKScene(size: CGSize(width: 100, height: 100))
for (name, action) in [("waiting", waitingSound), ("immediate", immediateSound)] {
    let node = SKNode()
    node.name = name
    node.run(SKAction.sequence([action, SKAction.moveBy(x: 10, y: 0, duration: 0.25)]), withKey: "sound")
    soundScene.addChild(node)
}
for (name, root): (String, Any) in [("sound-actions", soundScene),
    ("sound-library", ["actions": ["Beep": SKAction.repeat(waitingSound, count: 2)]])] {
    let archive = try tilePlist(root)
    for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
        try PropertyListSerialization.data(fromPropertyList: archive, format: format, options: 0)
            .write(to: directory.appendingPathComponent(name + "." + suffix))
    }
}

let compoundScene = SKScene(size: CGSize(width: 200, height: 200))
compoundScene.physicsWorld.gravity = .zero
let compoundNode = SKNode()
compoundNode.physicsBody = SKPhysicsBody(bodies: [
    SKPhysicsBody(circleOfRadius: 12, center: CGPoint(x: 2, y: 3)),
    SKPhysicsBody(rectangleOf: CGSize(width: 30, height: 20), center: CGPoint(x: 40, y: 5))
])
compoundNode.physicsBody?.mass = 2
compoundNode.physicsBody?.linearDamping = 0
compoundNode.physicsBody?.velocity = CGVector(dx: 10, dy: 0)
compoundScene.addChild(compoundNode)
let compoundArchive = try tilePlist(compoundScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: compoundArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("compound-physics." + suffix))
}

let edgeScene = SKScene(size: CGSize(width: 400, height: 200))
let edgePath = CGMutablePath()
edgePath.move(to: CGPoint(x: 10, y: 20))
edgePath.addLine(to: CGPoint(x: 40, y: 20))
edgePath.addLine(to: CGPoint(x: 40, y: 60))
let edgeBodies = [
    SKPhysicsBody(edgeFrom: CGPoint(x: 2, y: 3), to: CGPoint(x: 40, y: 5)),
    SKPhysicsBody(edgeChainFrom: edgePath),
    SKPhysicsBody(edgeLoopFrom: edgePath),
    SKPhysicsBody(edgeLoopFrom: CGRect(x: 10, y: 20, width: 30, height: 40))
]
for (index, body) in edgeBodies.enumerated() {
    let node = SKNode()
    node.position.x = CGFloat(index * 100)
    node.physicsBody = body
    body.velocity = CGVector(dx: 10, dy: 20)
    body.angularVelocity = 1
    edgeScene.addChild(node)
}
let edgeArchive = try tilePlist(edgeScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: edgeArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("edge-physics." + suffix))
}

let pinnedScene = SKScene(size: CGSize(width: 400, height: 400))
let pinnedNode = SKNode()
pinnedNode.position = CGPoint(x: 100, y: 200)
pinnedNode.physicsBody = SKPhysicsBody(circleOfRadius: 12, center: CGPoint(x: 30, y: 0))
pinnedNode.physicsBody?.pinned = true
pinnedNode.physicsBody?.angularDamping = 0
pinnedScene.addChild(pinnedNode)
let pinnedArchive = try tilePlist(pinnedScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: pinnedArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("pinned-physics." + suffix))
}

@objc(FixtureGameScene) final class FixtureGameScene: SKScene {
    override class var supportsSecureCoding: Bool { true }
    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(42, forKey: "customScore")
    }
}
@objc(FixtureGameSprite) final class FixtureGameSprite: SKSpriteNode {
    override class var supportsSecureCoding: Bool { true }
}
let customScene = FixtureGameScene(size: CGSize(width: 320, height: 240))
customScene.name = "custom-scene"
let customSprite = FixtureGameSprite(color: .red, size: CGSize(width: 20, height: 30))
customSprite.name = "custom-sprite"
customSprite.position = CGPoint(x: 40, y: 50)
customScene.addChild(customSprite)
let customArchive = try tilePlist(customScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: customArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("custom-classes." + suffix))
}

let colorScene = SKScene(size: CGSize(width: 200, height: 100))
let colorActions = [
    SKAction.colorize(with: .red, colorBlendFactor: 0.75, duration: 2),
    SKAction.colorize(withColorBlendFactor: 0.2, duration: 2),
    SKAction.repeat(SKAction.sequence([
        SKAction.colorize(with: .red, colorBlendFactor: 1, duration: 0.5),
        SKAction.colorize(with: .blue, colorBlendFactor: 0, duration: 0.5)
    ]), count: 2)
]
for (index, action) in colorActions.enumerated() {
    let sprite = SKSpriteNode(color: .blue, size: CGSize(width: 20, height: 20))
    sprite.colorBlendFactor = index == 1 ? 0.8 : 0
    sprite.position.x = CGFloat(index * 40)
    sprite.run(action, withKey: "color")
    colorScene.addChild(sprite)
}
let colorActionArchive = try tilePlist(colorScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: colorActionArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("color-actions." + suffix))
}
let axisScaleScene = SKScene(size: CGSize(width: 200, height: 100))
for action in [
    SKAction.scaleX(to: 4, duration: 2),
    SKAction.scaleY(to: -2, duration: 2),
    SKAction.group([SKAction.scaleX(to: 4, duration: 2), SKAction.scaleY(to: -2, duration: 2)])
] {
    let node = SKNode()
    node.xScale = 2
    node.yScale = 3
    node.run(action, withKey: "scale")
    axisScaleScene.addChild(node)
}
let axisScaleArchive = try tilePlist(axisScaleScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: axisScaleArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("axis-scale-actions." + suffix))
}

let resizeScene = SKScene(size: CGSize(width: 200, height: 100))
for action in [
    SKAction.resize(toWidth: 40, height: 60, duration: 2),
    SKAction.resize(toWidth: 40, duration: 2),
    SKAction.resize(toHeight: 60, duration: 2),
    SKAction.group([SKAction.resize(toWidth: 40, duration: 2), SKAction.resize(toHeight: 60, duration: 2)]),
    SKAction.resize(byWidth: 10, height: -10, duration: 2),
    SKAction.repeat(SKAction.resize(byWidth: 10, height: -5, duration: 1), count: 2)
] {
    let sprite = SKSpriteNode(color: .blue, size: CGSize(width: 20, height: 30))
    sprite.run(action, withKey: "resize")
    resizeScene.addChild(sprite)
}
let resizeArchive = try tilePlist(resizeScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: resizeArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("resize-actions." + suffix))
}

let sizeScaleScene = SKScene(size: CGSize(width: 200, height: 100))
for action in [
    SKAction.scale(to: CGSize(width: 80, height: 90), duration: 2),
    SKAction.sequence([
        SKAction.resize(toWidth: 40, height: 60, duration: 1),
        SKAction.scale(to: CGSize(width: 80, height: 120), duration: 1)
    ])
] {
    let sprite = SKSpriteNode(color: .blue, size: CGSize(width: 20, height: 30))
    sprite.xScale = 2
    sprite.yScale = 1
    sprite.run(action, withKey: "size-scale")
    sizeScaleScene.addChild(sprite)
}
let sizeScaleArchive = try tilePlist(sizeScaleScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: sizeScaleArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("size-scale-actions." + suffix))
}

let setTextureScene = SKScene(size: CGSize(width: 100, height: 100))
for resize in [false, true] {
    let sprite = SKSpriteNode(color: .white, size: CGSize(width: 12, height: 8))
    sprite.run(.sequence([
        .wait(forDuration: 0.5),
        .setTexture(croppedTile, resize: resize),
        .wait(forDuration: 0.5),
        .setTexture(tileTexture, resize: resize)
    ]), withKey: "texture")
    setTextureScene.addChild(sprite)
}
let setTextureArchive = try tilePlist(setTextureScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: setTextureArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("set-texture-actions." + suffix))
}

let speedScene = SKScene(size: CGSize(width: 100, height: 100))
for (initialSpeed, action) in [
    (CGFloat(1), SKAction.speed(to: 2, duration: 2)),
    (CGFloat(2), SKAction.speed(by: 0.5, duration: 2)),
    (CGFloat(1), SKAction.speed(to: 0, duration: 0))
] {
    let node = SKNode()
    node.speed = initialSpeed
    node.run(action, withKey: "speed")
    speedScene.addChild(node)
}
let speedArchive = try tilePlist(speedScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: speedArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("speed-actions." + suffix))
}

let reversedScene = SKScene(size: CGSize(width: 100, height: 100))
for action in [
    SKAction.moveBy(x: 10, y: -20, duration: 2),
    SKAction.rotate(byAngle: 1, duration: 2),
    SKAction.resize(byWidth: 10, height: -10, duration: 2)
] {
    let sprite = SKSpriteNode(color: .white, size: CGSize(width: 20, height: 30))
    sprite.position = CGPoint(x: 5, y: 7)
    sprite.zRotation = 0.5
    sprite.run(.sequence([action.reversed(), action]), withKey: "round-trip")
    reversedScene.addChild(sprite)
}
let reversedArchive = try tilePlist(reversedScene)
for (suffix, format) in [("sks", PropertyListSerialization.PropertyListFormat.binary), ("xml", .xml)] {
    try PropertyListSerialization.data(fromPropertyList: reversedArchive, format: format, options: 0)
        .write(to: directory.appendingPathComponent("reversed-actions." + suffix))
}
