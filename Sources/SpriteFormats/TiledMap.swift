import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import SpriteCore
import SpriteGraph

public enum TiledError: Error, Equatable, Sendable {
    case invalid(String)
    case unsupported(String)
}

/// Decoded finite orthogonal TMX map. Images are decoded before GPU upload.
public struct TiledMap: Sendable {
    public struct Layer: Sendable {
        public let name: String
        public let tiles: [Tile?]
        public let opacity: Float
        public let isHidden: Bool
        public let offset: Vector2
    }

    private struct Sheet: Sendable {
        let image: PixelBuffer
        let regions: [UInt32: Rect]
    }

    public let columns: Int
    public let rows: Int
    public let tileSize: Vector2
    /// Layers in painter's order; tile arrays use Tiled's top-down row order.
    public let layers: [Layer]
    private let sheets: [Sheet]

    public static func decode(at url: URL) async throws -> TiledMap {
        try await Task.detached {
            try decode(Data(contentsOf: url), relativeTo: url.deletingLastPathComponent())
        }.value
    }

    /// Resource paths are resolved relative to the document that references them.
    public static func decode(
        _ data: Data, relativeTo directory: URL,
        loadResource: (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) throws -> TiledMap {
        let map = try XMLNode.parse(data)
        guard map.name == "map" else { throw TiledError.invalid("Expected map") }
        guard map.attributes["orientation"] == "orthogonal",
              map.attributes["infinite", default: "0"] == "0",
              map.attributes["renderorder", default: "right-down"] == "right-down" else {
            throw TiledError.unsupported("Only finite orthogonal right-down maps are supported")
        }
        let columns = try map.integer("width"), rows = try map.integer("height")
        guard columns > 0, rows > 0, columns <= 4_000_000 / rows else {
            throw TiledError.invalid("Map must contain 1...4,000,000 cells")
        }
        let width = try map.integer("tilewidth"), height = try map.integer("tileheight")
        guard width > 0, height > 0 else { throw TiledError.invalid("Invalid tile dimensions") }
        let tileSize = Vector2(Float(width), Float(height))
        var sheets: [Sheet] = []
        var knownIDs = Set<UInt32>()
        for reference in map.children where reference.name == "tileset" {
            let first = try reference.integer("firstgid")
            var set = reference
            var base = directory
            if let source = reference.attributes["source"] {
                let url = directory.appendingPathComponent(source)
                set = try XMLNode.parse(loadResource(url))
                base = url.deletingLastPathComponent()
            }
            guard set.name == "tileset" else { throw TiledError.invalid("Expected tileset") }
            guard try set.integer("tilewidth") == width, try set.integer("tileheight") == height else {
                throw TiledError.unsupported("Tileset tile size must match the map grid")
            }
            try set.rejectChildren(["tileoffset", "tile", "wangsets"])
            let images = set.children.filter { $0.name == "image" }
            guard images.count == 1, let source = images[0].attributes["source"] else {
                throw TiledError.unsupported("Tilesets require one PNG sheet")
            }
            guard images[0].attributes["trans"] == nil else {
                throw TiledError.unsupported("Image transparency keys")
            }
            let image = try PixelBuffer(png: Array(loadResource(base.appendingPathComponent(source))))
            let count = try set.integer("tilecount"), across = try set.integer("columns")
            let margin = try set.integer("margin", default: 0), spacing = try set.integer("spacing", default: 0)
            guard first > 0, count > 0, count <= 4_000_000, across > 0,
                  margin >= 0, spacing >= 0, first <= 0x0FFF_FFFF - count + 1,
                  width <= image.width, height <= image.height,
                  margin <= image.width, margin <= image.height,
                  spacing <= max(image.width, image.height) else {
                throw TiledError.invalid("Invalid tileset dimensions or IDs")
            }
            var regions: [UInt32: Rect] = [:]
            for index in 0 ..< count {
                let x = margin + (index % across) * (width + spacing)
                let y = margin + (index / across) * (height + spacing)
                guard x <= image.width - width, y <= image.height - height else {
                    throw TiledError.invalid("Tile outside sheet")
                }
                let id = UInt32(first + index)
                guard knownIDs.insert(id).inserted else { throw TiledError.invalid("Overlapping tileset IDs") }
                regions[id] = Rect(x: Float(x), y: Float(y), width: Float(width), height: Float(height))
            }
            sheets.append(Sheet(image: image, regions: regions))
        }
        try map.rejectChildren(["group", "objectgroup", "imagelayer"])
        var layers: [Layer] = []
        for layer in map.children where layer.name == "layer" {
            guard try layer.integer("width") == columns, try layer.integer("height") == rows,
                  try layer.integer("x", default: 0) == 0, try layer.integer("y", default: 0) == 0 else {
                throw TiledError.unsupported("Layer dimensions must match the map")
            }
            guard try layer.number("parallaxx", default: 1) == 1,
                  try layer.number("parallaxy", default: 1) == 1,
                  layer.attributes["tintcolor"] == nil else {
                throw TiledError.unsupported("Layer parallax or tint")
            }
            let payloads = layer.children.filter { $0.name == "data" }
            guard payloads.count == 1 else { throw TiledError.invalid("Expected one layer data element") }
            let payload = payloads[0]
            guard payload.attributes["encoding"] == "csv", payload.attributes["compression"] == nil,
                  payload.children.isEmpty else { throw TiledError.unsupported("Only uncompressed CSV data is supported") }
            let tokens = payload.text.split(separator: ",", omittingEmptySubsequences: false)
            guard tokens.count == columns * rows else { throw TiledError.invalid("Incorrect tile count") }
            let tiles: [Tile?] = try tokens.map { token in
                guard let raw = UInt32(token.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw TiledError.invalid("Invalid global tile ID")
                }
                let id = raw & 0x0FFF_FFFF
                if id == 0 { return nil }
                guard knownIDs.contains(id) else { throw TiledError.invalid("Unknown global tile ID") }
                return Tile(id: id, flipHorizontally: raw & 0x8000_0000 != 0,
                    flipVertically: raw & 0x4000_0000 != 0, flipDiagonally: raw & 0x2000_0000 != 0)
            }
            let opacity = try layer.number("opacity", default: 1)
            guard (0...1).contains(opacity) else { throw TiledError.invalid("Invalid opacity") }
            layers.append(Layer(name: layer.attributes["name", default: ""], tiles: tiles,
                opacity: opacity, isHidden: try layer.integer("visible", default: 1) == 0,
                offset: try Vector2(layer.number("offsetx", default: 0), -layer.number("offsety", default: 0))))
        }
        return TiledMap(columns: columns, rows: rows, tileSize: tileSize, layers: layers, sheets: sheets)
    }

    /// Uploads sheets once and creates one editable TileMap per layer.
    @MainActor public func makeNode(backend: some SpriteRenderBackend) throws -> Node {
        var textures: [UInt32: Texture] = [:]
        for sheet in sheets {
            let texture = try backend.makeTexture(sheet.image, filtering: .nearest)
            for (id, rect) in sheet.regions {
                textures[id] = Texture(id: texture.id, textureSize: texture.textureSize, region: rect)
            }
        }
        let tileSet = TileSet(textures: textures)
        let root = Node()
        for (index, layer) in layers.enumerated() {
            let node = TileMap(tileSet: tileSet, columns: columns, rows: rows, tileSize: tileSize)
            node.name = layer.name
            node.alpha = layer.opacity
            node.isHidden = layer.isHidden
            node.position = layer.offset
            node.zPosition = Float(index)
            for (cell, tile) in layer.tiles.enumerated() {
                node[cell % columns, rows - 1 - cell / columns] = tile
            }
            root.addChild(node)
        }
        return root
    }
}

/// Minimal XML tree; external entities are never resolved.
private final class XMLNode: NSObject, XMLParserDelegate {
    var name = ""
    var attributes: [String: String] = [:]
    var children: [XMLNode] = []
    var text = ""
    private var stack: [XMLNode] = []

    static func parse(_ data: Data) throws -> XMLNode {
        let delegate = XMLNode()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.children.count == 1 else {
            throw TiledError.invalid(parser.parserError?.localizedDescription ?? "Malformed XML")
        }
        return delegate.children[0]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        let node = XMLNode()
        node.name = elementName
        node.attributes = attributeDict
        (stack.last ?? self).children.append(node)
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }

    func integer(_ key: String, default fallback: Int? = nil) throws -> Int {
        if let value = attributes[key], let result = Int(value) { return result }
        if attributes[key] == nil, let fallback { return fallback }
        throw TiledError.invalid("Invalid integer: " + key)
    }

    func number(_ key: String, default fallback: Float) throws -> Float {
        guard let value = attributes[key] else { return fallback }
        guard let result = Float(value), result.isFinite else { throw TiledError.invalid("Invalid number: " + key) }
        return result
    }

    func rejectChildren(_ names: Set<String>) throws {
        if let child = children.first(where: { names.contains($0.name) }) {
            throw TiledError.unsupported(child.name)
        }
    }
}
