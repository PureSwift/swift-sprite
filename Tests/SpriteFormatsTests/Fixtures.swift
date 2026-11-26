//
//  Fixtures.swift
//  SpriteFormatsTests
//

import Foundation

/// Test files under `Fixtures/` (regenerate PNG/DEFLATE files with `make_fixtures.py`).
enum Fixtures {

    static var root: URL {
        Bundle.module.url(forResource: "Fixtures", withExtension: nil)!
    }

    static func url(_ path: String) -> URL {
        root.appending(path: path)
    }

    static func bytes(_ path: String) throws -> [UInt8] {
        Array(try Data(contentsOf: url(path)))
    }
}
