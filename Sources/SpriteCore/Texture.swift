//
//  Texture.swift
//  SpriteCore
//

/// Opaque identifier of a GPU texture owned by a ``SpriteRenderBackend``.
public struct TextureID: RawRepresentable, Hashable, Comparable, Sendable {

    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Reserved identifier meaning "no texture" (solid vertex color).
    public static let none = TextureID(rawValue: 0)

    public static func < (lhs: TextureID, rhs: TextureID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Sampling filter applied when a texture is minified or magnified.
public enum TextureFiltering: Hashable, Sendable {
    case nearest
    case linear
}

/// Lightweight, `Sendable` handle to a region of a backend texture.
///
/// Sub-textures share the same ``id`` as their parent and differ only by ``region``.
public struct Texture: Hashable, Sendable {

    public let id: TextureID

    /// Size in pixels of the full backing texture.
    public let textureSize: Vector2

    /// Region of the backing texture in pixels, origin at the top-left.
    public let region: Rect

    public init(id: TextureID, textureSize: Vector2, region: Rect? = nil) {
        self.id = id
        self.textureSize = textureSize
        self.region = region ?? Rect(origin: .zero, size: textureSize)
    }

    /// Placeholder for untextured, solid-color quads.
    public static let none = Texture(id: .none, textureSize: .one)

    /// Size in pixels of this texture's region.
    public var size: Vector2 {
        region.size
    }

    /// Normalized texture coordinates of ``region`` (v = 0 at the top).
    public var uvRect: Rect {
        guard textureSize.x > 0, textureSize.y > 0 else { return .unit }
        return Rect(origin: region.origin / textureSize, size: region.size / textureSize)
    }

    /// Creates a texture referencing a sub-region in pixels, relative to this texture's region.
    public func subtexture(in rect: Rect) -> Texture {
        Texture(
            id: id,
            textureSize: textureSize,
            region: Rect(origin: region.origin + rect.origin, size: rect.size)
        )
    }

    /// Creates a texture referencing a sub-region in unit coordinates of this texture's region.
    public func subtexture(inUnitRect rect: Rect) -> Texture {
        subtexture(in: Rect(origin: rect.origin * region.size, size: rect.size * region.size))
    }
}
