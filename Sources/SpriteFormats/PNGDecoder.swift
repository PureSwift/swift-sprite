//
//  PNGDecoder.swift
//  SpriteFormats
//

import SpriteCore

/// Pure-Swift PNG decoder producing straight-alpha RGBA8 ``PixelBuffer``s.
///
/// Supports all standard color types and bit depths, palettes, `tRNS`
/// transparency and Adam7 interlacing. Color management chunks are ignored.
public enum PNGDecoder {

    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidSignature
        case truncated
        case checksumMismatch(chunk: String)
        case missingHeader
        case unsupportedFormat(colorType: Int, bitDepth: Int)
        case invalidFilter(Int)
        case missingPalette
        case invalidImageData
        case compression(Inflate.Error)
    }

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    struct Header {
        var width: Int
        var height: Int
        var bitDepth: Int
        var colorType: Int
        var interlaced: Bool

        var channels: Int {
            switch colorType {
            case 0, 3: 1
            case 2: 3
            case 4: 2
            default: 4
            }
        }

        var bitsPerPixel: Int {
            channels * bitDepth
        }

        /// Byte distance to the corresponding byte of the previous pixel (for filtering).
        var filterStride: Int {
            max(1, bitsPerPixel / 8)
        }

        func rowBytes(width: Int) -> Int {
            (width * bitsPerPixel + 7) / 8
        }
    }

    /// Whether data starts with the PNG signature.
    public static func isPNG(_ data: [UInt8]) -> Bool {
        data.starts(with: signature)
    }

    public static func decode(_ data: [UInt8]) throws(Error) -> PixelBuffer {
        guard isPNG(data) else { throw .invalidSignature }
        var header: Header?
        var palette = [Color]()
        var transparency = [UInt8]()
        var compressed = [UInt8]()

        var offset = signature.count
        func u32(_ i: Int) -> Int {
            Int(data[i]) << 24 | Int(data[i + 1]) << 16 | Int(data[i + 2]) << 8 | Int(data[i + 3])
        }
        chunks: while true {
            guard offset + 12 <= data.count else { throw .truncated }
            let length = u32(offset)
            let typeStart = offset + 4
            let dataStart = offset + 8
            guard length >= 0, dataStart + length + 4 <= data.count else { throw .truncated }
            let type = String(decoding: data[typeStart ..< typeStart + 4], as: UTF8.self)
            let body = data[dataStart ..< dataStart + length]
            guard Inflate.crc32(data[typeStart ..< dataStart + length]) == UInt32(u32(dataStart + length)) else {
                throw .checksumMismatch(chunk: type)
            }
            offset = dataStart + length + 4

            switch type {
            case "IHDR":
                guard length == 13 else { throw .missingHeader }
                let b = Array(body)
                let parsed = Header(
                    width: Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3]),
                    height: Int(b[4]) << 24 | Int(b[5]) << 16 | Int(b[6]) << 8 | Int(b[7]),
                    bitDepth: Int(b[8]),
                    colorType: Int(b[9]),
                    interlaced: b[12] == 1
                )
                try validate(parsed)
                header = parsed
            case "PLTE":
                palette = stride(from: body.startIndex, to: body.endIndex - 2, by: 3).map {
                    Color(red: Float(data[$0]) / 255, green: Float(data[$0 + 1]) / 255, blue: Float(data[$0 + 2]) / 255)
                }
            case "tRNS":
                transparency = Array(body)
            case "IDAT":
                compressed.append(contentsOf: body)
            case "IEND":
                break chunks
            default:
                break
            }
        }

        guard let header else { throw .missingHeader }
        if header.colorType == 3, palette.isEmpty { throw .missingPalette }
        let raw: [UInt8]
        do {
            raw = try Inflate.zlibDecompress(compressed)
        } catch {
            throw .compression(error)
        }
        return try reconstruct(raw, header: header, palette: palette, transparency: transparency)
    }

    private static func validate(_ header: Header) throws(Error) {
        let allowed: [Int: Set<Int>] = [
            0: [1, 2, 4, 8, 16],
            2: [8, 16],
            3: [1, 2, 4, 8],
            4: [8, 16],
            6: [8, 16],
        ]
        guard header.width > 0, header.height > 0,
              allowed[header.colorType]?.contains(header.bitDepth) == true else {
            throw .unsupportedFormat(colorType: header.colorType, bitDepth: header.bitDepth)
        }
    }

    // MARK: - Reconstruction

    /// Adam7 passes as (x start, y start, x step, y step).
    private static let adam7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]

    private static func reconstruct(_ raw: [UInt8], header: Header, palette: [Color], transparency: [UInt8]) throws(Error) -> PixelBuffer {
        var pixels = [UInt8](repeating: 0, count: header.width * header.height * 4)
        let passes = header.interlaced ? adam7 : [(0, 0, 1, 1)]
        var offset = 0
        let converter = PixelConverter(header: header, palette: palette, transparency: transparency)

        for (xStart, yStart, xStep, yStep) in passes {
            let passWidth = (header.width - xStart + xStep - 1) / xStep
            let passHeight = (header.height - yStart + yStep - 1) / yStep
            guard passWidth > 0, passHeight > 0 else { continue }
            let rowBytes = header.rowBytes(width: passWidth)
            var previous = [UInt8](repeating: 0, count: rowBytes)
            var row = [UInt8](repeating: 0, count: rowBytes)
            for passY in 0 ..< passHeight {
                guard offset + 1 + rowBytes <= raw.count else { throw .invalidImageData }
                let filter = Int(raw[offset])
                for i in 0 ..< rowBytes {
                    row[i] = raw[offset + 1 + i]
                }
                offset += 1 + rowBytes
                try unfilter(&row, previous: previous, filter: filter, stride: header.filterStride)
                let y = yStart + passY * yStep
                for passX in 0 ..< passWidth {
                    let x = xStart + passX * xStep
                    let (r, g, b, a) = converter.pixel(row, index: passX)
                    let i = (y * header.width + x) * 4
                    pixels[i] = r
                    pixels[i + 1] = g
                    pixels[i + 2] = b
                    pixels[i + 3] = a
                }
                swap(&previous, &row)
            }
        }
        return PixelBuffer(width: header.width, height: header.height, pixels: pixels)
    }

    private static func unfilter(_ row: inout [UInt8], previous: [UInt8], filter: Int, stride: Int) throws(Error) {
        switch filter {
        case 0:
            break
        case 1:
            for i in stride ..< row.count {
                row[i] &+= row[i - stride]
            }
        case 2:
            for i in 0 ..< row.count {
                row[i] &+= previous[i]
            }
        case 3:
            for i in 0 ..< row.count {
                let left = i >= stride ? Int(row[i - stride]) : 0
                row[i] &+= UInt8((left + Int(previous[i])) / 2)
            }
        case 4:
            for i in 0 ..< row.count {
                let a = i >= stride ? Int(row[i - stride]) : 0
                let b = Int(previous[i])
                let c = i >= stride ? Int(previous[i - stride]) : 0
                let p = a + b - c
                let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                let predictor = pa <= pb && pa <= pc ? a : (pb <= pc ? b : c)
                row[i] &+= UInt8(predictor)
            }
        default:
            throw .invalidFilter(filter)
        }
    }
}

