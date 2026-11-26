//
//  AtlasDocument.swift
//  SpriteFormats
//

import SpriteCore

/// Format-independent description of a packed texture atlas.
public struct AtlasDocument: Hashable, Sendable {

    public var pages: [AtlasPage]

    public init(pages: [AtlasPage]) {
        self.pages = pages
    }
}

/// One image of an atlas and the regions packed into it.
public struct AtlasPage: Hashable, Sendable {

    /// Image file name, relative to the atlas description.
    public var imageName: String

    public var filtering: TextureFiltering

    public var regions: [AtlasRegion]

    public init(imageName: String, filtering: TextureFiltering = .linear, regions: [AtlasRegion]) {
        self.imageName = imageName
        self.filtering = filtering
        self.regions = regions
    }
}

/// A sprite packed into an atlas page, possibly trimmed and rotated.
public struct AtlasRegion: Hashable, Sendable {

    /// How the sprite was rotated when packed into the page.
    public enum Rotation: Hashable, Sendable {
        case none
        /// Rotated 90° clockwise (SpriteKit `textureRotated`).
        case clockwise
        /// Rotated 90° counter-clockwise (libGDX / Spine `rotate`).
        case counterClockwise
    }

    public var name: String

    /// Packed rectangle in page pixels (top-left origin), with the rotated size if rotated.
    public var frame: Rect

    public var rotation: Rotation

    /// Size of the sprite before trimming.
    public var sourceSize: Vector2

    /// Top-left of the trimmed content within the untrimmed sprite (Y-down).
    public var trimOrigin: Vector2

    public init(name: String, frame: Rect, rotation: Rotation = .none, sourceSize: Vector2? = nil, trimOrigin: Vector2 = .zero) {
        self.name = name
        self.frame = frame
        self.rotation = rotation
        self.sourceSize = sourceSize ?? (rotation == .none ? frame.size : Vector2(frame.height, frame.width))
        self.trimOrigin = trimOrigin
    }

    /// Size of the trimmed content in sprite orientation.
    public var contentSize: Vector2 {
        rotation == .none ? frame.size : Vector2(frame.height, frame.width)
    }

    /// Whether the region can be used directly as a sub-texture of its page.
    public var isUntransformed: Bool {
        rotation == .none && trimOrigin == .zero && sourceSize == frame.size
    }
}

public enum AtlasError: Swift.Error, Equatable, Sendable {
    case invalidDescription(String)
    case missingImage(String)
    case regionOutOfBounds(String)
}

// MARK: - Region extraction

extension AtlasRegion {

    /// Copies the region out of its page, undoing rotation and restoring trimmed padding.
    public func extract(from page: PixelBuffer) throws(AtlasError) -> PixelBuffer {
        let x0 = Int(frame.minX), y0 = Int(frame.minY)
        let frameWidth = Int(frame.width), frameHeight = Int(frame.height)
        guard x0 >= 0, y0 >= 0, x0 + frameWidth <= page.width, y0 + frameHeight <= page.height else {
            throw .regionOutOfBounds(name)
        }
        let content = contentSize
        let width = Int(content.x), height = Int(content.y)
        var output = PixelBuffer(width: Int(sourceSize.x), height: Int(sourceSize.y))
        let left = Int(trimOrigin.x), top = Int(trimOrigin.y)
        guard left >= 0, top >= 0, left + width <= output.width, top + height <= output.height else {
            throw .regionOutOfBounds(name)
        }
        for y in 0 ..< height {
            for x in 0 ..< width {
                // Sheet coordinates of sprite pixel (x, y).
                let (sx, sy): (Int, Int) = switch rotation {
                case .none: (x, y)
                // Clockwise: the sprite's top edge lies along the right of the packed rect.
                case .clockwise: (height - 1 - y, x)
                // Counter-clockwise: the sprite's top edge lies along the left of the packed rect.
                case .counterClockwise: (y, width - 1 - x)
                }
                let src = ((y0 + sy) * page.width + x0 + sx) * 4
                let dst = ((top + y) * output.width + left + x) * 4
                output.pixels[dst] = page.pixels[src]
                output.pixels[dst + 1] = page.pixels[src + 1]
                output.pixels[dst + 2] = page.pixels[src + 2]
                output.pixels[dst + 3] = page.pixels[src + 3]
            }
        }
        return output
    }
}
