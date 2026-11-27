import Foundation
import SpriteCore
import SpriteGraph

public enum SceneArchiveError: Error, Equatable, Sendable {
    case invalid(String)
    case unsupported(String)
    case missingTexture(String)
    case missingFont(String)
    case missingTileSet(String)
}

/// Reads binary or XML SpriteKit keyed archives through Foundation.
/// Archived classes are never instantiated; supported nodes are built in SpriteGraph.
public struct SpriteKitSceneArchive: Sendable {
    public struct TextureReference: Hashable, Sendable {
        public let imageName: String
        public let atlasName: String?
        public let subtextureName: String?
        public let filtering: TextureFiltering
    }

    private struct Record: Sendable {
        let id: Int
        let className: String
        var name: String?
        var position = Vector2.zero
        var scale = Vector2.one
        var rotation: Float = 0
        var zPosition: Float = 0
        var alpha: Float = 1
        var hidden = false
        var paused = false
        var speed: Float = 1
        var children: [Int] = []
        var size = Vector2.zero
        var anchor = Vector2.zero
        var color = Color.white
        var blend: BlendMode = .alpha
        var colorBlend: Float = 0
        var centerRect = Rect.unit
        var texture: TextureReference?
        var textureRect = Rect.unit
        var scaleMode: Scene.ScaleMode = .aspectFill
        var camera: Int?
        var text = ""
        var fontName = ""
        var fontSize: Float = 32
        var horizontal: Label.HorizontalAlignment = .center
        var vertical: Label.VerticalAlignment = .baseline
        var lineCount = 1
        var layoutWidth: Float = 0
        var tileMap: ArchiveTileMap?
        var emitter: ArchiveEmitter?
        var target: Int?
        var actions: [ArchiveNodeAction] = []
        var physicsBody: ArchivePhysicsBody?
        var physicsWorld: ArchivePhysicsWorld?
    }

    private let rootID: Int
    private let records: [Record]
    /// Describes deliberately omitted metadata.
    public let diagnostics: [String]

    public static func decode(at url: URL) async throws -> SpriteKitSceneArchive {
        try await Task.detached { try decode(Data(contentsOf: url)) }.value
    }

