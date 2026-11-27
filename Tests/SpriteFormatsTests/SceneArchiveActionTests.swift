import Foundation
import Testing
import SpriteCore
import SpriteGraph
@testable import SpriteFormats

@Suite struct SceneArchiveActionTests {
    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresAndRunsNativeActions(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/actions." + format)))
        let scene = try #require(archive.makeNode() as? Scene)
        let independent = try #require(archive.makeNode() as? Scene)
        let nodes = Dictionary(uniqueKeysWithValues: scene.children.compactMap { node in node.name.map { ($0, node) } })
        func node(_ name: String) throws -> Node { try #require(nodes[name]) }
        for child in scene.children where child.name != "unkeyed" {
            #expect(child.action(forKey: "animation") != nil)
        }
        #expect(try node("unkeyed").hasActions)
        #expect(try node("unkeyed").action(forKey: "animation") == nil)
        scene.advance(by: .seconds(1))
        #expect(try node("move").position == [6, 12])
        #expect(try node("moveTo").position == [10, 15])
        #expect(try node("moveX").position == [8, 0])
        #expect(try node("rotate").zRotation == 0.5)
        #expect(try node("rotateTo").zRotation == 1)
        #expect(try node("scale").scale == [1.5, 1.5])
        #expect(try node("scaleBy").scale == [2, 2])
        #expect(try abs(node("fade").alpha - 0.6) < 0.00001)
        #expect(try node("sequence").position == [10, 0])
        #expect(try node("group").position == [5, 10])
        #expect(try node("group").alpha == 0.5)
        #expect(try node("repeat").position == [10, 0])
        #expect(try node("forever").position == [10, 0])
        #expect(try node("hide").isHidden && !node("unhide").isHidden)
        #expect(try node("remove").parent == nil)
        #expect(try node("unkeyed").position == [5, 0])
        #expect(independent.children.first?.position == .zero)
        scene.advance(by: .seconds(2))
        #expect(try node("move").position == [12, 24])
        #expect(try node("sequence").position == [10, 10])
        #expect(try node("repeat").position == [30, 0])
        #expect(try !node("repeat").hasActions)
        #expect(try node("forever").position == [30, 0])
        #expect(try node("forever").hasActions)
        try node("forever").removeAction(forKey: "animation")
        #expect(try !node("forever").hasActions)
    }

    private func archive(actionFields: [String: PropertyValue], className: String = "SKWait",
                         keyed: Bool = false, extra: [PropertyValue] = []) throws -> (KeyedArchive, [String: PropertyValue]) {
        let action = actionFields.merging(["$class": .uid(3)]) { old, _ in old }
        let graph = try KeyedArchive(.dictionary([
            "$archiver": .string("NSKeyedArchiver"), "$version": .number(100_000),
            "$top": .dictionary(["root": .uid(1)]), "$objects": .array([
                .string("$null"), .dictionary([:]), .dictionary(action),
                .dictionary(["$classname": .string(className)]),
                .dictionary(["$classname": .string("NSDictionary")])] + extra)]))
        var fields: [String: PropertyValue] = ["_actions": .array([.uid(2)])]
        if keyed {
            fields["_keyedActions"] = .dictionary(["$class": .uid(4),
                "NS.keys": .array([.string("key")]), "NS.objects": .array([.uid(2)])])
        }
        return (graph, fields)
    }

    @Test func rejectsMalformedAndUnsupportedActions() throws {
        for fields: [String: PropertyValue] in [["_duration": .number(-1)],
            ["_duration": .number(.infinity)], ["_timingMode": .number(99)],
            ["_isReversed": .bool(true)], ["_lastRatio": .number(0.5)]] {
            let (graph, node) = try archive(actionFields: fields)
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(node) }
        }
        for name in ["SKRunBlock", "SKPlaySound", "CustomAction"] {
            let (graph, node) = try archive(actionFields: [:], className: name)
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.unsupported("Action class \(name)")) { try decoder.actions(node) }
        }
    }

    @Test func rejectsCyclesAndInvalidKeyReferences() throws {
        let (graph, fields) = try archive(actionFields: ["_actions": .array([.uid(2)])], className: "SKSequence")
        var decoder = ArchiveActionDecoder(graph: graph)
        #expect(throws: SceneArchiveError.self) { try decoder.actions(fields) }
        let (keyedGraph, keyedFields) = try archive(actionFields: ["_duration": .number(1)], keyed: true)
        var keyedDecoder = ArchiveActionDecoder(graph: keyedGraph)
        #expect(try keyedDecoder.actions(keyedFields).count == 1)
        var missing = keyedFields
        missing["_actions"] = .array([])
        #expect(throws: SceneArchiveError.self) { try keyedDecoder.actions(missing) }
        var duplicate = keyedFields
        duplicate["_actions"] = .array([.uid(2), .uid(2)])
        #expect(throws: SceneArchiveError.self) { try keyedDecoder.actions(duplicate) }
    }

    @Test func rejectsInvalidRepeatAndRetiming() throws {
        for count: Double in [-1, 1.5, 100_001] {
            let (graph, fields) = try archive(actionFields: ["_repeatedAction": .uid(5),
                "_timesToRepeat": .number(count)], className: "SKRepeat", extra: [
                    .dictionary(["$class": .uid(6), "_duration": .number(1)]),
                    .dictionary(["$classname": .string("SKWait")])])
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.invalid("Invalid action repeat count")) { try decoder.actions(fields) }
        }
        for name in ["SKSequence", "SKGroup", "SKHide", "SKRemove"] {
            let (graph, fields) = try archive(actionFields: ["_duration": .number(1)], className: name)
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(fields) }
        }
    }
}
