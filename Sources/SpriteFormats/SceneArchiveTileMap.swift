import Foundation
import SpriteCore
import SpriteGraph

/// A SpriteKit tile set's baked definitions, usable with named tile-map references.
public struct SpriteKitTileSetArchive: Sendable {
    public let name: String?
    struct Definition: Sendable {
        let textures: [ArchiveTexture]
        let timePerFrame: Double
        let size: Vector2
    }
    let definitions: [Definition]
    let groups: [Set<Int>]

    /// Reads a standalone tile-set archive or the array stored in an editor TileSets.sks file.
    public static func decode(_ data: Data) throws -> [SpriteKitTileSetArchive] {
        let graph = try KeyedArchive(ArchivePropertyList.decode(data))
        let root = try graph.dictionary(.uid(graph.rootID))
        if try graph.className(root) == "SKTileSet" { return [try Self(.uid(graph.rootID), graph: graph)] }
        return try graph.array(.uid(graph.rootID)).map { try Self($0, graph: graph) }
    }

    public static func decode(at url: URL) async throws -> [SpriteKitTileSetArchive] {
        try await Task.detached { try decode(Data(contentsOf: url)) }.value
    }

    init(_ value: PropertyValue, graph: KeyedArchive) throws {
        let fields = try graph.dictionary(value)
        guard try graph.className(fields) == "SKTileSet", try graph.number(fields["_type"], default: -1) == 0 else {
            throw SceneArchiveError.unsupported("Only grid tile sets are supported")
        }
        name = try graph.string(fields["_name"])
        let groupValues = try graph.array(fields["_groups"])
        guard groupValues.count <= 32767 else { throw SceneArchiveError.invalid("Too many tile groups") }
        var definitions: [Definition] = []
        var indices: [Int: Int] = [:]
        var groups: [Set<Int>] = []
        var budget = 100_000
        for groupValue in groupValues {
            let group = try graph.dictionary(groupValue)
            guard try graph.className(group) == "SKTileGroup" else { throw SceneArchiveError.unsupported("Tile group class") }
            var members = Set<Int>()
            for ruleValue in try graph.array(group["_rules"]) {
                budget -= 1
                guard budget >= 0 else { throw SceneArchiveError.invalid("Excessive tile rules") }
                let rule = try graph.dictionary(ruleValue)
                guard try graph.className(rule) == "SKTileGroupRule" else { throw SceneArchiveError.unsupported("Tile rule class") }
                for definitionValue in try graph.array(rule["_tileDefinitions"]) {
                    budget -= 1
                    guard budget >= 0 else { throw SceneArchiveError.invalid("Excessive tile definitions") }
                    let id = try graph.reference(definitionValue, field: "_tileDefinitions")
                    if let index = indices[id] { members.insert(index); continue }
                    guard definitions.count < 65535 else { throw SceneArchiveError.invalid("Too many tile definitions") }
                    let definition = try graph.dictionary(definitionValue)
                    guard try graph.className(definition) == "SKTileDefinition" else {
                        throw SceneArchiveError.unsupported("Tile definition class")
                    }
                    let textures = try graph.array(definition["_textures"])
                    guard !textures.isEmpty, textures.count <= 4096 else {
                        throw SceneArchiveError.invalid("Invalid tile animation frame count")
                    }
                    budget -= textures.count
                    guard budget >= 0 else { throw SceneArchiveError.invalid("Excessive tile animation frames") }
                    guard try graph.array(definition["_normals"]).isEmpty,
                          try graph.number(definition["_orientation"], default: 0) == 0 else {
                        throw SceneArchiveError.unsupported("Oriented or normal-mapped tile definition")
                    }
                    let timePerFrame = Double(try graph.number(definition["_timePerFrame"], default: 0))
                    guard timePerFrame >= 0, timePerFrame <= 31_536_000,
                          textures.count == 1 || timePerFrame >= 1e-9 else {
                        throw SceneArchiveError.invalid("Invalid tile animation frame duration")
                    }
                    let size = try Vector2(graph.number(definition["_width"], default: 0), graph.number(definition["_height"], default: 0))
                    guard size.x > 0, size.y > 0 else { throw SceneArchiveError.invalid("Invalid tile definition size") }
                    let index = definitions.count
                    indices[id] = index
                    members.insert(index)
                    definitions.append(Definition(textures: try textures.map { try ArchiveTexture($0, graph: graph) },
                                                  timePerFrame: timePerFrame, size: size))
                }
            }
            groups.append(members)
        }
        self.definitions = definitions
        self.groups = groups
    }
}

