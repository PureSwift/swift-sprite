import SpriteCore

struct ArchiveTexture: Sendable {
    let reference: SpriteKitSceneArchive.TextureReference
    let rect: Rect

    init(_ value: PropertyValue, graph: KeyedArchive) throws {
        let texture = try graph.dictionary(value)
        guard try graph.className(texture) == "SKTexture" else {
            throw SceneArchiveError.unsupported("Texture class")
        }
        for key in ["_isData", "_isCapture", "_isRotated", "_isFlipped"] {
            guard try !graph.boolean(texture[key], default: false) else {
                throw SceneArchiveError.unsupported("Texture \(key)")
            }
        }
        guard try graph.vector(texture["_cropScale"], default: .one) == .one,
              try graph.vector(texture["_cropOffset"], default: .zero) == .zero else {
            throw SceneArchiveError.unsupported("Trimmed texture")
        }
        guard let imageName = try graph.string(texture["_imgName"]), !imageName.isEmpty else {
            throw SceneArchiveError.unsupported("Texture without image name")
        }
        let filtering = try graph.number(texture["_filteringMode"], default: 1)
        guard filtering == 0 || filtering == 1 else { throw SceneArchiveError.invalid("Texture filtering mode") }
        reference = try SpriteKitSceneArchive.TextureReference(imageName: imageName,
            atlasName: graph.string(texture["_originalAtlasName"]),
            subtextureName: graph.string(texture["_subTextureName"]),
            filtering: filtering == 0 ? .nearest : .linear)
        let unitRect = try graph.rect(texture["_textRect"], default: .unit)
        try graph.validateUnitRect(unitRect)
        rect = Rect(x: unitRect.minX, y: 1 - unitRect.maxY, width: unitRect.width, height: unitRect.height)
    }
}
