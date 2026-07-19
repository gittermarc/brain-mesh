//
//  GraphReadDTOs.swift
//  BrainMesh
//
//  Value-only, Sendable snapshots produced by the graph-scoped read repositories.
//

import Foundation

nonisolated struct GraphMetadataDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphScope
    let name: String
    let createdAt: Date
}

nonisolated struct GraphEntityDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphScope
    let name: String
    let notes: String
    let iconSymbolName: String?
    let createdAt: Date

    var nodeKey: NodeRefKey {
        NodeRefKey(kind: .entity, id: id)
    }

    var nodeSummary: GraphNodeSummaryDTO {
        GraphNodeSummaryDTO(
            scope: scope,
            nodeKey: nodeKey,
            label: name,
            notes: notes,
            iconSymbolName: iconSymbolName,
            ownerEntityID: nil,
            ownerLabel: nil
        )
    }
}

nonisolated struct GraphAttributeDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphScope
    let ownerEntityID: UUID?
    let ownerLabel: String?
    let name: String
    let displayLabel: String
    let notes: String
    let iconSymbolName: String?

    var nodeKey: NodeRefKey {
        NodeRefKey(kind: .attribute, id: id)
    }

    var nodeSummary: GraphNodeSummaryDTO {
        GraphNodeSummaryDTO(
            scope: scope,
            nodeKey: nodeKey,
            label: displayLabel,
            notes: notes,
            iconSymbolName: iconSymbolName,
            ownerEntityID: ownerEntityID,
            ownerLabel: ownerLabel
        )
    }
}

nonisolated struct GraphLinkDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphScope
    let createdAt: Date
    let sourceKindRaw: Int
    let sourceID: UUID
    let sourceLabel: String
    let targetKindRaw: Int
    let targetID: UUID
    let targetLabel: String
    let note: String?

    var sourceKind: NodeKind? {
        NodeKind(rawValue: sourceKindRaw)
    }

    var targetKind: NodeKind? {
        NodeKind(rawValue: targetKindRaw)
    }

    var sourceNodeKey: NodeRefKey? {
        guard let sourceKind else { return nil }
        return NodeRefKey(kind: sourceKind, id: sourceID)
    }

    var targetNodeKey: NodeRefKey? {
        guard let targetKind else { return nil }
        return NodeRefKey(kind: targetKind, id: targetID)
    }
}

nonisolated struct GraphDetailFieldDefinitionDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphScope
    let entityID: UUID
    let entityLabel: String?
    let name: String
    let typeRaw: Int
    let sortIndex: Int
    let isPinned: Bool
    let unit: String?
    let options: [String]

    var type: DetailFieldType {
        DetailFieldType(rawValue: typeRaw) ?? .singleLineText
    }
}

nonisolated enum GraphDetailValuePayload: Hashable, Sendable {
    case text(String)
    case integer(Int)
    case decimal(Double)
    case date(Date)
    case boolean(Bool)
    case choice(String)
    case empty
}

nonisolated struct GraphDetailValueDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphScope
    let attributeID: UUID
    let attributeLabel: String?
    let fieldID: UUID
    let fieldName: String?
    let fieldTypeRaw: Int?
    let value: GraphDetailValuePayload

    var fieldType: DetailFieldType? {
        guard let fieldTypeRaw else { return nil }
        return DetailFieldType(rawValue: fieldTypeRaw)
    }
}

nonisolated struct GraphAttachmentMetadataDTO: Identifiable, Hashable, Sendable {
    let id: UUID
    let scope: GraphScope
    let createdAt: Date
    let ownerKindRaw: Int
    let ownerID: UUID
    let ownerLabel: String?
    let contentKindRaw: Int
    let title: String
    let originalFilename: String
    let contentTypeIdentifier: String
    let fileExtension: String
    let byteCount: Int

    var ownerKind: NodeKind? {
        NodeKind(rawValue: ownerKindRaw)
    }

    var ownerNodeKey: NodeRefKey? {
        guard let ownerKind else { return nil }
        return NodeRefKey(kind: ownerKind, id: ownerID)
    }

    var contentKind: AttachmentContentKind? {
        AttachmentContentKind(rawValue: contentKindRaw)
    }
}

nonisolated struct GraphNodeSummaryDTO: Identifiable, Hashable, Sendable {
    let scope: GraphScope
    let nodeKey: NodeRefKey
    let label: String
    let notes: String
    let iconSymbolName: String?
    let ownerEntityID: UUID?
    let ownerLabel: String?

    var id: NodeRefKey {
        nodeKey
    }

    var kind: NodeKind {
        nodeKey.kind
    }
}

nonisolated struct GraphDirectNeighborhoodDTO: Hashable, Sendable {
    let scope: GraphScope
    let center: GraphNodeSummaryDTO
    let outgoingLinks: [GraphLinkDTO]
    let incomingLinks: [GraphLinkDTO]
    let neighbors: [GraphNodeSummaryDTO]
}

nonisolated struct GraphSourceSnapshotDTO: Equatable, Sendable {
    let scope: GraphScope
    let graph: GraphMetadataDTO
    let entities: [GraphEntityDTO]
    let attributes: [GraphAttributeDTO]
    let links: [GraphLinkDTO]
    let detailFieldDefinitions: [GraphDetailFieldDefinitionDTO]
    let detailValues: [GraphDetailValueDTO]
    let attachments: [GraphAttachmentMetadataDTO]

    var nodeSummaries: [GraphNodeSummaryDTO] {
        let entityNodes = entities.map(\.nodeSummary)
        let attributeNodes = attributes.map(\.nodeSummary)
        return (entityNodes + attributeNodes).sorted {
            if $0.nodeKey.kind.rawValue != $1.nodeKey.kind.rawValue {
                return $0.nodeKey.kind.rawValue < $1.nodeKey.kind.rawValue
            }
            return $0.nodeKey.id.uuidString < $1.nodeKey.id.uuidString
        }
    }
}
