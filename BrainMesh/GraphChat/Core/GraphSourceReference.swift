//
//  GraphSourceReference.swift
//  BrainMesh
//
//  Stable technical source references for evidence and navigation.
//

import Foundation

nonisolated enum GraphSourceKind: String, CaseIterable, Hashable, Sendable {
    case graph
    case entity
    case attribute
    case detailField
    case detailValue
    case link
    case attachment
}

nonisolated struct GraphSourceNodeReference: Hashable, Sendable {
    let kind: NodeKind
    let id: UUID

    var nodeKey: NodeRefKey {
        NodeRefKey(kind: kind, id: id)
    }
}

nonisolated enum GraphSourceLinkDirection:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case incoming
    case outgoing
}

nonisolated struct GraphSourceLinkBinding:
    Hashable,
    Sendable
{
    let linkID: UUID
    let source: GraphSourceNodeReference
    let target: GraphSourceNodeReference
    let direction: GraphSourceLinkDirection
    let note: String?
}

nonisolated enum GraphSourceNavigationTarget: Hashable, Sendable {
    case graph(GraphScope)
    case node(GraphScope, NodeRefKey)
}

nonisolated struct GraphSourceReference: Hashable, Sendable, Identifiable {
    let graphID: UUID
    let sourceKind: GraphSourceKind
    let sourceID: UUID
    let node: GraphSourceNodeReference?
    let owner: GraphSourceNodeReference?
    let fieldID: UUID?
    let linkID: UUID?
    let linkBinding: GraphSourceLinkBinding?
    let attachmentID: UUID?

    var id: GraphSourceReference {
        self
    }

    var nodeKind: NodeKind? {
        node?.kind
    }

    var nodeID: UUID? {
        node?.id
    }

    var ownerKind: NodeKind? {
        owner?.kind
    }

    var ownerID: UUID? {
        owner?.id
    }

    var navigationTarget: GraphSourceNavigationTarget? {
        let graphScope = GraphScope(graphID: graphID)

        if let node {
            return .node(graphScope, node.nodeKey)
        }
        if let owner {
            return .node(graphScope, owner.nodeKey)
        }

        switch sourceKind {
        case .graph:
            return .graph(graphScope)
        case .entity:
            return .node(
                graphScope,
                NodeRefKey(kind: .entity, id: sourceID)
            )
        case .attribute:
            return .node(
                graphScope,
                NodeRefKey(kind: .attribute, id: sourceID)
            )
        case .detailField, .detailValue, .link, .attachment:
            return nil
        }
    }

    init(
        graphID: UUID,
        sourceKind: GraphSourceKind,
        sourceID: UUID,
        node: GraphSourceNodeReference? = nil,
        owner: GraphSourceNodeReference? = nil,
        fieldID: UUID? = nil,
        linkID: UUID? = nil,
        linkBinding: GraphSourceLinkBinding? = nil,
        attachmentID: UUID? = nil
    ) {
        self.graphID = graphID
        self.sourceKind = sourceKind
        self.sourceID = sourceID
        self.node = node
        self.owner = owner
        self.fieldID = fieldID
        self.linkID = linkID
        self.linkBinding = linkBinding
        self.attachmentID = attachmentID
    }
}