struct ArchiveTileMap: Sendable {
    let columns: Int
    let rows: Int
    let size: Vector2
    let anchor: Vector2
    let color: Color
    let blend: BlendMode
    let tileSet: SpriteKitTileSetArchive?
    let tileSetName: String?
    let cells: [UInt32]

    init(_ fields: [String: PropertyValue], graph: KeyedArchive) throws {
        func dimension(_ key: String) throws -> Int {
            let value = try graph.number(fields[key], default: 0)
            guard value > 0, value <= 1_000_000, value.rounded() == value else {
                throw SceneArchiveError.invalid("Invalid tile map dimension")
            }
            return Int(value)
        }
        columns = try dimension("_currentColumns")
        rows = try dimension("_currentRows")
        guard columns * rows <= 1_000_000 else { throw SceneArchiveError.invalid("Tile map exceeds cell limit") }
        size = try Vector2(graph.number(fields["_tileWidth"], default: 0), graph.number(fields["_tileHeight"], default: 0))
        guard size.x > 0, size.y > 0, (size * Vector2(Float(columns), Float(rows))).x.isFinite,
              (size * Vector2(Float(columns), Float(rows))).y.isFinite else {
            throw SceneArchiveError.invalid("Invalid tile map size")
        }
        anchor = try graph.vector(fields["_anchorPoint"], default: [0.5, 0.5])
        let mix = try graph.number(fields["_colorMix"], default: 0)
        guard mix >= 0, mix <= 1 else { throw SceneArchiveError.invalid("Invalid tile map color blend") }
        color = try Color.white.mix(with: graph.color(fields, prefix: "_baseColor"), fraction: mix)
        blend = try graph.blend(fields["_blendMode"])
        if let value = fields["_tileSet"], try !graph.isNull(value) {
            tileSet = try SpriteKitTileSetArchive(value, graph: graph)
        } else { tileSet = nil }
        tileSetName = try graph.string(fields["_tileSetName"])
        guard tileSet != nil || !(tileSetName ?? "").isEmpty else {
            throw SceneArchiveError.invalid("Missing tile set or tile set name")
        }
        guard case let .data(data) = try graph.resolve(fields["_rawTiles"]), data.count == columns * rows * 4 else {
            throw SceneArchiveError.invalid("Invalid tile cell data length")
        }
        // Native archives store little-endian words: group index in the high half,
        // unique definition index in the low half. Row zero is the bottom row.
        let bytes = Array(data)
        cells = stride(from: 0, to: bytes.count, by: 4).map { offset in
            UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        }
        if let tileSet { try validate(tileSet) }
    }

    func validate(_ set: SpriteKitTileSetArchive) throws {
        for cell in cells where cell != 0x7fffffff {
            let group = Int(cell >> 16), definition = Int(cell & 0xffff)
            guard set.groups.indices.contains(group), set.groups[group].contains(definition) else {
                throw SceneArchiveError.invalid("Tile cell references an unknown group or definition")
            }
            guard set.definitions[definition].size == size else {
                throw SceneArchiveError.unsupported("Tile definition size differs from the map cell size")
            }
        }
    }

    @MainActor func makeNode(set: SpriteKitTileSetArchive,
                            texture: (ArchiveTexture) throws -> Texture) throws -> TileMap {
        try validate(set)
        var textures: [UInt32: Texture] = [:]
        var animations: [UInt32: TileAnimation] = [:]
        for cell in cells where cell != 0x7fffffff {
            let id = cell & 0xffff
            if textures[id] == nil {
                let definition = set.definitions[Int(id)]
                let frames = try definition.textures.map(texture)
                textures[id] = frames[0]
                if frames.count > 1 {
                    guard let animation = TileAnimation(textures: frames, timePerFrame: .seconds(definition.timePerFrame)) else {
                        throw SceneArchiveError.invalid("Invalid tile animation")
                    }
                    animations[id] = animation
                }
            }
        }
        let map = TileMap(tileSet: TileSet(textures: textures, animations: animations), columns: columns, rows: rows, tileSize: size)
        map.anchorPoint = anchor
        map.color = color
        map.blendMode = blend
        for (index, cell) in cells.enumerated() where cell != 0x7fffffff {
            map[index % columns, index / columns] = Tile(id: cell & 0xffff)
        }
        return map
    }
}
