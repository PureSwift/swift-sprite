//
//  Inflate.swift
//  SpriteFormats
//

/// Pure-Swift DEFLATE decoder (RFC 1951) with zlib (RFC 1950) and gzip (RFC 1952) wrappers.
public enum Inflate {

    public enum Error: Swift.Error, Equatable, Sendable {
        case truncated
        case invalidBlockType
        case invalidStoredLength
        case invalidHuffmanCode
        case invalidDistance
        case invalidHeader
        case checksumMismatch
        case unsupportedPresetDictionary
    }

    /// Decompresses a raw DEFLATE stream.
    public static func inflate(_ input: [UInt8]) throws(Error) -> [UInt8] {
        var reader = BitReader(input)
        return try inflate(&reader)
    }

    /// Decompresses a zlib stream, verifying its Adler-32 checksum.
    public static func zlibDecompress(_ input: [UInt8]) throws(Error) -> [UInt8] {
        guard input.count >= 6 else { throw .truncated }
        let cmf = input[0], flg = input[1]
        guard cmf & 0x0F == 8, (UInt16(cmf) << 8 | UInt16(flg)) % 31 == 0 else { throw .invalidHeader }
        guard flg & 0x20 == 0 else { throw .unsupportedPresetDictionary }
        var reader = BitReader(input, offset: 2)
        let output = try inflate(&reader)
        reader.alignToByte()
        let end = reader.byteOffset
        guard end + 4 <= input.count else { throw .truncated }
        let expected = UInt32(input[end]) << 24 | UInt32(input[end + 1]) << 16 | UInt32(input[end + 2]) << 8 | UInt32(input[end + 3])
        guard adler32(output) == expected else { throw .checksumMismatch }
        return output
    }

