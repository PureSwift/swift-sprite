//
//  Camera.swift
//  SpriteGraph
//

import SpriteCore

/// Node whose position, rotation and scale determine the visible region of a ``Scene``.
///
/// When set as ``Scene/camera`` the camera's position is placed at the center of the
/// view. Scaling the camera up zooms out. Children of the camera act as a HUD.
open class Camera: Node {

    /// Scene-space region visible through the camera for the scene's current size.
    public var visibleRect: Rect? {
        guard let scene else { return nil }
        let half = scene.size * 0.5
        return Rect(origin: -half, size: scene.size).applying(worldMatrix)
    }

    /// Whether the accumulated frame of `node` intersects the visible region.
    public func contains(_ node: Node) -> Bool {
        guard let visibleRect, let parent = node.parent else { return false }
        let frame = node.calculateAccumulatedFrame().applying(parent.worldMatrix)
        return visibleRect.intersects(frame)
    }
}
