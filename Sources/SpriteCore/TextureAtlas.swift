//
//  TextureAtlas.swift
//  SpriteCore
//

/// Named sub-textures packed into a single backend texture.
public struct TextureAtlas: Sendable {

    public let texture: Texture

    /// Named regions in pixels, origin at the top-left of ``texture``.
    public let regions: [String: Rect]

    public init(texture: Texture, regions: [String: Rect]) {
        self.texture = texture
        self.regions = regions
    }

    /// Sorted names of all textures in the atlas.
    public var textureNames: [String] {
        regions.keys.sorted()
    }

    public subscript(name: String) -> Texture? {
        regions[name].map { texture.subtexture(in: $0) }
    }
}

public extension TextureAtlas {

    /// Packs named images into a single pixel buffer and uploads it through `backend`.
    ///
    /// - Throws: ``AtlasPacker/Error/doesNotFit`` if the images exceed `maxSize`.
    static func make(
        images: [String: PixelBuffer],
        backend: some SpriteRenderBackend,
        maxSize: Int = 4096,
        padding: Int = 1,
        filtering: TextureFiltering = .linear
    ) throws -> TextureAtlas {
        let names = images.keys.sorted()
        let sizes = names.map { (images[$0]!.width, images[$0]!.height) }
        let packer = AtlasPacker(maxWidth: maxSize, maxHeight: maxSize, padding: padding)
        let layout = try packer.pack(sizes)
        var buffer = PixelBuffer(width: layout.width, height: layout.height)
        var regions = [String: Rect](minimumCapacity: names.count)
        for (index, name) in names.enumerated() {
            let placement = layout.placements[index]
            let image = images[name]!
            buffer.blit(image, x: placement.x, y: placement.y)
            regions[name] = Rect(
                x: Float(placement.x),
                y: Float(placement.y),
                width: Float(image.width),
                height: Float(image.height)
            )
        }
        let texture = try backend.makeTexture(buffer, filtering: filtering)
        return TextureAtlas(texture: texture, regions: regions)
    }
}

/// Shelf-based rectangle packer for building texture atlases.
public struct AtlasPacker: Sendable {

    public enum Error: Swift.Error, Equatable {
        case doesNotFit
    }

    public struct Placement: Equatable, Sendable {
        public let x: Int
        public let y: Int
    }

    public struct Layout: Equatable, Sendable {
        /// Placement of each input, in input order.
        public let placements: [Placement]
        /// Power-of-two dimensions of the packed atlas.
        public let width: Int
        public let height: Int
    }

    public let maxWidth: Int
    public let maxHeight: Int
    public let padding: Int

    public init(maxWidth: Int, maxHeight: Int, padding: Int = 1) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.padding = padding
    }

    /// Packs rectangles (width, height) by placing tallest first on horizontal shelves.
    public func pack(_ sizes: [(width: Int, height: Int)]) throws(Error) -> Layout {
        let order = sizes.indices.sorted {
            (sizes[$0].height, sizes[$0].width) > (sizes[$1].height, sizes[$1].width)
        }
        var placements = [Placement?](repeating: nil, count: sizes.count)
        var cursorX = 0, shelfY = 0, shelfHeight = 0, usedWidth = 0
        for index in order {
            let (w, h) = sizes[index]
            guard w + padding <= maxWidth else { throw .doesNotFit }
            if cursorX + w + padding > maxWidth {
                shelfY += shelfHeight
                cursorX = 0
                shelfHeight = 0
            }
            guard shelfY + h + padding <= maxHeight else { throw .doesNotFit }
            placements[index] = Placement(x: cursorX + padding, y: shelfY + padding)
            cursorX += w + padding
            shelfHeight = Swift.max(shelfHeight, h + padding)
            usedWidth = Swift.max(usedWidth, cursorX)
        }
        return Layout(
            placements: placements.map { $0! },
            width: Self.nextPowerOfTwo(usedWidth + padding),
            height: Self.nextPowerOfTwo(shelfY + shelfHeight + padding)
        )
    }

    static func nextPowerOfTwo(_ value: Int) -> Int {
        var result = 1
        while result < value { result <<= 1 }
        return result
    }
}