    /// Decompresses a gzip member, verifying its CRC-32 and length.
    public static func gzipDecompress(_ input: [UInt8]) throws(Error) -> [UInt8] {
        guard input.count >= 18 else { throw .truncated }
        guard input[0] == 0x1F, input[1] == 0x8B, input[2] == 8 else { throw .invalidHeader }
        let flags = input[3]
        var offset = 10
        if flags & 0x04 != 0 {
            // FEXTRA
            guard offset + 2 <= input.count else { throw .truncated }
            offset += 2 + (Int(input[offset]) | Int(input[offset + 1]) << 8)
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            // FNAME, FCOMMENT: zero-terminated strings
            while offset < input.count, input[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 {
            offset += 2 // FHCRC
        }
        guard offset < input.count else { throw .truncated }
        var reader = BitReader(input, offset: offset)
        let output = try inflate(&reader)
        reader.alignToByte()
        let end = reader.byteOffset
        guard end + 8 <= input.count else { throw .truncated }
        func le32(_ i: Int) -> UInt32 {
            UInt32(input[i]) | UInt32(input[i + 1]) << 8 | UInt32(input[i + 2]) << 16 | UInt32(input[i + 3]) << 24
        }
        guard crc32(output) == le32(end), UInt32(truncatingIfNeeded: output.count) == le32(end + 4) else {
            throw .checksumMismatch
        }
        return output
    }

    // MARK: - Checksums

    public static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        var index = 0
        while index < data.count {
            // 5552 is the largest block that cannot overflow before the modulo.
            let end = min(index + 5552, data.count)
            while index < end {
                a += UInt32(data[index])
                b += a
                index += 1
            }
            a %= 65521
            b %= 65521
        }
        return b << 16 | a
    }

    public static func crc32<C: Collection>(_ data: C, initial: UInt32 = 0) -> UInt32 where C.Element == UInt8 {
        var crc = ~initial
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return ~crc
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { n in
        var c = UInt32(n)
        for _ in 0 ..< 8 {
            c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    // MARK: - DEFLATE

    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static let fixedLiterals: Huffman = {
        var lengths = [UInt8](repeating: 8, count: 288)
        for i in 144 ..< 256 { lengths[i] = 9 }
        for i in 256 ..< 280 { lengths[i] = 7 }
        return try! Huffman(lengths: lengths)
    }()

    private static let fixedDistances = try! Huffman(lengths: [UInt8](repeating: 5, count: 30))

    private static func inflate(_ reader: inout BitReader) throws(Error) -> [UInt8] {
        var output = [UInt8]()
        output.reserveCapacity(reader.remainingBytes * 4)
        var isFinal = false
        while !isFinal {
            isFinal = try reader.bits(1) == 1
            switch try reader.bits(2) {
            case 0:
                try storedBlock(&reader, &output)
            case 1:
                try compressedBlock(&reader, &output, literals: fixedLiterals, distances: fixedDistances)
            case 2:
                let (literals, distances) = try dynamicTables(&reader)
                try compressedBlock(&reader, &output, literals: literals, distances: distances)
            default:
                throw .invalidBlockType
            }
        }
        return output
    }

    private static func storedBlock(_ reader: inout BitReader, _ output: inout [UInt8]) throws(Error) {
        reader.alignToByte()
        let length = try reader.bits(16)
        let complement = try reader.bits(16)
        guard length == ~complement & 0xFFFF else { throw .invalidStoredLength }
        try reader.copyBytes(length, into: &output)
    }

    private static func dynamicTables(_ reader: inout BitReader) throws(Error) -> (Huffman, Huffman) {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeLengthCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 30 else { throw .invalidHuffmanCode }

        var codeLengthLengths = [UInt8](repeating: 0, count: 19)
        for i in 0 ..< codeLengthCount {
            codeLengthLengths[codeLengthOrder[i]] = UInt8(try reader.bits(3))
        }
        let codeLengths = try Huffman(lengths: codeLengthLengths)

        var lengths = [UInt8]()
        lengths.reserveCapacity(literalCount + distanceCount)
        while lengths.count < literalCount + distanceCount {
            let symbol = try codeLengths.decode(&reader)
            switch symbol {
            case 0 ..< 16:
                lengths.append(UInt8(symbol))
            case 16:
                guard let previous = lengths.last else { throw .invalidHuffmanCode }
                lengths.append(contentsOf: repeatElement(previous, count: 3 + (try reader.bits(2))))
            case 17:
                lengths.append(contentsOf: repeatElement(0, count: 3 + (try reader.bits(3))))
            default:
                lengths.append(contentsOf: repeatElement(0, count: 11 + (try reader.bits(7))))
            }
        }
        guard lengths.count == literalCount + distanceCount, lengths[256] != 0 else { throw .invalidHuffmanCode }
        return (
            try Huffman(lengths: Array(lengths[..<literalCount])),
            try Huffman(lengths: Array(lengths[literalCount...]))
        )
    }

    private static func compressedBlock(
        _ reader: inout BitReader,
        _ output: inout [UInt8],
        literals: Huffman,
        distances: Huffman
    ) throws(Error) {
        while true {
            let symbol = try literals.decode(&reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
                continue
            }
            if symbol == 256 { return }
            let lengthIndex = symbol - 257
            guard lengthIndex < lengthBase.count else { throw .invalidHuffmanCode }
            let length = lengthBase[lengthIndex] + (try reader.bits(lengthExtra[lengthIndex]))
            let distanceSymbol = try distances.decode(&reader)
            guard distanceSymbol < distanceBase.count else { throw .invalidDistance }
            let distance = distanceBase[distanceSymbol] + (try reader.bits(distanceExtra[distanceSymbol]))
            guard distance <= output.count else { throw .invalidDistance }
            // Byte-by-byte copy handles overlapping runs (distance < length).
            var source = output.count - distance
            for _ in 0 ..< length {
                output.append(output[source])
                source += 1
            }
        }
    }
}

// MARK: - Bit reader

/// LSB-first bit reader over a byte array.
struct BitReader {

    private let bytes: [UInt8]
    private var position: Int
    private var buffer: UInt64 = 0
    private var count = 0

    init(_ bytes: [UInt8], offset: Int = 0) {
        self.bytes = bytes
        self.position = offset
    }

    /// Offset of the next unread byte (valid after ``alignToByte()``).
    var byteOffset: Int {
        position - count / 8
    }

    var remainingBytes: Int {
        bytes.count - position + count / 8
    }

    /// Loads bytes until at least `n` bits are buffered, or the input ends.
    @inline(__always)
    private mutating func fill(_ n: Int) {
        while count < n, position < bytes.count {
            buffer |= UInt64(bytes[position]) << count
            position += 1
            count += 8
        }
    }

    /// Up to `n` buffered bits without consuming them (missing bits read as zero).
    @inline(__always)
    mutating func peek(_ n: Int) -> (value: Int, available: Int) {
        fill(n)
        return (Int(buffer & ((1 << UInt64(n)) - 1)), min(count, n))
    }

    @inline(__always)
    mutating func consume(_ n: Int) {
        buffer >>= UInt64(n)
        count -= n
    }

    @inline(__always)
    mutating func bits(_ n: Int) throws(Inflate.Error) -> Int {
        guard n > 0 else { return 0 }
        fill(n)
        guard count >= n else { throw .truncated }
        let value = Int(buffer & ((1 << UInt64(n)) - 1))
        consume(n)
        return value
    }

    mutating func alignToByte() {
        consume(count % 8)
    }

    /// Copies whole bytes after ``alignToByte()``.
    mutating func copyBytes(_ n: Int, into output: inout [UInt8]) throws(Inflate.Error) {
        // Drain buffered whole bytes first.
        var remaining = n
        while remaining > 0, count >= 8 {
            output.append(UInt8(buffer & 0xFF))
            consume(8)
            remaining -= 1
        }
        guard position + remaining <= bytes.count else { throw .truncated }
        output.append(contentsOf: bytes[position ..< position + remaining])
        position += remaining
    }
}

// MARK: - Huffman

/// Canonical Huffman decoder with a 9-bit lookup table and a bit-serial fallback.
struct Huffman {

    private static let fastBits = 9

    /// Number of codes of each length (1...15).
    private var counts = [Int](repeating: 0, count: 16)
    /// Symbols ordered by code length, then value.
    private var symbols: [Int] = []
    /// `symbol << 4 | length` for codes up to `fastBits` long, indexed by reversed code; 0 if absent.
    private var fast = [UInt16](repeating: 0, count: 1 << Huffman.fastBits)

    init(lengths: [UInt8]) throws(Inflate.Error) {
        for length in lengths {
            counts[Int(length)] += 1
        }
        counts[0] = 0
        // Reject over-subscribed codes; incomplete codes are allowed (e.g. a single distance code).
        var left = 1
        for length in 1 ... 15 {
            left = (left << 1) - counts[length]
            if left < 0 { throw .invalidHuffmanCode }
        }

        var offsets = [Int](repeating: 0, count: 16)
        for length in 1 ..< 15 {
            offsets[length + 1] = offsets[length] + counts[length]
        }
        symbols = [Int](repeating: 0, count: lengths.count)
        for (symbol, length) in lengths.enumerated() where length != 0 {
            symbols[offsets[Int(length)]] = symbol
            offsets[Int(length)] += 1
        }

        // Canonical codes (MSB-first), stored bit-reversed for LSB-first lookup.
        var code = 0
        var index = 0
        for length in 1 ... 15 {
            for _ in 0 ..< counts[length] {
                if length <= Self.fastBits {
                    var reversed = 0
                    for bit in 0 ..< length where code & (1 << bit) != 0 {
                        reversed |= 1 << (length - 1 - bit)
                    }
                    let entry = UInt16(symbols[index] << 4 | length)
                    var fill = reversed
                    while fill < 1 << Self.fastBits {
                        fast[fill] = entry
                        fill += 1 << length
                    }
                }
                code += 1
                index += 1
            }
            code <<= 1
        }
    }

    @inline(__always)
    func decode(_ reader: inout BitReader) throws(Inflate.Error) -> Int {
        let (bits, available) = reader.peek(Self.fastBits)
        let entry = fast[bits]
        if entry != 0 {
            let length = Int(entry & 0xF)
            guard length <= available else { throw .truncated }
            reader.consume(length)
            return Int(entry >> 4)
        }
        // Longer codes: decode one bit at a time.
        var code = 0, first = 0, index = 0
        for length in 1 ... 15 {
            code |= try reader.bits(1)
            let count = counts[length]
            if code - first < count {
                return symbols[index + code - first]
            }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        throw .invalidHuffmanCode
    }
}