    public static func decode(_ data: Data) throws -> SpriteKitSceneArchive {
        let graph = try KeyedArchive(ArchivePropertyList.decode(data))
        var records: [Record] = []
        var seen = Set<Int>()
        var seenBodies = Set<Int>()
        var actionDecoder = ArchiveActionDecoder(graph: graph)
        var diagnostics: [String] = []

        func visit(_ id: Int, depth: Int, scaledAncestor: Bool = false) throws {
            guard depth < 128, seen.count < 100_000, seen.insert(id).inserted else {
                throw SceneArchiveError.invalid("Cyclic, shared, or excessively deep node hierarchy")
            }
            let fields = try graph.dictionary(.uid(id))
            let className = try graph.className(fields)
            guard ["SKScene", "SKNode", "SKSpriteNode", "SKCameraNode", "SKLabelNode", "SKEmitterNode", "SKTileMapNode"].contains(className) else {
                throw SceneArchiveError.unsupported("Node class \(className) at object \(id)")
            }
            if className == "SKScene", id != graph.rootID {
                throw SceneArchiveError.invalid("A scene cannot be a child node")
            }
            for key in ["_constraints", "_reachConstraints",
                        "_shader", "_filter", "_normalTexture", "_warpGeometry", "_attributedText"] {
                guard try graph.isEmpty(fields[key]) else {
                    throw SceneArchiveError.unsupported("\(className).\(key)")
                }
            }
            for key in ["_xRotation", "_yRotation", "_lightingBitMask", "_shadowCastBitMask", "_shadowedBitMask"] {
                guard try graph.number(fields[key], default: 0) == 0 else {
                    throw SceneArchiveError.unsupported("\(className).\(key)")
                }
            }
            for key in ["_shouldEnableEffects", "_shouldRasterize"] {
                guard try !graph.boolean(fields[key], default: false) else {
                    throw SceneArchiveError.unsupported("\(className).\(key)")
                }
            }
            if try !graph.isEmpty(fields["_userData"]) {
                diagnostics.append("Object \(id): userData is not imported.")
            }
            var record = Record(id: id, className: className)
            record.actions = try actionDecoder.actions(fields)
            if let body = fields["_PKPhysicsBody"], try !graph.isNull(body) {
                guard seenBodies.insert(try graph.reference(body, field: "_PKPhysicsBody")).inserted else {
                    throw SceneArchiveError.invalid("Physics body shared by multiple nodes")
                }
                record.physicsBody = try ArchivePhysicsBody(body, graph: graph)
            }
            record.name = try graph.string(fields["_name"])
            record.position = try graph.vector(fields["_position"], default: .zero)
            record.scale = try Vector2(graph.number(fields["_xScale"], default: 1), graph.number(fields["_yScale"], default: 1))
            let scaled = scaledAncestor || record.scale != .one
            if record.physicsBody != nil, scaled {
                throw SceneArchiveError.unsupported("Physics bodies under scaled nodes")
            }
            record.rotation = try graph.number(fields["_zRotation"], default: 0)
            record.zPosition = try graph.number(fields["_zPosition"], default: 0)
            record.alpha = try graph.number(fields["_opacity"], default: 1)
            record.hidden = try graph.boolean(fields["_hidden"], default: false)
            record.paused = try graph.boolean(fields["_paused"], default: false)
            record.speed = try graph.number(fields["_speed"], default: 1)
            record.children = try graph.array(fields["_children"]).map { try graph.reference($0, field: "_children") }
            switch className {
            case "SKScene":
                record.size = try graph.rect(fields["Scene_bounds"], default: .zero).size
                guard record.size.x > 0, record.size.y > 0 else { throw SceneArchiveError.invalid("Invalid scene size") }
                record.anchor = try graph.vector(fields["_anchorPoint"], default: .zero)
                record.color = try graph.color(fields, prefix: "_backgroundColor")
                switch try graph.number(fields["_scaleMode"], default: 1) {
                case 0: record.scaleMode = .fill
                case 1: record.scaleMode = .aspectFill
                case 2: record.scaleMode = .aspectFit
                case 3: record.scaleMode = .resizeFill
                default: throw SceneArchiveError.unsupported("Scene scale mode")
                }
                if try !graph.isNull(fields["_camera"]) {
                    record.camera = try graph.reference(fields["_camera"], field: "_camera")
                }
                if let world = fields["_physicsWorld"], try !graph.isNull(world) {
                    record.physicsWorld = try ArchivePhysicsWorld(world, graph: graph)
                }
            case "SKSpriteNode":
                record.size = try graph.rect(fields["_bounds"], default: .zero).size
                guard record.size.x >= 0, record.size.y >= 0 else { throw SceneArchiveError.invalid("Invalid sprite size") }
                record.anchor = try graph.vector(fields["_anchorPoint"], default: [0.5, 0.5])
                record.color = try graph.color(fields, prefix: "_baseColor")
                record.colorBlend = try graph.number(fields["_colorMix"], default: 0)
                record.blend = try graph.blend(fields["_blendMode"])
                let center = try graph.rect(fields["_centerRect"], default: .unit)
                try graph.validateUnitRect(center)
                // SpriteKit unit rectangles are Y-up; engine texture rectangles are Y-down.
                record.centerRect = Rect(x: center.minX, y: 1 - center.maxY, width: center.width, height: center.height)
            case "SKLabelNode":
                record.text = try graph.string(fields["_text"]) ?? ""
                record.fontName = try graph.string(fields["_fontName"]) ?? ""
                record.fontSize = try graph.number(fields["_fontSize"], default: 32)
                guard record.fontSize > 0 else { throw SceneArchiveError.invalid("Invalid label font size") }
                record.color = try graph.color(fields, prefix: "_fontColor")
                record.blend = try graph.blend(fields["_labelBlendMode"])
                guard try graph.number(fields["_labelColorBlend"], default: 0) == 0 else {
                    throw SceneArchiveError.unsupported("Label color blending")
                }
                switch try graph.number(fields["_horizontalAlignmentMode"], default: 0) {
                case 0: record.horizontal = .center
                case 1: record.horizontal = .left
                case 2: record.horizontal = .right
                default: throw SceneArchiveError.invalid("Label horizontal alignment")
                }
                switch try graph.number(fields["_verticalAlignmentMode"], default: 0) {
                case 0: record.vertical = .baseline
                case 1: record.vertical = .center
                case 2: record.vertical = .top
                case 3: record.vertical = .bottom
                default: throw SceneArchiveError.invalid("Label vertical alignment")
                }
                let lines = try graph.number(fields["_numberOfLines"], default: 1)
                guard lines >= 0, lines <= 100_000, lines.rounded() == lines else {
                    throw SceneArchiveError.invalid("Label line count")
                }
                record.lineCount = Int(lines)
                record.layoutWidth = try graph.number(fields["_preferredMaxLayoutWidth"], default: 0)
            default: break
            }
            if className == "SKTileMapNode" {
                record.tileMap = try ArchiveTileMap(fields, graph: graph)
            }
            if className == "SKEmitterNode" {
                record.emitter = try ArchiveEmitter(fields, graph: graph)
                if try !graph.isNull(fields["_target"]) {
                    record.target = try graph.reference(fields["_target"], field: "_target")
                }
            }
            let textureValue = className == "SKEmitterNode" ? fields["_particleTexture"] : (className == "SKSpriteNode" ? fields["_texture"] : nil)
            if let value = textureValue, try !graph.isNull(value) {
                let texture = try ArchiveTexture(value, graph: graph)
                record.texture = texture.reference
                record.textureRect = texture.rect
            }
            records.append(record)
            for child in record.children { try visit(child, depth: depth + 1, scaledAncestor: scaled) }
        }
        try visit(graph.rootID, depth: 0)
        for record in records {
            if let target = record.target, !seen.contains(target) {
                throw SceneArchiveError.invalid("Emitter target must reference a node in the archive tree")
            }
            if let camera = record.camera, !records.contains(where: { $0.id == camera && $0.className == "SKCameraNode" }) {
                throw SceneArchiveError.invalid("Scene camera must reference a camera in the node tree")
            }
        }
        return SpriteKitSceneArchive(rootID: graph.rootID, records: records, diagnostics: diagnostics)
    }

