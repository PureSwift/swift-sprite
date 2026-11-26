//
//  InflateTests.swift
//  SpriteFormatsTests
//

import Testing
@testable import SpriteFormats

@Suite struct InflateTests {

    let payload: [UInt8]

    init() throws {
        payload = try Fixtures.bytes("Deflate/payload.bin")
    }

    @Test(arguments: ["stored.zlib", "fast.zlib", "best.zlib"])
    func zlibStreams(_ name: String) throws {
        #expect(try Inflate.zlibDecompress(Fixtures.bytes("Deflate/\(name)")) == payload)
    }

    @Test(arguments: ["raw.deflate", "fixed.deflate"])
    func rawStreams(_ name: String) throws {
        #expect(try Inflate.inflate(Fixtures.bytes("Deflate/\(name)")) == payload)
    }

    @Test func gzipWithFileName() throws {
        #expect(try Inflate.gzipDecompress(Fixtures.bytes("Deflate/payload.gz")) == payload)
    }

    @Test func detectsCorruption() throws {
        var data = try Fixtures.bytes("Deflate/best.zlib")
        data[data.count - 1] ^= 0xFF
        #expect(throws: Inflate.Error.checksumMismatch) { try Inflate.zlibDecompress(data) }

        let truncated = Array(try Fixtures.bytes("Deflate/best.zlib").prefix(100))
        #expect(throws: Inflate.Error.self) { try Inflate.zlibDecompress(truncated) }
        #expect(throws: Inflate.Error.invalidHeader) { try Inflate.zlibDecompress([0x00, 0x00, 0, 0, 0, 0]) }
    }

    @Test func checksums() {
        let bytes = Array("Wikipedia".utf8)
        #expect(Inflate.adler32(bytes) == 0x11E6_0398)
        #expect(Inflate.crc32(Array("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func emptyStoredBlock() throws {
        // Final stored block of length 0.
        #expect(try Inflate.inflate([0x01, 0x00, 0x00, 0xFF, 0xFF]) == [])
    }
}
