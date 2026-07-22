//
//  GraphCanvasSelectionState.swift
//  BrainMesh
//
//  Single source of truth for the primary Canvas selection and retained chat members.
//

import Foundation

struct GraphCanvasSelectionState: Equatable, Sendable {
    private(set) var primary: NodeKey?
    private(set) var retainedNodes: Set<NodeKey>

    init(
        primary: NodeKey? = nil,
        retainedNodes: Set<NodeKey> = []
    ) {
        self.primary = primary
        self.retainedNodes = retainedNodes
        if let primary, retainedNodes.count == 1, retainedNodes.contains(primary) {
            self.retainedNodes.remove(primary)
        }
    }

    var chatNodes: [NodeKey] {
        var nodes = retainedNodes
        if let primary {
            nodes.insert(primary)
        }
        return nodes.sorted(by: Self.nodeSort)
    }

    var chatNodeCount: Int {
        chatNodes.count
    }

    var isPrimaryRetained: Bool {
        guard let primary else {
            return false
        }
        return retainedNodes.contains(primary)
    }

    mutating func setPrimary(_ node: NodeKey?) {
        guard let node else {
            clear()
            return
        }
        primary = node
    }

    mutating func togglePrimaryRetention() {
        guard let primary else {
            return
        }
        if retainedNodes.contains(primary) {
            retainedNodes.remove(primary)
            if let replacement = retainedNodes.sorted(by: Self.nodeSort).first {
                self.primary = replacement
                retainedNodes.remove(replacement)
            }
        } else {
            retainedNodes.insert(primary)
        }
    }

    mutating func clear() {
        primary = nil
        retainedNodes.removeAll()
    }

    mutating func retainAvailableNodes(_ availableNodes: Set<NodeKey>) {
        retainedNodes = retainedNodes.intersection(availableNodes)
        if let primary, availableNodes.contains(primary) == false {
            self.primary = nil
        }
        if primary == nil, let replacement = retainedNodes.sorted(by: Self.nodeSort).first {
            primary = replacement
            retainedNodes.remove(replacement)
        }
    }

    private static func nodeSort(_ lhs: NodeKey, _ rhs: NodeKey) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.uuid.uuidString < rhs.uuid.uuidString
    }
}
