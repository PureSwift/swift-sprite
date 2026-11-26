//
//  Node2DBuilder.swift
//  SpriteGraph
//

/// Result builder for declaratively composing node hierarchies.
///
/// ```swift
/// let root = Node(name: "root") {
///     Sprite(texture: ship)
///     if showShadow {
///         Sprite(color: .black, size: [32, 8])
///     }
///     for star in stars {
///         Sprite(texture: star)
///     }
/// }
/// ```
@resultBuilder
public enum Node2DBuilder {

    public static func buildExpression(_ node: Node) -> [Node] {
        [node]
    }

    public static func buildExpression(_ nodes: [Node]) -> [Node] {
        nodes
    }

    public static func buildBlock(_ components: [Node]...) -> [Node] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [Node]?) -> [Node] {
        component ?? []
    }

    public static func buildEither(first component: [Node]) -> [Node] {
        component
    }

    public static func buildEither(second component: [Node]) -> [Node] {
        component
    }

    public static func buildArray(_ components: [[Node]]) -> [Node] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [Node]) -> [Node] {
        component
    }
}
