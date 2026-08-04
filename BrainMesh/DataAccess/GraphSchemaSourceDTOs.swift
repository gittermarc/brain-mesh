//
//  GraphSchemaSourceDTOs.swift
//  BrainMesh
//
//  Value-only source values for the narrow graph-chat schema read path.
//

import Foundation

/// The only detail-value dimension that can widen a schema-source read.
nonisolated struct GraphSchemaSourceScope: Hashable, Sendable {
    let exampleFieldIDs: [UUID]

    init(exampleFieldIDs: Set<UUID> = []) {
        self.exampleFieldIDs = exampleFieldIDs.sorted {
            $0.uuidString < $1.uuidString
        }
    }

    var exampleFieldIDSet: Set<UUID> {
        Set(exampleFieldIDs)
    }
}

nonisolated struct GraphSchemaSourceEntityDTO:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    let scope: GraphScope
    let name: String
    let createdAt: Date

    var nodeKey: NodeRefKey {
        NodeRefKey(kind: .entity, id: id)
    }
}

/// An attribute node stripped of notes, media, relationships, and detail values.
nonisolated struct GraphSchemaSourceNodeDTO:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    let scope: GraphScope
    let ownerEntityID: UUID
    let name: String
    let displayName: String

    var nodeKey: NodeRefKey {
        NodeRefKey(kind: .attribute, id: id)
    }
}

nonisolated struct GraphSchemaSourceFieldDefinitionDTO:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    let scope: GraphScope
    let entityID: UUID
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

nonisolated struct GraphSchemaSourceExampleValueDTO:
    Identifiable,
    Hashable,
    Sendable
{
    let id: UUID
    let scope: GraphScope
    let attributeID: UUID
    let fieldID: UUID
    let value: GraphDetailValuePayload
}

/// The authoritative narrow input to `GraphSchemaService`.
///
/// This type deliberately has no representation for links, link notes, attachments, media,
/// backlinks, statistics, or unrequested detail values.
nonisolated struct GraphSchemaSourceSnapshotDTO: Hashable, Sendable {
    let scope: GraphScope
    let sourceScope: GraphSchemaSourceScope
    let graph: GraphMetadataDTO
    let entities: [GraphSchemaSourceEntityDTO]
    let nodes: [GraphSchemaSourceNodeDTO]
    let fieldDefinitions: [GraphSchemaSourceFieldDefinitionDTO]
    let exampleValues: [GraphSchemaSourceExampleValueDTO]

    init(
        scope: GraphScope,
        sourceScope: GraphSchemaSourceScope,
        graph: GraphMetadataDTO,
        entities: [GraphSchemaSourceEntityDTO],
        nodes: [GraphSchemaSourceNodeDTO],
        fieldDefinitions: [GraphSchemaSourceFieldDefinitionDTO],
        exampleValues: [GraphSchemaSourceExampleValueDTO]
    ) {
        precondition(graph.scope == scope)
        precondition(entities.allSatisfy { $0.scope == scope })
        precondition(nodes.allSatisfy { $0.scope == scope })
        precondition(fieldDefinitions.allSatisfy { $0.scope == scope })
        precondition(exampleValues.allSatisfy { $0.scope == scope })
        precondition(
            exampleValues.allSatisfy {
                sourceScope.exampleFieldIDSet.contains($0.fieldID)
            }
        )

        self.scope = scope
        self.sourceScope = sourceScope
        self.graph = graph
        self.entities = entities
        self.nodes = nodes
        self.fieldDefinitions = fieldDefinitions
        self.exampleValues = exampleValues
    }
}

/// Fetch-level instrumentation used by repository and performance regression tests.
nonisolated enum GraphSchemaSourceFetchKind: String, Hashable, Sendable {
    case graph
    case entities
    case nodes
    case fieldDefinitions
    case exampleValues
    case fullSourceSnapshot
    case links
    case attachments
    case media
    case backlinks
    case statistics
}

nonisolated struct GraphSchemaSourceInstrumentation: Sendable {
    private let recorder: @Sendable (GraphSchemaSourceFetchKind) -> Void

    static let disabled = GraphSchemaSourceInstrumentation { _ in }

    init(
        recorder: @escaping @Sendable (GraphSchemaSourceFetchKind) -> Void
    ) {
        self.recorder = recorder
    }

    func record(_ kind: GraphSchemaSourceFetchKind) {
        recorder(kind)
    }
}