/// Converts unfiltered scanline samples to RGBA8.
private struct PixelConverter {

    let header: PNGDecoder.Header
    let palette: [(UInt8, UInt8, UInt8, UInt8)]
    let transparentKey: [Int]?

    init(header: PNGDecoder.Header, palette: [Color], transparency: [UInt8]) {
        self.header = header
        self.palette = palette.enumerated().map { index, color in
            (
                UInt8((color.red * 255).rounded()),
                UInt8((color.green * 255).rounded()),
                UInt8((color.blue * 255).rounded()),
                index < transparency.count ? transparency[index] : 255
            )
        }
        // Gray and RGB images may mark one exact color as transparent (16-bit big-endian values).
        if header.colorType == 0 || header.colorType == 2, transparency.count >= 2 {
            transparentKey = Swift.stride(from: 0, to: transparency.count - 1, by: 2).map {
                Int(transparency[$0]) << 8 | Int(transparency[$0 + 1])
            }
        } else {
            transparentKey = nil
        }
    }

    /// Raw sample `channel` of pixel `index` at the image's bit depth.
    @inline(__always)
    private func sample(_ row: [UInt8], _ index: Int, _ channel: Int) -> Int {
        let depth = header.bitDepth
        switch depth {
        case 8:
            return Int(row[index * header.channels + channel])
        case 16:
            let i = (index * header.channels + channel) * 2
            return Int(row[i]) << 8 | Int(row[i + 1])
        default:
            // Sub-byte samples are packed MSB-first; only single-channel types use them.
            let bit = index * depth
            let byte = Int(row[bit / 8])
            return (byte >> (8 - depth - bit % 8)) & ((1 << depth) - 1)
        }
    }

    /// Scales a sample to 8 bits.
    @inline(__always)
    private func scale(_ value: Int) -> UInt8 {
        switch header.bitDepth {
        case 16: UInt8(value >> 8)
        case 8: UInt8(value)
        default: UInt8(value * 255 / ((1 << header.bitDepth) - 1))
        }
    }

    @inline(__always)
    func pixel(_ row: [UInt8], index: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        switch header.colorType {
        case 0:
            let gray = sample(row, index, 0)
            let alpha: UInt8 = transparentKey?.first == gray ? 0 : 255
            let value = scale(gray)
            return (value, value, value, alpha)
        case 2:
            let r = sample(row, index, 0), g = sample(row, index, 1), b = sample(row, index, 2)
            let alpha: UInt8 = transparentKey == [r, g, b] ? 0 : 255
            return (scale(r), scale(g), scale(b), alpha)
        case 3:
            let entry = sample(row, index, 0)
            return entry < palette.count ? palette[entry] : (0, 0, 0, 255)
        case 4:
            let value = scale(sample(row, index, 0))
            return (value, value, value, scale(sample(row, index, 1)))
        default:
            return (
                scale(sample(row, index, 0)),
                scale(sample(row, index, 1)),
                scale(sample(row, index, 2)),
                scale(sample(row, index, 3))
            )
        }
    }
}

public extension PixelBuffer {

    /// Decodes PNG data.
    init(png data: [UInt8]) throws(PNGDecoder.Error) {
        self = try PNGDecoder.decode(data)
    }
}
