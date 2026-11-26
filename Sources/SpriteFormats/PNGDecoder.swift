//
//  PNGDecoder.swift
//  SpriteFormats
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import PNG
import SpriteCore

/// Decodes PNG files to straight-alpha RGBA8 ``PixelBuffer``s using
/// [swift-png](https://github.com/PureSwift/swift-png).
///
/// Every color type and bit depth, palettes, `tRNS` transparency and Adam7
/// interlacing are normalized to 8-bit RGBA by the decoder's read transforms.
public enum PNGDecoder {

    public enum Error: Swift.Error, Equatable, Sendable {
        case invalidSignature
        case truncated
        /// The decoder rejected the file; carries its diagnostic message.
        case invalidData(String)
    }

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Whether data starts with the PNG signature.
    public static func isPNG(_ data: [UInt8]) -> Bool {
        data.starts(with: signature)
    }

    public static func decode(_ data: [UInt8]) throws(Error) -> PixelBuffer {
        guard isPNG(data) else { throw .invalidSignature }
        let source = Source(data)
        let result = withExtendedLifetime(source) {
            Result { () throws(Diagnostic) in try read(from: source) }
        }
        // A short read is zero-filled to keep the decoder running; report it as truncation.
        if source.overrun { throw .truncated }
        switch result {
        case let .success(image):
            return image
        case let .failure(diagnostic):
            throw .invalidData(String(describing: diagnostic.message))
        }
    }

    private static func read(from source: Source) throws(Diagnostic) -> PixelBuffer {
        let host = Host(
            owner: Unmanaged.passUnretained(source).toOpaque(),
            allocate: { _, size in malloc(Int(size)) },
            deallocate: { _, memory in free(memory) },
            read: { owner, destination, count in
                Unmanaged<Source>.fromOpaque(owner!).takeUnretainedValue().read(into: destination, count: Int(count))
            },
            warn: { _, _, _ in },
            warnChunk: { _, _, _, _ in }
        )
        let context = PngContext(host: host, isReading: true)
        let info = InfoStore(host: host)
        defer {
            info.release()
            context.release()
        }

        try context.readInfo(into: info)
        guard let header = info.header else { throw Diagnostic("missing IHDR") }

        // Normalize to RGBA8: expand palettes, low bit depths and tRNS to alpha, gray to RGB,
        // fold 16-bit samples to 8, and add an opaque alpha channel where none exists.
        context.transformFlags.insert([.expand, .expandTransparency, .expandGrayTo8, .grayToRgb, .scale16, .addAlpha])
        context.fillerValue = 0xFFFF
        context.fillerAfterColor = true
        if header.isInterlaced {
            // Spread Adam7 passes into full-width rows.
            _ = context.enableInterlaceHandling()
        }
        try context.updateInfoForClient(info)

        let width = header.width, height = header.height
        let rowBytes = info.rowBytes
        guard rowBytes == width * 4 else { throw Diagnostic("unexpected output layout") }

        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        try pixels.withUnsafeMutableBufferPointer { buffer throws(Diagnostic) in
            var rows: [UnsafeMutablePointer<UInt8>?] = (0 ..< height).map { buffer.baseAddress! + $0 * rowBytes }
            try rows.withUnsafeMutableBufferPointer { rows throws(Diagnostic) in
                try context.readImage(rows: rows.baseAddress!)
            }
        }
        try context.readEnd(into: nil)
        return PixelBuffer(width: width, height: height, pixels: pixels)
    }

    /// Input bytes served to the decoder's read callback.
    private final class Source {

        let bytes: [UInt8]
        var offset = 0
        var overrun = false

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        func read(into destination: UnsafeMutablePointer<UInt8>?, count: Int) {
            guard let destination else { return }
            let available = max(0, min(count, bytes.count - offset))
            bytes.withUnsafeBufferPointer {
                destination.update(from: $0.baseAddress! + offset, count: available)
            }
            if available < count {
                // The callback cannot throw; zero-fill so the decoder fails on its own checks.
                (destination + available).update(repeating: 0, count: count - available)
                overrun = true
            }
            offset += available
        }
    }
}

public extension PixelBuffer {

    /// Decodes PNG data.
    init(png data: [UInt8]) throws(PNGDecoder.Error) {
        self = try PNGDecoder.decode(data)
    }
}
