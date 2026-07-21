//
//  GraphChatSourceNavigation.swift
//  BrainMesh
//
//  Graph-safe evidence navigation into existing node details and graph jumps.
//

import Foundation

nonisolated enum GraphChatSourceDestination: Hashable, Sendable {
    case graph(graphID: UUID)
    case nodeDetail(graphID: UUID, node: NodeRefKey)
    case linkEndpoints(graphID: UUID, linkID: UUID)
}

nonisolated struct GraphChatSourceGraphJump: Hashable, Sendable {
    let graphID: UUID
    let nodeKey: NodeKey
}

nonisolated enum GraphChatSourceNavigationResolver {
    static func openDestination(
        for reference: GraphSourceReference,
        activeGraphID: UUID
    ) -> GraphChatSourceDestination? {
        guard reference.graphID == activeGraphID else {
            return nil
        }

        switch reference.sourceKind {
        case .graph:
            return .graph(graphID: reference.graphID)
        case .entity:
            return .nodeDetail(
                graphID: reference.graphID,
                node: NodeRefKey(kind: .entity, id: reference.sourceID)
            )
        case .attribute:
            return .nodeDetail(
                graphID: reference.graphID,
                node: NodeRefKey(kind: .attribute, id: reference.sourceID)
            )
        case .detailField:
            guard let owner = reference.owner else {
                return nil
            }
            return .nodeDetail(graphID: reference.graphID, node: owner.nodeKey)
        case .detailValue:
            guard let ownerNode = reference.owner ?? reference.node else {
                return nil
            }
            return .nodeDetail(graphID: reference.graphID, node: ownerNode.nodeKey)
        case .attachment:
            guard let owner = reference.owner else {
                return nil
            }
            return .nodeDetail(graphID: reference.graphID, node: owner.nodeKey)
        case .link:
            guard let linkID = reference.linkID else {
                return nil
            }
            return .linkEndpoints(graphID: reference.graphID, linkID: linkID)
        }
    }

    static func graphJump(
        for reference: GraphSourceReference,
        activeGraphID: UUID
    ) -> GraphChatSourceGraphJump? {
        guard reference.graphID == activeGraphID else {
            return nil
        }

        let node: GraphSourceNodeReference?
        switch reference.sourceKind {
        case .graph:
            node = nil
        case .entity:
            node = GraphSourceNodeReference(kind: .entity, id: reference.sourceID)
        case .attribute:
            node = GraphSourceNodeReference(kind: .attribute, id: reference.sourceID)
        case .detailField:
            node = reference.owner
        case .detailValue:
            node = reference.owner ?? reference.node
        case .attachment:
            node = reference.owner
        case .link:
            node = reference.node ?? reference.owner
        }

        guard let node else {
            return nil
        }
        return GraphChatSourceGraphJump(
            graphID: reference.graphID,
            nodeKey: NodeKey(kind: node.kind, uuid: node.id)
        )
    }
}
