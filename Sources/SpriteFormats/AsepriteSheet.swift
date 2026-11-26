//
//  AsepriteSheet.swift
//  SpriteFormats
//

import Foundation
import SpriteCore
import SpriteGraph

/// Sprite sheet exported by Aseprite (`--format json-hash` or `json-array`).
public struct AsepriteSheet: Sendable {

    public struct Frame: Sendable {
        /// Frame name, used as the texture name in the uploaded atlas.
        public var name: String
        public var region: AtlasRegion
        public var duration: Duration
    }

    public enum Direction: String, Sendable {
        case forward
        case reverse
        case pingpong
        case pingpongReverse = "pingpong_reverse"
    }

    public struct Tag: Sendable {
        public var name: String
        public var from: Int
        public var to: Int
        public var direction: Direction
        /// Number of times to play, or `nil` when unspecified.
        public var repeatCount: Int?
    }

    public struct Slice: Sendable {
        public struct Key: Sendable {
            public var frame: Int
            /// Slice bounds in sprite pixels (top-left origin).
            public var bounds: Rect
            /// 9-patch center within ``bounds``, if defined.
            public var center: Rect?
            public var pivot: Vector2?
        }

        public var name: String
        public var keys: [Key]
    }

    public var imageName: String
    public var frames: [Frame]
    public var tags: [Tag]
    public var slices: [Slice]

    public init(json data: Data) throws {
        let root = try JSONDecoder().decode(JSONSheet.self, from: data)
        imageName = root.meta.image
        frames = root.frames.map { entry in
            let frame = entry.frame
            return Frame(
                name: entry.name,
                region: AtlasRegion(
                    name: entry.name,
                    frame: Rect(x: frame.frame.x, y: frame.frame.y, width: frame.frame.w, height: frame.frame.h),
                    rotation: frame.rotated == true ? .clockwise : .none,
                    sourceSize: frame.sourceSize.map { Vector2($0.w, $0.h) },
                    trimOrigin: frame.spriteSourceSize.map { Vector2($0.x, $0.y) } ?? .zero
                ),
                duration: .milliseconds(frame.duration ?? 100)
            )
        }
        tags = (root.meta.frameTags ?? []).map { tag in
            Tag(
                name: tag.name,
                from: tag.from,
                to: tag.to,
                direction: Direction(rawValue: tag.direction ?? "forward") ?? .forward,
                repeatCount: tag.repeat.flatMap { Int($0) }
            )
        }
        slices = (root.meta.slices ?? []).map { slice in
            Slice(name: slice.name, keys: slice.keys.map { key in
                Slice.Key(
                    frame: key.frame,
                    bounds: Rect(x: key.bounds.x, y: key.bounds.y, width: key.bounds.w, height: key.bounds.h),
                    center: key.center.map { Rect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) },
                    pivot: key.pivot.map { Vector2($0.x, $0.y) }
                )
            })
        }
    }

    public func tag(named name: String) -> Tag? {
        tags.first { $0.name == name }
    }

    /// Frame indices for one playback of a tag, honoring its direction.
    public func frameIndices(for tag: Tag) -> [Int] {
        let forward = Array(tag.from ... tag.to)
        // Ping-pong does not repeat the end frames when turning around.
        let back = forward.count > 2 ? Array(forward.dropFirst().dropLast().reversed()) : []
        switch tag.direction {
        case .forward: return forward
        case .reverse: return forward.reversed()
        case .pingpong: return forward + back
        case .pingpongReverse: return forward.reversed() + back.reversed()
        }
    }

    /// Animation playing a tag once (or `repeatCount` times) with per-frame durations.
    ///
    /// Wrap in ``Action/repeatForever(_:)`` to loop.
    @MainActor
    public func animation(tag name: String, atlas: TextureAtlas, resize: Bool = false) -> Action? {
        guard let tag = tag(named: name) else { return nil }
        var steps = [Action]()
        for index in frameIndices(for: tag) where frames.indices.contains(index) {
            guard let texture = atlas[frames[index].name] else { continue }
            steps.append(.setTexture(texture, resize: resize))
            steps.append(.wait(for: frames[index].duration))
        }
        let once = Action.sequence(steps)
        if let count = tag.repeatCount, count > 1 {
            return .repeat(once, count: count)
        }
        return once
    }

    /// Unit-space 9-patch rect of a slice for ``Sprite/centerRect``.
    public func centerRect(slice name: String, frame: Int = 0) -> Rect? {
        guard let slice = slices.first(where: { $0.name == name }),
              let key = slice.keys.last(where: { $0.frame <= frame }) ?? slice.keys.first,
              let center = key.center, key.bounds.width > 0, key.bounds.height > 0 else { return nil }
        return Rect(origin: center.origin / key.bounds.size, size: center.size / key.bounds.size)
    }

    /// Decodes the sheet's JSON and image off the caller's actor.
    @concurrent
    public static func decode(at url: URL) async throws -> (sheet: AsepriteSheet, atlas: DecodedAtlas) {
        let sheet = try AsepriteSheet(json: Data(contentsOf: url))
        let page = AtlasPage(imageName: sheet.imageName, filtering: .nearest, regions: sheet.frames.map(\.region))
        let atlas = try DecodedAtlas(document: AtlasDocument(pages: [page]), directory: url.deletingLastPathComponent())
        return (sheet, atlas)
    }
}

// MARK: - JSON schema

private struct JSONRect: Decodable {
    var x: Float
    var y: Float
    var w: Float
    var h: Float
}

private struct JSONSize: Decodable {
    var w: Float
    var h: Float
}

private struct JSONPoint: Decodable {
    var x: Float
    var y: Float
}

private struct JSONFrame: Decodable {
    var filename: String?
    var frame: JSONRect
    var rotated: Bool?
    var trimmed: Bool?
    var spriteSourceSize: JSONRect?
    var sourceSize: JSONSize?
    var duration: Int?
}

private struct JSONSheet: Decodable {

    struct NamedFrame {
        var name: String
        var frame: JSONFrame
    }

    struct Meta: Decodable {
        struct FrameTag: Decodable {
            var name: String
            var from: Int
            var to: Int
            var direction: String?
            var `repeat`: String?
        }

        struct Slice: Decodable {
            struct Key: Decodable {
                var frame: Int
                var bounds: JSONRect
                var center: JSONRect?
                var pivot: JSONPoint?
            }

            var name: String
            var keys: [Key]
        }

        var image: String
        var frameTags: [FrameTag]?
        var slices: [Slice]?
    }

    var frames: [NamedFrame]
    var meta: Meta

    enum CodingKeys: String, CodingKey {
        case frames, meta
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        meta = try container.decode(Meta.self, forKey: .meta)
        if let array = try? container.decode([JSONFrame].self, forKey: .frames) {
            frames = array.enumerated().map { NamedFrame(name: $1.filename ?? String($0), frame: $1) }
        } else {
            // JSON objects are unordered; recover frame order from the number in each name.
            let hash = try container.decode([String: JSONFrame].self, forKey: .frames)
            frames = hash.map { NamedFrame(name: $0.key, frame: $0.value) }
                .sorted { lhs, rhs in
                    let (a, b) = (Self.frameNumber(lhs.name), Self.frameNumber(rhs.name))
                    return a != b ? (a ?? .max) < (b ?? .max) : lhs.name < rhs.name
                }
        }
    }

    /// Last integer in a frame name (`"hero 12.aseprite"` → 12).
    static func frameNumber(_ name: String) -> Int? {
        name.split(whereSeparator: { !$0.isNumber }).last.flatMap { Int($0) }
    }
}
