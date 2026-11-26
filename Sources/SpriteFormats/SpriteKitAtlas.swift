//
//  SpriteKitAtlas.swift
//  SpriteFormats
//

import Foundation
import SpriteCore

/// SpriteKit texture atlases: compiled `.atlasc` folders (property list + pages)
/// and source `.atlas` folders of individual images.
public enum SpriteKitAtlas {

    /// Parses the property list inside a compiled `.atlasc` folder.
    public static func parse(propertyList data: Data) throws -> AtlasDocument {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = root["images"] as? [[String: Any]] else {
            throw AtlasError.invalidDescription("Missing images array")
        }
        let pages = try images.map { image -> AtlasPage in
            guard let path = image["path"] as? String, let subimages = image["subimages"] as? [[String: Any]] else {
                throw AtlasError.invalidDescription("Invalid image entry")
            }
            let regions = try subimages.map { subimage -> AtlasRegion in
                guard let name = subimage["name"] as? String,
                      let rect = (subimage["textureRect"] as? String).flatMap(parseRect) else {
                    throw AtlasError.invalidDescription("Invalid subimage in \(path)")
                }
                let rotated = subimage["textureRotated"] as? Bool ?? false
                let content = rotated ? Vector2(rect.height, rect.width) : rect.size
                let sourceSize = (subimage["spriteSourceSize"] as? String).flatMap(parseVector) ?? content
                // spriteOffset locates the trimmed content from the bottom-left (Y-up).
                let offset = (subimage["spriteOffset"] as? String).flatMap(parseVector) ?? .zero
                return AtlasRegion(
                    name: textureName(name),
                    frame: rect,
                    rotation: rotated ? .clockwise : .none,
                    sourceSize: sourceSize,
                    trimOrigin: Vector2(offset.x, sourceSize.y - offset.y - content.y)
                )
            }
            return AtlasPage(imageName: path, regions: regions)
        }
        return AtlasDocument(pages: pages)
    }

    /// Texture name without image extension and scale suffix (`"hero@2x.png"` → `"hero"`).
    public static func textureName(_ fileName: String) -> String {
        var name = fileName
        for suffix in [".png", ".PNG"] where name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        if let range = name.range(of: #"@\dx$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name
    }

    /// Decodes a compiled `.atlasc` folder or a source `.atlas` folder of PNG files.
    ///
    /// Runs off the caller's actor; use ``DecodedAtlas/makeTextureAtlases(backend:)`` to upload.
    @concurrent
    public static func decode(at url: URL) async throws -> DecodedAtlas {
        if url.pathExtension == "atlasc" {
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            guard let plist = contents.first(where: { $0.hasSuffix(".plist") }) else {
                throw AtlasError.invalidDescription("No property list in \(url.lastPathComponent)")
            }
            let document = try parse(propertyList: Data(contentsOf: url.appending(path: plist)))
            return try DecodedAtlas(document: document, directory: url)
        }
        return try decodeImageFolder(at: url)
    }

    /// Reads every PNG in a folder (preferring the given scale variant) for packing.
    static func decodeImageFolder(at url: URL, scale: Int = 1) throws -> DecodedAtlas {
        let files = try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { $0.lowercased().hasSuffix(".png") }
            .sorted()
        var chosen = [String: String]()
        for file in files {
            let name = textureName(file)
            let isPreferred = scale > 1 ? file.contains("@\(scale)x") : !file.contains("@")
            if chosen[name] == nil || isPreferred {
                chosen[name] = file
            }
        }
        var images = [String: PixelBuffer]()
        for (name, file) in chosen {
            images[name] = try PixelBuffer(png: Array(Data(contentsOf: url.appending(path: file))))
        }
        return DecodedAtlas(looseImages: images)
    }

    // MARK: - Geometry strings

    /// Numbers in a geometry string such as `"{{1, 41}, {16, 16}}"`.
    static func numbers(in string: String) -> [Float] {
        string.split(whereSeparator: { !"0123456789.-eE".contains($0) }).compactMap { Float($0) }
    }

    static func parseVector(_ string: String) -> Vector2? {
        let n = numbers(in: string)
        return n.count == 2 ? Vector2(n[0], n[1]) : nil
    }

    static func parseRect(_ string: String) -> Rect? {
        let n = numbers(in: string)
        return n.count == 4 ? Rect(x: n[0], y: n[1], width: n[2], height: n[3]) : nil
    }
}
