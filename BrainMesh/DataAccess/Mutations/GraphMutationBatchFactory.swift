//
//  GraphMutationBatchFactory.swift
//  BrainMesh
//
//  Value-only plans for precise, graph-scoped mutation batches.
//

import Foundation

/// Technical link identity captured before a model is inserted, updated, or deleted.
nonisolated struct GraphMutationLinkReference: Hashable, Sendable {
    let id: UUID
    let source: NodeRefKey
    let target: NodeRefKey

    init(
        id: UUID,
        source: NodeRefKey,
        target: NodeRefKey
    ) {
        self.id = id
        self.source = source
        self.target = target
    }
}

/// Technical detail-value identity captured before a model is inserted, updated, or deleted.
nonisolated struct GraphMutationDetailValueReference: Hashable, Sendable {
    let id: UUID
    let ownerAttributeID: UUID
    let fieldID: UUID

    init(
        id: UUID,
        ownerAttributeID: UUID,
        fieldID: UUID
    ) {
        self.id = id
        self.ownerAttributeID = ownerAttributeID
        self.fieldID = fieldID
    }
}

/// Central construction point for data-minimal PR-05A mutation classifications.
///
/// Every helper accepts technical identifiers only. No SwiftData model, label, note, detail value,
/// filename, title, image, or binary payload can enter the event layer through this API.
nonisolated enum GraphMutationBatchFactory {
    static func entityCreated(
        graphID: UUID,
        entityID: UUID
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [
                GraphMutationEvent(
                    graphID: graphID,
                    kind: .entityCreated,
                    references: [
                        .node(NodeRefKey(kind: .entity, id: entityID))
                    ]
                )
            ]
        )
    }

    static func attributeCreated(
        graphID: UUID,
        attributeID: UUID,
        ownerEntityID: UUID
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [
                GraphMutationEvent(
                    graphID: graphID,
                    kind: .attributeCreated,
                    references: [
                        .node(NodeRefKey(kind: .attribute, id: attributeID)),
                        .node(NodeRefKey(kind: .entity, id: ownerEntityID))
                    ]
                )
            ]
        )
    }

    /// Preserves the supplied order. `AddLinkView` supplies forward before reverse.
    static func linksCreated(
        graphID: UUID,
        links: [GraphMutationLinkReference]
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: links.map { linkEvent(graphID: graphID, kind: .linkCreated, link: $0) }
        )
    }

    static func linkUpdated(
        graphID: UUID,
        link: GraphMutationLinkReference
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [linkEvent(graphID: graphID, kind: .linkUpdated, link: link)]
        )
    }

    /// Sorts by technical link ID so a multi-delete does not depend on fetch or selection order.
    static func linksDeleted(
        graphID: UUID,
        links: [GraphMutationLinkReference]
    ) throws -> GraphMutationBatch {
        let ordered = links.sorted { lhs, rhs in
            uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
        }
        return try batch(
            graphID: graphID,
            events: ordered.map { linkEvent(graphID: graphID, kind: .linkDeleted, link: $0) }
        )
    }

    /// Preserves the caller's deterministic schema order while removing duplicate IDs.
    static func detailSchemaChanged(
        graphID: UUID,
        ownerEntityID: UUID,
        definitionIDs: [UUID]
    ) throws -> GraphMutationBatch {
        let orderedIDs = stableUnique(definitionIDs)
        let references = orderedIDs.map { definitionID in
            GraphMutationReference.detailFieldDefinition(
                id: definitionID,
                ownerEntityID: ownerEntityID
            )
        }
        return try batch(
            graphID: graphID,
            events: [
                GraphMutationEvent(
                    graphID: graphID,
                    kind: .detailSchemaChanged,
                    references: references
                )
            ]
        )
    }

    static func detailValueChanged(
        graphID: UUID,
        value: GraphMutationDetailValueReference
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [detailValueEvent(graphID: graphID, kind: .detailValueChanged, value: value)]
        )
    }

    static func detailValueDeleted(
        graphID: UUID,
        value: GraphMutationDetailValueReference
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [detailValueEvent(graphID: graphID, kind: .detailValueDeleted, value: value)]
        )
    }

    /// Emits value deletions first, ordered by field ID and then value ID, followed by one schema
    /// event whose definition references are ordered by technical ID.
    static func detailFieldsDeleted(
        graphID: UUID,
        ownerEntityID: UUID,
        affectedDefinitionIDs: [UUID],
        deletedValues: [GraphMutationDetailValueReference]
    ) throws -> GraphMutationBatch {
        let orderedValues = deletedValues.sorted { lhs, rhs in
            let lhsField = uuidSortKey(lhs.fieldID)
            let rhsField = uuidSortKey(rhs.fieldID)
            if lhsField != rhsField {
                return lhsField < rhsField
            }
            return uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
        }

        let orderedDefinitionIDs = Array(Set(affectedDefinitionIDs)).sorted { lhs, rhs in
            uuidSortKey(lhs) < uuidSortKey(rhs)
        }

        var events = orderedValues.map { value in
            detailValueEvent(
                graphID: graphID,
                kind: .detailValueDeleted,
                value: value
            )
        }
        events.append(
            GraphMutationEvent(
                graphID: graphID,
                kind: .detailSchemaChanged,
                references: orderedDefinitionIDs.map { definitionID in
                    .detailFieldDefinition(
                        id: definitionID,
                        ownerEntityID: ownerEntityID
                    )
                }
            )
        )

        return try batch(graphID: graphID, events: events)
    }

    private static func linkEvent(
        graphID: UUID,
        kind: GraphMutationKind,
        link: GraphMutationLinkReference
    ) -> GraphMutationEvent {
        GraphMutationEvent(
            graphID: graphID,
            kind: kind,
            references: [
                .link(
                    id: link.id,
                    source: link.source,
                    target: link.target
                )
            ]
        )
    }

    private static func detailValueEvent(
        graphID: UUID,
        kind: GraphMutationKind,
        value: GraphMutationDetailValueReference
    ) -> GraphMutationEvent {
        GraphMutationEvent(
            graphID: graphID,
            kind: kind,
            references: [
                .detailValue(
                    id: value.id,
                    ownerAttributeID: value.ownerAttributeID,
                    fieldID: value.fieldID
                )
            ]
        )
    }

    private static func batch(
        graphID: UUID,
        events: [GraphMutationEvent]
    ) throws -> GraphMutationBatch {
        try GraphMutationBatch(
            graphID: graphID,
            events: events
        )
    }

    private static func stableUnique(_ values: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func uuidSortKey(_ value: UUID) -> String {
        value.uuidString
    }
}
