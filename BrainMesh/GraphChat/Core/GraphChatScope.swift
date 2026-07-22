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
    case incompatibleContext

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Eine Graph-Chat-Auswahl muss mindestens einen Node enthalten."
        case .duplicateNode:
            return "Eine Graph-Chat-Auswahl darf denselben Node nicht mehrfach enthalten."
        case .incompatibleContext:
            return "Der sichtbare Graph-Chat-Kontext passt nicht zur technischen Scope-Grenze."
        }
    }
}

nonisolated enum GraphChatScopeTarget: Hashable, Sendable {
    case graph
    case entity(UUID)
    case node(NodeRefKey)
    case selection([NodeRefKey])
}

/// Stable identity for the user-visible context while the existing target keeps
/// enforcing the productive read-only authorization boundary.
nonisolated enum GraphChatScopeContext: Hashable, Sendable {
    case graph
    case entity(UUID)
    case detailField(entityID: UUID, fieldID: UUID)
    case node(NodeRefKey)
    case selection([NodeRefKey])
    case healthFinding(id: String, affectedNodes: [NodeRefKey])
}

nonisolated struct GraphChatScope: Hashable, Sendable {
    let graphScope: GraphScope
    let target: GraphChatScopeTarget
    let context: GraphChatScopeContext

    init(
        graphScope: GraphScope,
        target: GraphChatScopeTarget,
        context: GraphChatScopeContext? = nil
    ) throws {
        self.graphScope = graphScope
        let normalizedTarget = try Self.normalizedTarget(target)
        self.target = normalizedTarget
        self.context = try Self.normalizedContext(
            context ?? Self.defaultContext(for: normalizedTarget),
            target: normalizedTarget
        )
    }

    static func entireGraph(_ graphScope: GraphScope) -> GraphChatScope {
        GraphChatScope(
            uncheckedGraphScope: graphScope,
            target: .graph,
            context: .graph
        )
    }

    static func entity(
        _ entityID: UUID,
        in graphScope: GraphScope
    ) -> GraphChatScope {
        GraphChatScope(
            uncheckedGraphScope: graphScope,
            target: .entity(entityID),
            context: .entity(entityID)
        )
    }

    static func detailField(
        _ fieldID: UUID,
        entityID: UUID,
        in graphScope: GraphScope
    ) -> GraphChatScope {
        GraphChatScope(
            uncheckedGraphScope: graphScope,
            target: .entity(entityID),
            context: .detailField(entityID: entityID, fieldID: fieldID)
        )
    }

    static func node(
        _ node: NodeRefKey,
        in graphScope: GraphScope
    ) -> GraphChatScope {
        GraphChatScope(
            uncheckedGraphScope: graphScope,
            target: .node(node),
            context: .node(node)
        )
    }

    static func selection(
        _ nodes: [NodeRefKey],
        in graphScope: GraphScope
    ) throws -> GraphChatScope {
        try GraphChatScope(
            graphScope: graphScope,
            target: .selection(nodes),
            context: .selection(nodes)
        )
    }

    static func healthFinding(
        id: String,
        affectedNodes: [NodeRefKey],
        in graphScope: GraphScope
    ) throws -> GraphChatScope {
        let normalizedID = String(
            id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256)
        )
        let target: GraphChatScopeTarget = affectedNodes.isEmpty
            ? .graph
            : .selection(affectedNodes)
        return try GraphChatScope(
            graphScope: graphScope,
            target: target,
            context: .healthFinding(
                id: normalizedID.isEmpty ? "health-finding" : normalizedID,
                affectedNodes: affectedNodes
            )
        )
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
        target: GraphChatScopeTarget,
        context: GraphChatScopeContext
    ) {
        self.graphScope = graphScope
        self.target = target
        self.context = context
    }

    private static func normalizedTarget(
        _ target: GraphChatScopeTarget
    ) throws -> GraphChatScopeTarget {
        switch target {
        case .graph, .entity, .node:
            return target
        case .selection(let nodes):
            return .selection(try normalizedNodes(nodes))
        }
    }

    private static func normalizedContext(
        _ context: GraphChatScopeContext,
        target: GraphChatScopeTarget
    ) throws -> GraphChatScopeContext {
        switch context {
        case .graph:
            guard case .graph = target else {
                throw GraphChatScopeError.incompatibleContext
            }
            return .graph

        case .entity(let entityID):
            guard case .entity(let targetEntityID) = target,
                  targetEntityID == entityID else {
                throw GraphChatScopeError.incompatibleContext
            }
            return .entity(entityID)

        case .detailField(let entityID, let fieldID):
            guard case .entity(let targetEntityID) = target,
                  targetEntityID == entityID else {
                throw GraphChatScopeError.incompatibleContext
            }
            return .detailField(entityID: entityID, fieldID: fieldID)

        case .node(let node):
            guard case .node(let targetNode) = target,
                  targetNode == node else {
                throw GraphChatScopeError.incompatibleContext
            }
            return .node(node)

        case .selection(let nodes):
            let normalizedNodes = try normalizedNodes(nodes)
            guard case .selection(let targetNodes) = target,
                  targetNodes == normalizedNodes else {
                throw GraphChatScopeError.incompatibleContext
            }
            return .selection(normalizedNodes)

        case .healthFinding(let id, let affectedNodes):
            let normalizedID = String(
                id.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256)
            )
            let normalizedNodes = affectedNodes.isEmpty
                ? []
                : try normalizedNodes(affectedNodes)
            if normalizedNodes.isEmpty {
                guard case .graph = target else {
                    throw GraphChatScopeError.incompatibleContext
                }
            } else {
                guard case .selection(let targetNodes) = target,
                      targetNodes == normalizedNodes else {
                    throw GraphChatScopeError.incompatibleContext
                }
            }
            return .healthFinding(
                id: normalizedID.isEmpty ? "health-finding" : normalizedID,
                affectedNodes: normalizedNodes
            )
        }
    }

    private static func defaultContext(
        for target: GraphChatScopeTarget
    ) -> GraphChatScopeContext {
        switch target {
        case .graph:
            return .graph
        case .entity(let entityID):
            return .entity(entityID)
        case .node(let node):
            return .node(node)
        case .selection(let nodes):
            return .selection(nodes)
        }
    }

    private static func normalizedNodes(
        _ nodes: [NodeRefKey]
    ) throws -> [NodeRefKey] {
        guard nodes.isEmpty == false else {
            throw GraphChatScopeError.emptySelection
        }

        var seen = Set<NodeRefKey>()
        for node in nodes {
            guard seen.insert(node).inserted else {
                throw GraphChatScopeError.duplicateNode(node)
            }
        }
        return nodes.sorted(by: nodeSort)
    }

    private static func nodeSort(_ lhs: NodeRefKey, _ rhs: NodeRefKey) -> Bool {
        if lhs.kind.rawValue != rhs.kind.rawValue {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
