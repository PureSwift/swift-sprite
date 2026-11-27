import Foundation
import Testing
import SpriteCore
import SpriteGraph
@testable import SpriteFormats

@Suite struct SceneArchiveActionTests {
    @MainActor private final class PlaybackLog {
        var nodes: [String] = []
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func resolvesAndSchedulesSounds(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/sound-actions." + format)))
        #expect(throws: SceneArchiveError.missingSound("beep.wav")) { try archive.makeNode() }
        let log = PlaybackLog()
        var requests = 0
        let scene = try #require(archive.makeNode(soundResolver: { name in
            requests += 1
            #expect(name == "beep.wav")
            return { node in log.nodes.append(node.name ?? "") }
        }) as? Scene)
        #expect(requests == 1 && log.nodes.isEmpty)
        let waiting = try #require(scene.children.first { $0.name == "waiting" })
        let immediate = try #require(scene.children.first { $0.name == "immediate" })
        scene.isPaused = true
        scene.advance(by: .seconds(1))
        #expect(log.nodes.isEmpty)
        scene.isPaused = false
        scene.advance(by: .milliseconds(125))
        #expect(log.nodes == ["waiting", "immediate"])
        #expect(waiting.position.x == 0 && immediate.position.x == 5)
        scene.advance(by: .milliseconds(250))
        #expect(log.nodes.count == 2)
        #expect(waiting.position.x == 5 && immediate.position.x == 10)
        waiting.removeAllActions()
        scene.advance(by: .seconds(1))
        #expect(log.nodes.count == 2 && waiting.position.x == 5)
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func repeatsLibrarySounds(format: String) throws {
        let library = try SpriteKitActionArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/sound-library." + format)))
        #expect(throws: SceneArchiveError.missingSound("beep.wav")) { try library.makeAction(named: "Beep") }
        let log = PlaybackLog()
        var requests = 0
        let action = try #require(try library.makeAction(named: "Beep", soundResolver: { _ in
            requests += 1
            return { node in log.nodes.append(node.name ?? "") }
        }))
        #expect(requests == 1 && log.nodes.isEmpty)
        let scene = Scene(size: [100, 100])
        scene.name = "scene"
        scene.run(action)
        scene.advance(by: .milliseconds(375))
        #expect(log.nodes == ["scene", "scene"])
        scene.advance(by: .seconds(1))
        #expect(!scene.hasActions && log.nodes.count == 2)
        scene.run(action)
        scene.removeAllActions()
        scene.advance(by: .seconds(1))
        #expect(log.nodes.count == 2)
    }

    @Test func rejectsMalformedSoundActions() throws {
        for fields: [String: PropertyValue] in [[:], ["_fileName": .string("")],
            ["_fileName": .string("beep"), "_wait": .bool(false), "_duration": .number(1)],
            ["_fileName": .string("beep"), "_position": .string("{1, 2}")],
            ["_fileName": .string("beep"), "_wait": .string("yes")]] {
            let (graph, node) = try archive(actionFields: fields, className: "SKPlaySound")
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(node) }
        }
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func loadsNamedActionLibraries(format: String) async throws {
        let library = try await SpriteKitActionArchive.decode(at: Fixtures.url("SceneArchives/action-library." + format))
        #expect(library.actionNames == ["Flipbook", "Move"])
        #expect(try library.makeAction(named: "missing") == nil)
        #expect(throws: SceneArchiveError.self) { try library.makeAction(named: "Flipbook") }
        var requests = 0
        let animation = try #require(try library.makeAction(named: "Flipbook", textureResolver: { _ in
            requests += 1
            return Texture(id: TextureID(rawValue: 7), textureSize: [80, 40])
        }))
        #expect(requests == 1)
        let sprite = Sprite(texture: nil)
        let scene = Scene(size: [100, 100])
        scene.addChild(sprite)
        sprite.run(animation)
        scene.advance(by: .milliseconds(125))
        #expect(sprite.texture?.size == [40, 40])
        scene.advance(by: .milliseconds(250))
        #expect(sprite.texture?.size == [80, 40])
        let move = try #require(try library.makeAction(named: "Move"))
        let a = Node(), b = Node()
        scene.addChild(a)
        scene.addChild(b)
        a.run(move)
        scene.advance(by: .milliseconds(500))
        b.run(move)
        scene.advance(by: .milliseconds(250))
        #expect(a.position == [15, 7.5] && b.position == [5, 2.5])
    }

    @Test func rejectsInvalidActionLibraries() throws {
        func data(keys: [String], values: [Any]) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: [
                "$archiver": "NSKeyedArchiver", "$version": 100_000,
                "$top": ["root": ["CF$UID": 1]],
                "$objects": ["$null",
                    ["$class": ["CF$UID": 2], "NS.keys": keys, "NS.objects": values],
                    ["$classname": "NSDictionary"]]
            ], format: .xml, options: 0)
        }
        for (keys, values): ([String], [Any]) in [([], []), (["actions"], []),
            (["actions", "actions"], [0, 0]), ([""], [0]), (["actions"], [42])] {
            #expect(throws: SceneArchiveError.self) { try SpriteKitActionArchive.decode(data(keys: keys, values: values)) }
        }
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresTextureAnimations(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf: Fixtures.url("SceneArchives/texture-actions." + format)))
        #expect(throws: SceneArchiveError.self) { try archive.makeNode() }
        var requests = 0
        let scene = try #require(archive.makeNode(textureResolver: { _ in
            requests += 1
            return Texture(id: TextureID(rawValue: 3), textureSize: [80, 40])
        }) as? Scene)
        #expect(requests == 1)
        let once = try #require(scene.children.first { $0.name == "once" } as? Sprite)
        let restore = try #require(scene.children.first { $0.name == "restore" } as? Sprite)
        let loop = try #require(scene.children.first { $0.name == "loop" } as? Sprite)
        let fixed = try #require(scene.children.first { $0.name == "fixed" } as? Sprite)
        #expect(once.size == [12, 8])
        scene.advance(by: .milliseconds(375))
        #expect(once.texture?.size == [40, 40] && once.size == [40, 40])
        #expect(loop.texture?.size == [80, 40])
        #expect(fixed.size == [12, 8] && fixed.texture?.size == [40, 40])
        scene.isPaused = true
        scene.advance(by: .seconds(1))
        #expect(once.texture?.size == [40, 40])
        scene.isPaused = false
        scene.advance(by: .milliseconds(250))
        #expect(once.texture?.size == [80, 40] && once.size == [80, 40])
        #expect(loop.texture?.size == [40, 40])
        scene.advance(by: .milliseconds(125))
        #expect(!once.hasActions && !restore.hasActions && loop.hasActions)
        #expect(restore.texture?.size == [20, 40] && restore.size == [20, 40])
        #expect(once.texture?.size == [80, 40])
        let fresh = try #require(archive.makeNode(textureResolver: { _ in
            Texture(id: TextureID(rawValue: 4), textureSize: [80, 40])
        }) as? Scene)
        #expect((fresh.children.first as? Sprite)?.size == [12, 8])
        let cancelled = try #require(fresh.children.first { $0.name == "restore" } as? Sprite)
        fresh.advance(by: .milliseconds(375))
        #expect(cancelled.texture?.size == [40, 40])
        cancelled.removeAction(forKey: "flipbook")
        #expect(cancelled.texture?.size == [20, 40] && cancelled.size == [20, 40])
        #expect(!cancelled.hasActions)
    }

    @MainActor @Test(arguments: ["sks", "xml"], [false, true])
    func restoresScheduledTextureReplacement(format: String, preserveSize: Bool) throws {
        let data = try Data(contentsOf: Fixtures.url("SceneArchives/set-texture-actions." + format))
        var plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        if preserveSize {
            var objects = try #require(plist["$objects"] as? [Any])
            for index in objects.indices {
                guard var fields = objects[index] as? [String: Any], fields["_textures"] != nil else { continue }
                fields["_resize"] = false
                objects[index] = fields
            }
            plist["$objects"] = objects
        }
        let archive = try SpriteKitSceneArchive.decode(PropertyListSerialization.data(
            fromPropertyList: plist, format: format == "sks" ? .binary : .xml, options: 0))
        #expect(throws: SceneArchiveError.self) { try archive.makeNode() }
        var requests = 0
        let scene = try #require(archive.makeNode(textureResolver: { _ in
            requests += 1
            return Texture(id: TextureID(rawValue: 9), textureSize: [80, 40])
        }) as? Scene)
        let sprites = scene.children.compactMap { $0 as? Sprite }
        #expect(sprites.count == 2 && requests == 1)
        #expect(sprites.allSatisfy { $0.texture == nil })
        scene.advance(by: .milliseconds(250))
        #expect(sprites.allSatisfy { $0.texture == nil })
        scene.advance(by: .milliseconds(500))
        #expect(sprites.map { $0.texture?.size } == [[40, 40], [40, 40]])
        #expect(sprites.map(\.size) == (preserveSize ? [[12, 8], [12, 8]] : [[40, 40], [40, 40]]))
        scene.advance(by: .milliseconds(500))
        #expect(sprites.map { $0.texture?.size } == [[80, 40], [80, 40]])
        #expect(sprites.map(\.size) == (preserveSize ? [[12, 8], [12, 8]] : [[80, 40], [80, 40]]))
        #expect(sprites.allSatisfy { !$0.hasActions })
        let cancelled = try archive.makeNode(textureResolver: { _ in
            Texture(id: TextureID(rawValue: 10), textureSize: [80, 40])
        })
        cancelled.children.forEach { $0.removeAllActions() }
        let cancelledScene = try #require(cancelled as? Scene)
        cancelledScene.advance(by: .seconds(2))
        #expect(cancelled.children.compactMap { $0 as? Sprite }.allSatisfy { $0.texture == nil })
    }

    @Test func rejectsMalformedTextureReplacement() throws {
        let graph = try KeyedArchive(ArchivePropertyList.decode(Data(contentsOf:
            Fixtures.url("SceneArchives/set-texture-actions.sks"))))
        let id = try #require(graph.objects.firstIndex { value in
            guard let fields = value.dictionary else { return false }
            return (try? graph.className(fields)) == "SKAnimate"
        })
        let fields = try graph.dictionary(.uid(id))
        let textures = try graph.array(fields["_textures"])
        for changes: [String: PropertyValue] in [
            ["_restore": .bool(true)], ["_resize": .string("yes")],
            ["_textures": .array([])], ["_textures": .array(textures + textures)],
            ["_duration": .number(0.000001)]
        ] {
            var objects = graph.objects
            objects[id] = .dictionary(fields.merging(changes) { _, new in new })
            let modified = try KeyedArchive(.dictionary(["$archiver": .string("NSKeyedArchiver"),
                "$version": .number(100_000), "$top": .dictionary(["root": .uid(graph.rootID)]),
                "$objects": .array(objects)]))
            var decoder = ArchiveActionDecoder(graph: modified)
            #expect(throws: SceneArchiveError.self) {
                try decoder.actions(["_actions": .array([.uid(id)])])
            }
        }
    }

    @Test func rejectsMalformedTextureAnimations() throws {
        let graph = try KeyedArchive(ArchivePropertyList.decode(Data(contentsOf: Fixtures.url("SceneArchives/texture-actions.sks"))))
        let id = try #require(graph.objects.firstIndex { value in
            guard let fields = value.dictionary else { return false }
            return (try? graph.className(fields)) == "SKAnimate"
        })
        for changes: [String: PropertyValue] in [
            ["_textures": .array([])], ["_timePerFrame": .number(0)],
            ["_timePerFrame": .number(-1)], ["_timePerFrame": .number(.infinity)],
            ["_duration": .number(99)], ["_finished": .bool(true)],
            ["_textures": .array(Array(repeating: .uid(0), count: 4097))]
        ] {
            var objects = graph.objects
            objects[id] = .dictionary(try graph.dictionary(.uid(id)).merging(changes) { _, new in new })
            let modified = try KeyedArchive(.dictionary(["$archiver": .string("NSKeyedArchiver"),
                "$version": .number(100_000), "$top": .dictionary(["root": .uid(graph.rootID)]), "$objects": .array(objects)]))
            var decoder = ArchiveActionDecoder(graph: modified)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(["_actions": .array([.uid(id)])]) }
        }
    }

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

    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresColorActions(format: String) throws {
        let archive = try SpriteKitSceneArchive.decode(Data(contentsOf:
            Fixtures.url("SceneArchives/color-actions." + format)))
        let scene = try #require(archive.makeNode() as? Scene)
        let color = try #require(scene.children[0] as? Sprite)
        let blend = try #require(scene.children[1] as? Sprite)
        let repeated = try #require(scene.children[2] as? Sprite)
        scene.advance(by: .seconds(1))
        #expect(abs(color.color.red - 0.5) < 0.00001 && abs(color.color.blue - 0.5) < 0.00001)
        #expect(color.colorBlendFactor == 0.375)
        #expect(blend.color == .blue && abs(blend.colorBlendFactor - 0.5) < 0.00001)
        #expect(repeated.color == .blue && repeated.hasActions)
        scene.advance(by: .seconds(1))
        #expect(color.color == .red && color.colorBlendFactor == 0.75)
        #expect(blend.color == .blue && abs(blend.colorBlendFactor - 0.2) < 0.00001)
        #expect(repeated.color == .blue && repeated.colorBlendFactor == 0)
        #expect(scene.children.allSatisfy { !$0.hasActions })
        let other = try archive.makeNode()
        let independent = try #require(other.children[0] as? Sprite)
        #expect(independent.color == .blue && independent.colorBlendFactor == 0)
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresIndependentScaleAxes(format: String) throws {
        let scene = try #require(SpriteKitSceneArchive.decode(Data(contentsOf:
            Fixtures.url("SceneArchives/axis-scale-actions." + format))).makeNode() as? Scene)
        scene.advance(by: .seconds(1))
        #expect(scene.children.map(\.scale) == [[3, 3], [2, 0.5], [3, 0.5]])
        scene.children[0].scale.y = 9
        scene.children[1].scale.x = 8
        scene.advance(by: .seconds(1))
        #expect(scene.children.map(\.scale) == [[4, 9], [8, -2], [4, -2]])
        #expect(scene.children.allSatisfy { !$0.hasActions })
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresSpriteResizeActions(format: String) throws {
        let scene = try #require(SpriteKitSceneArchive.decode(Data(contentsOf:
            Fixtures.url("SceneArchives/resize-actions." + format))).makeNode() as? Scene)
        let sprites = scene.children.compactMap { $0 as? Sprite }
        #expect(sprites.count == 6)
        scene.advance(by: .seconds(1))
        #expect(sprites.map(\.size) == [[30, 45], [30, 30], [20, 45], [30, 45], [25, 25], [30, 25]])
        sprites[1].size.y = 90
        sprites[2].size.x = 80
        scene.advance(by: .seconds(1))
        #expect(sprites.map(\.size) == [[40, 60], [40, 90], [80, 60], [40, 60], [30, 20], [40, 20]])
        #expect(sprites.allSatisfy { !$0.hasActions })
    }

    @Test func rejectsMalformedResizeActions() throws {
        let valid: [String: PropertyValue] = [
            "_useW": .bool(true), "_useH": .bool(true),
            "_sizeTarget.width": .number(40), "_sizeTarget.height": .number(60)
        ]
        for change: [String: PropertyValue] in [
            ["_useW": .bool(false), "_useH": .bool(false)],
            ["_useW": .string("yes")], ["_sizeTarget.width": .null],
            ["_sizeTarget.height": .number(.nan)], ["_sizeTarget.width": .number(.infinity)],
            ["_sizeResidual.width": .number(1)], ["_sizeResidual.height": .number(1)]
        ] {
            let (graph, node) = try archive(actionFields: valid.merging(change) { _, new in new },
                className: "SKResize")
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(node) }
        }
    }

    @MainActor @Test(arguments: ["sks", "xml"])
    func restoresSizeBasedScaling(format: String) throws {
        let scene = try #require(SpriteKitSceneArchive.decode(Data(contentsOf:
            Fixtures.url("SceneArchives/size-scale-actions." + format))).makeNode() as? Scene)
        let sprites = scene.children.compactMap { $0 as? Sprite }
        #expect(sprites.count == 2)
        scene.advance(by: .seconds(1))
        #expect(sprites.map(\.scale) == [[3, 2], [2, 1]])
        #expect(sprites.map(\.size) == [[20, 30], [40, 60]])
        scene.advance(by: .seconds(1))
        #expect(sprites.map(\.scale) == [[4, 3], [2, 2]])
        #expect(sprites.map(\.size) == [[20, 30], [40, 60]])
        #expect(sprites.allSatisfy { !$0.hasActions })
    }

    @Test func rejectsInvalidSizeBasedScaling() throws {
        let valid: [String: PropertyValue] = [
            "_useX": .bool(true), "_useY": .bool(true), "_isTargetSizeBased": .bool(true),
            "_targetSize": .string("{40, 60}")
        ]
        for change: [String: PropertyValue] in [
            ["_targetSize": .null], ["_targetSize": .string("invalid")],
            ["_targetSize": .string("{inf, 60}")], ["_isRelative": .bool(true)],
            ["_useX": .bool(false)]
        ] {
            let (graph, node) = try archive(actionFields: valid.merging(change) { _, new in new },
                className: "SKScale")
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(node) }
        }
    }

    @Test func rejectsInvalidScaleActions() throws {
        for fields: [String: PropertyValue] in [
            ["_useX": .bool(false), "_useY": .bool(false)],
            ["_useX": .bool(true), "_scaleTargetX": .number(.infinity)],
            ["_useY": .bool(true), "_isTargetSizeBased": .bool(true)],
            ["_useX": .bool(true), "_isRelative": .bool(true)]
        ] {
            let (graph, node) = try archive(actionFields: fields, className: "SKScale")
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(node) }
        }
    }

    @Test func rejectsMalformedColorActions() throws {
        let valid: [String: PropertyValue] = [
            "_duration": .number(1), "_colorMix": .number(0.5), "_isMixOnly": .bool(false),
            "_colorBlendR": .number(1), "_colorBlendG": .number(0),
            "_colorBlendB": .number(0), "_colorBlendA": .number(1)
        ]
        for change: [String: PropertyValue] in [
            ["_colorMix": .number(-0.1)], ["_colorMix": .number(1.1)],
            ["_colorMix": .number(.nan)], ["_colorMix": .null],
            ["_isMixOnly": .string("yes")], ["_isMixOnly": .null],
            ["_colorBlendR": .number(.infinity)], ["_colorBlendG": .number(-1)],
            ["_colorBlendB": .number(2)], ["_colorBlendA": .null]
        ] {
            let (graph, fields) = try archive(actionFields: valid.merging(change) { _, new in new },
                className: "SKColorize")
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(fields) }
        }
    }

    @Test func rejectsMalformedAndUnsupportedActions() throws {
        for fields: [String: PropertyValue] in [["_duration": .number(-1)],
            ["_duration": .number(.infinity)], ["_timingMode": .number(99)],
            ["_isReversed": .bool(true)], ["_lastRatio": .number(0.5)]] {
            let (graph, node) = try archive(actionFields: fields)
            var decoder = ArchiveActionDecoder(graph: graph)
            #expect(throws: SceneArchiveError.self) { try decoder.actions(node) }
        }
        for name in ["SKRunBlock", "CustomAction"] {
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
