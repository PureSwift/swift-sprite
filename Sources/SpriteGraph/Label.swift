//
//  Label.swift
//  SpriteGraph
//

import SpriteCore

/// Node that draws text by batching glyph quads from a ``BitmapFont``.
open class Label: Node {

    public enum HorizontalAlignment: Hashable, Sendable {
        case left
        case center
        case right
    }

    public enum VerticalAlignment: Hashable, Sendable {
        /// The first line's baseline sits at the node's origin.
        case baseline
        case center
        case top
        case bottom
    }

    public var text: String {
        didSet { if text != oldValue { invalidateLayout() } }
    }

    public var font: BitmapFont? {
        didSet { invalidateLayout() }
    }

    /// Rendered size corresponding to ``BitmapFont/size``.
    public var fontSize: Float {
        didSet { if fontSize != oldValue { invalidateLayout() } }
    }

    public var color: Color = .white

    public var blendMode: BlendMode = .alpha

    public var horizontalAlignmentMode: HorizontalAlignment = .center {
        didSet { if horizontalAlignmentMode != oldValue { invalidateLayout() } }
    }

    public var verticalAlignmentMode: VerticalAlignment = .baseline {
        didSet { if verticalAlignmentMode != oldValue { invalidateLayout() } }
    }

    /// Wraps lines at word boundaries when greater than zero (in node units).
    public var preferredMaxLayoutWidth: Float = 0 {
        didSet { if preferredMaxLayoutWidth != oldValue { invalidateLayout() } }
    }

    /// Maximum number of lines; `0` means unlimited.
    public var numberOfLines: Int = 0 {
        didSet { if numberOfLines != oldValue { invalidateLayout() } }
    }

    /// Additional space between lines, in node units.
    public var lineSpacing: Float = 0 {
        didSet { if lineSpacing != oldValue { invalidateLayout() } }
    }

    /// Positioned glyph quad in the label's coordinate space.
    struct PlacedGlyph: Equatable {
        var region: Rect
        var rect: Rect
    }

    private var cachedLayout: [PlacedGlyph]?

    public init(text: String = "", font: BitmapFont?, fontSize: Float? = nil) {
        self.text = text
        self.font = font
        self.fontSize = fontSize ?? font?.size ?? 0
        super.init()
    }

    open override var localBounds: Rect? {
        let glyphs = layout
        guard var bounds = glyphs.first?.rect else { return nil }
        for glyph in glyphs.dropFirst() {
            bounds = bounds.union(glyph.rect)
        }
        return bounds
    }

    open override func draw(in context: inout RenderContext) {
        guard let font else { return }
        for glyph in layout {
            context.submit(
                texture: font.texture.subtexture(in: glyph.region),
                size: glyph.rect.size,
                offset: .translation(glyph.rect.origin),
                anchorPoint: .zero,
                color: color,
                blendMode: blendMode,
                shader: font.shader
            )
        }
    }

    private func invalidateLayout() {
        cachedLayout = nil
    }

    var layout: [PlacedGlyph] {
        if let cachedLayout { return cachedLayout }
        let result = makeLayout()
        cachedLayout = result
        return result
    }

    /// Splits text into lines, honoring explicit newlines, word wrap and the line limit.
    func lines(font: BitmapFont, scale: Float) -> [[Character]] {
        let maxWidth = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth / scale : .infinity
        var lines = [[Character]]()
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = [Character]()
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false) {
                let candidate = line.isEmpty ? Array(word) : line + [" "] + Array(word)
                if !line.isEmpty, width(of: candidate, font: font) > maxWidth {
                    lines.append(line)
                    line = Array(word)
                } else {
                    line = candidate
                }
            }
            lines.append(line)
        }
        if numberOfLines > 0, lines.count > numberOfLines {
            lines.removeLast(lines.count - numberOfLines)
        }
        return lines
    }

    /// Width of a line in font pixels, excluding the trailing advance's spacing.
    func width(of line: [Character], font: BitmapFont) -> Float {
        var width: Float = 0
        var previous: Character?
        for character in line {
            if let previous {
                width += font.kerning(previous, character)
            }
            width += font.glyph(for: character)?.advance ?? 0
            previous = character
        }
        return width
    }

    private func makeLayout() -> [PlacedGlyph] {
        guard let font, font.size > 0, !text.isEmpty else { return [] }
        let scale = fontSize / font.size
        let lines = lines(font: font, scale: scale)
        let lineStep = font.lineHeight + lineSpacing / scale
        let lastBaseline = -Float(lines.count - 1) * lineStep
        let top = font.baseline
        let bottom = lastBaseline - (font.lineHeight - font.baseline)
        let dy: Float = switch verticalAlignmentMode {
        case .baseline: 0
        case .top: -top
        case .bottom: -bottom
        case .center: -(top + bottom) / 2
        }

        var placed = [PlacedGlyph]()
        for (index, line) in lines.enumerated() {
            let lineWidth = width(of: line, font: font)
            var penX: Float = switch horizontalAlignmentMode {
            case .left: 0
            case .center: -lineWidth / 2
            case .right: -lineWidth
            }
            let baselineY = -Float(index) * lineStep + dy
            var previous: Character?
            for character in line {
                if let previous {
                    penX += font.kerning(previous, character)
                }
                previous = character
                guard let glyph = font.glyph(for: character) else { continue }
                defer { penX += glyph.advance }
                guard !glyph.region.isEmpty, character != " " else { continue }
                let glyphTop = baselineY + font.baseline - glyph.offset.y
                let rect = Rect(
                    x: penX + glyph.offset.x,
                    y: glyphTop - glyph.region.height,
                    width: glyph.region.width,
                    height: glyph.region.height
                )
                placed.append(PlacedGlyph(
                    region: glyph.region,
                    rect: Rect(origin: rect.origin * scale, size: rect.size * scale)
                ))
            }
        }
        return placed
    }
}
