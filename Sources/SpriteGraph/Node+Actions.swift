//
//  Node+Actions.swift
//  SpriteGraph
//

/// An action instance attached to a node.
@MainActor
struct RunningAction {

    let action: Action

    let key: String?

    let state: any ActionState

    /// Called with `true` when the action completes, `false` when it is removed.
    let completion: ((Bool) -> Void)?
}

public extension Node {

    /// Runs an action. Any running action with the same key is removed first.
    ///
    /// - Parameter completion: Called when the action completes (not when it is removed).
    func run(_ action: Action, withKey key: String? = nil, completion: (@MainActor () -> Void)? = nil) {
        if let key {
            removeAction(forKey: key)
        }
        actions.append(RunningAction(
            action: action,
            key: key,
            state: action.makeState(),
            completion: completion.map { completion in { finished in if finished { completion() } } }
        ))
    }

    /// Runs an action and suspends until it completes or is removed.
    func runAndWait(_ action: Action, withKey key: String? = nil) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            if let key {
                removeAction(forKey: key)
            }
            actions.append(RunningAction(
                action: action,
                key: key,
                state: action.makeState(),
                completion: { _ in continuation.resume() }
            ))
        }
    }

    var hasActions: Bool {
        !actions.isEmpty
    }

    func action(forKey key: String) -> Action? {
        actions.first { $0.key == key }?.action
    }

    func removeAction(forKey key: String) {
        let removed = actions.filter { $0.key == key }
        actions.removeAll { $0.key == key }
        removed.forEach { $0.completion?(false) }
    }

    func removeAllActions() {
        let removed = actions
        actions.removeAll()
        removed.forEach { $0.completion?(false) }
    }
}

extension Node {

    /// Advances actions on this node and its descendants, honoring `speed` and `isPaused`.
    func evaluateActions(seconds dt: Double) {
        guard !isPaused else { return }
        let scaled = dt * Double(speed)
        if !actions.isEmpty {
            advanceActions(by: scaled)
        }
        simulate(seconds: scaled)
        // Iterate a snapshot; actions may add or remove children.
        for child in children {
            child.evaluateActions(seconds: scaled)
        }
    }

    private func advanceActions(by dt: Double) {
        // Iterate a snapshot; completions may run or remove actions.
        for running in actions {
            guard actions.contains(where: { $0.state === running.state }) else { continue }
            if running.state.advance(self, by: dt) != nil {
                actions.removeAll { $0.state === running.state }
                running.completion?(true)
            }
        }
    }
}