    /// Resolvers supply backend-owned textures and bitmap/SDF fonts.
    /// Return the named image or atlas entry before the archive's texture-rect crop.
    @MainActor public func makeNode(
        textureResolver: (TextureReference) throws -> Texture? = { _ in nil },
        fontResolver: (String) throws -> BitmapFont? = { _ in nil },
        tileSetResolver: (String) throws -> SpriteKitTileSetArchive? = { _ in nil }
    ) throws -> Node {
        var nodes: [Int: Node] = [:]
        var textures: [TextureReference: Texture] = [:]
        var fonts: [String: BitmapFont] = [:]
        var tileSets: [String: SpriteKitTileSetArchive] = [:]
        func resolveTexture(_ reference: TextureReference, rect: Rect) throws -> Texture {
            if textures[reference] == nil {
                guard let texture = try textureResolver(reference) else {
                    throw SceneArchiveError.missingTexture(reference.imageName)
                }
                textures[reference] = texture
            }
            guard let texture = textures[reference] else { throw SceneArchiveError.missingTexture(reference.imageName) }
            return texture.subtexture(inUnitRect: rect)
        }
        for record in records {
            var texture: Texture?
            if let reference = record.texture { texture = try resolveTexture(reference, rect: record.textureRect) }
            let node: Node
            switch record.className {
            case "SKScene":
                let scene = Scene(size: record.size)
                scene.scaleMode = record.scaleMode
                scene.anchorPoint = record.anchor
                scene.backgroundColor = record.color
                if let world = record.physicsWorld {
                    scene.physicsWorld.gravity = world.gravity
                    scene.physicsWorld.speed = world.speed
                }
                node = scene
            case "SKSpriteNode":
                let sprite = Sprite(texture: texture, color: record.color, size: record.size)
                sprite.anchorPoint = record.anchor
                sprite.colorBlendFactor = record.colorBlend
                sprite.centerRect = record.centerRect
                sprite.blendMode = record.blend
                node = sprite
            case "SKLabelNode":
                if fonts[record.fontName] == nil, !record.text.isEmpty {
                    guard let font = try fontResolver(record.fontName) else {
                        throw SceneArchiveError.missingFont(record.fontName)
                    }
                    fonts[record.fontName] = font
                }
                let label = Label(text: record.text, font: fonts[record.fontName], fontSize: record.fontSize)
                label.color = record.color
                label.blendMode = record.blend
                label.horizontalAlignmentMode = record.horizontal
                label.verticalAlignmentMode = record.vertical
                label.numberOfLines = record.lineCount
                label.preferredMaxLayoutWidth = record.layoutWidth
                node = label
            case "SKTileMapNode":
                guard let map = record.tileMap else { throw SceneArchiveError.invalid("Missing tile map") }
                let set: SpriteKitTileSetArchive
                if let embedded = map.tileSet { set = embedded }
                else {
                    guard let name = map.tileSetName else { throw SceneArchiveError.invalid("Missing tile set name") }
                    if tileSets[name] == nil {
                        guard let resolved = try tileSetResolver(name) else { throw SceneArchiveError.missingTileSet(name) }
                        tileSets[name] = resolved
                    }
                    guard let resolved = tileSets[name] else { throw SceneArchiveError.missingTileSet(name) }
                    set = resolved
                }
                node = try map.makeNode(set: set) { try resolveTexture($0.reference, rect: $0.rect) }
            case "SKEmitterNode":
                guard let emitter = record.emitter else { throw SceneArchiveError.invalid("Missing emitter settings") }
                node = emitter.makeEmitter(texture: texture)
            case "SKCameraNode": node = Camera()
            default: node = Node()
            }
            node.name = record.name
            node.position = record.position
            node.scale = record.scale
            node.zRotation = record.rotation
            node.zPosition = record.zPosition
            node.alpha = record.alpha
            node.isHidden = record.hidden
            node.isPaused = record.paused
            node.speed = record.speed
            node.physicsBody = record.physicsBody?.makeBody()
            for action in record.actions { node.run(action.action, withKey: action.key) }
            nodes[record.id] = node
        }
        for record in records {
            guard let parent = nodes[record.id] else { throw SceneArchiveError.invalid("Missing node") }
            for child in record.children {
                guard let node = nodes[child] else { throw SceneArchiveError.invalid("Missing child") }
                parent.addChild(node)
            }
            if let emitter = parent as? ParticleEmitter, let target = record.target {
                emitter.targetNode = nodes[target]
            }
            if let scene = parent as? Scene, let camera = record.camera {
                scene.camera = nodes[camera] as? Camera
            }
        }
        guard let root = nodes[rootID] else { throw SceneArchiveError.invalid("Missing root") }
        return root
    }
}
