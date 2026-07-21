//
//  GraphChatScope.swift
//  BrainMesh
//
//  Graph-scoped, value-only chat boundaries.
//

import Foundation

nonisolated enum GraphChatScopeError: LocalizedError, Equatable, Sendable {
    case emptySelection
    case duplicateNode(NodeRefKey)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Eine Graph-Chat-Auswahl muss mindestens einen Node enthalten."
        case .duplicateNode:
            return "Eine Graph-Chat-Auswahl darf denselben Node nicht mehrfach enthalten."
        }
    }
}

nonisolated enum GraphChatScopeTarget: Hashable, Sendable {
    case graph
    case entity(UUID)
    case node(NodeRefKey)
    case selection([NodeRefKey])
}

nonisolated struct GraphChatScope: Hashable, Sendable {
    let graphScope: GraphScope
    let target: GraphChatScopeTarget

    init(
        graphScope: GraphScope,
        target: GraphChatScopeTarget
    ) throws {
        self.graphScope = graphScope

        switch target {
        case .graph, .entity, .node:
            self.target = target
        case .selection(let nodes):
            guard nodes.isEmpty == false else {
                throw GraphChatScopeError.emptySelection
            }

            var seen = Set<NodeRefKey>()
            for node in nodes {
                guard seen.insert(node).inserted else {
                    throw GraphChatScopeError.duplicateNode(node)
                }
            }

            self.target = .selection(nodes.sorted(by: Self.nodeSort))
        }
    }

    static func entireGraph(_ graphScope: GraphScope) -> GraphChatScope {
        GraphChatScope(uncheckedGraphScope: graphScope, target: .graph)
    }

    static func entity(
        _ entityID: UUID,
        in graphScope: GraphScope
    ) -> GraphChatScope {
        GraphChatScope(uncheckedGraphScope: graphScope, target: .entity(entityID))
    }

    static func node(
        _ node: NodeRefKey,
        in graphScope: GraphScope
    ) -> GraphChatScope {
        GraphChatScope(uncheckedGraphScope: graphScope, target: .node(node))
    }

    static func selection(
        _ nodes: [NodeRefKey],
        in graphScope: GraphScope
    ) throws -> GraphChatScope {
        try GraphChatScope(graphScope: graphScope, target: .selection(nodes))
    }

    var nodeReferences: [NodeRefKey] {
        switch target {
        case .graph, .entity:
            return []
        case .node(let node):
            return [node]
        case .selection(let nodes):
            return nodes
        }
    }

    private init(
        uncheckedGraphScope graphScope: GraphScope,
        target: GraphChatScopeTarget
    ) {
        self.graphScope = graphScope
        self.target = target
    }

    private static func nodeSort(_ lhs: NodeRefKey, _ rhs: NodeRefKey) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
