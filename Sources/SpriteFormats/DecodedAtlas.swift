//
//  DecodedAtlas.swift
//  SpriteFormats
//

import Foundation
import SpriteCore

/// Atlas pages decoded to pixels, ready to upload to a ``SpriteRenderBackend``.
public struct DecodedAtlas: Sendable {

    public struct Page: Sendable {
        public var page: AtlasPage
        public var image: PixelBuffer
    }

    /// Pages loaded from a description.
    public var pages: [Page]

    /// Individual images to pack into a new atlas (e.g. a source `.atlas` folder).
    public var looseImages: [String: PixelBuffer]

    public init(pages: [Page]) {
        self.pages = pages
        self.looseImages = [:]
    }

    public init(looseImages: [String: PixelBuffer]) {
        self.pages = []
        self.looseImages = looseImages
    }

    /// Loads page images referenced by `document` relative to `directory`.
    public init(document: AtlasDocument, directory: URL) throws {
        self.init(pages: try document.pages.map { page in
            let url = directory.appending(path: page.imageName)
            guard let data = try? Data(contentsOf: url) else {
                throw AtlasError.missingImage(page.imageName)
            }
            return Page(page: page, image: try PixelBuffer(png: Array(data)))
        })
    }

    /// Uploads the atlas, one ``TextureAtlas`` per page.
    ///
    /// Pages whose regions are all untrimmed and unrotated are uploaded as-is; otherwise
    /// regions are extracted (restoring trim padding and orientation) and repacked.
    public func makeTextureAtlases(
        backend: some SpriteRenderBackend,
        filtering: TextureFiltering? = nil,
        maxSize: Int = 4096
    ) throws -> [TextureAtlas] {
        var atlases = [TextureAtlas]()
        for page in pages {
            let pageFiltering = filtering ?? page.page.filtering
            if page.page.regions.allSatisfy(\.isUntransformed) {
                let texture = try backend.makeTexture(page.image, filtering: pageFiltering)
                var regions = [String: Rect]()
                for region in page.page.regions {
                    regions[region.name] = region.frame
                }
                atlases.append(TextureAtlas(texture: texture, regions: regions))
            } else {
                var images = [String: PixelBuffer]()
                for region in page.page.regions {
                    images[region.name] = try region.extract(from: page.image)
                }
                atlases.append(try TextureAtlas.make(images: images, backend: backend, maxSize: maxSize, filtering: pageFiltering))
            }
        }
        if !looseImages.isEmpty {
            atlases.append(try TextureAtlas.make(images: looseImages, backend: backend, maxSize: maxSize, filtering: filtering ?? .linear))
        }
        return atlases
    }
}

public extension Array where Element == TextureAtlas {

    /// Finds a texture by name across all atlases.
    subscript(texture name: String) -> Texture? {
        lazy.compactMap { $0[name] }.first
    }

    /// All texture names across atlases.
    var textureNames: [String] {
        flatMap(\.textureNames).sorted()
    }
}
