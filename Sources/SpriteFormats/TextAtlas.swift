//
//  TextAtlas.swift
//  SpriteFormats
//

import Foundation
import SpriteCore

/// libGDX / Spine text `.atlas` files (both the legacy and the current key formats).
///
/// Indexed regions (`index: n`, n ≥ 0) are named `"name_n"`.
public enum TextAtlas {

    public static func parse(_ text: String) throws -> AtlasDocument {
        var pages = [AtlasPage]()
        var page: AtlasPage?
        var region: [String: String]?
        var regionName = ""
        var expectingPage = true

        func finishRegion() throws {
            guard let fields = region, page != nil else { return }
            page!.regions.append(try makeRegion(name: regionName, fields: fields))
            region = nil
        }
        func finishPage() throws {
            try finishRegion()
            if let page { pages.append(page) }
            page = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty {
                try finishPage()
                expectingPage = true
                continue
            }
            if let colon = line.firstIndex(of: ":") {
                let key = line[..<colon].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if region != nil {
                    region![key] = value
                } else if key == "filter", page != nil {
                    page!.filtering = value.lowercased().hasPrefix("nearest") ? .nearest : .linear
                }
                continue
            }
            if expectingPage {
                try finishPage()
                page = AtlasPage(imageName: line, regions: [])
                expectingPage = false
            } else {
                try finishRegion()
                regionName = line
                region = [:]
            }
        }
        try finishPage()
        guard !pages.isEmpty else { throw AtlasError.invalidDescription("No pages") }
        return AtlasDocument(pages: pages)
    }

    private static func ints(_ value: String?) -> [Float] {
        value?.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) } ?? []
    }

    private static func makeRegion(name: String, fields: [String: String]) throws -> AtlasRegion {
        // Current format: bounds x,y,w,h and offsets x,y,origW,origH; legacy: xy, size, orig, offset.
        let bounds = fields["bounds"].map(ints) ?? (ints(fields["xy"]) + ints(fields["size"]))
        guard bounds.count == 4 else { throw AtlasError.invalidDescription("Region \(name) has no bounds") }
        let size = Vector2(bounds[2], bounds[3])

        let offsets = fields["offsets"].map(ints) ?? (ints(fields["offset"]) + ints(fields["orig"]))
        let offset = offsets.count == 4 ? Vector2(offsets[0], offsets[1]) : .zero
        let sourceSize = offsets.count == 4 ? Vector2(offsets[2], offsets[3]) : size

        let rotate = fields["rotate"]?.lowercased()
        let rotated = rotate == "true" || rotate == "90"
        // Sizes are given unrotated; the packed rect is transposed when rotated.
        let frame = Rect(origin: Vector2(bounds[0], bounds[1]), size: rotated ? Vector2(size.y, size.x) : size)

        let index = fields["index"].flatMap { Int($0) } ?? -1
        return AtlasRegion(
            name: index >= 0 ? "\(name)_\(index)" : name,
            frame: frame,
            rotation: rotated ? .counterClockwise : .none,
            sourceSize: sourceSize,
            // Offsets count stripped pixels from the bottom-left (Y-up).
            trimOrigin: Vector2(offset.x, sourceSize.y - offset.y - size.y)
        )
    }

    /// Decodes an atlas file and its page images off the caller's actor.
    @concurrent
    public static func decode(at url: URL) async throws -> DecodedAtlas {
        let document = try parse(String(decoding: Data(contentsOf: url), as: UTF8.self))
        return try DecodedAtlas(document: document, directory: url.deletingLastPathComponent())
    }
}
