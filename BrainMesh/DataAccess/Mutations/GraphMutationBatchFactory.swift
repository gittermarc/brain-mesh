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

/// Technical attachment identity captured before a model is inserted, updated, or deleted.
nonisolated struct GraphMutationAttachmentReference: Hashable, Sendable {
    let id: UUID
    let owner: NodeRefKey

    init(
        id: UUID,
        owner: NodeRefKey
    ) {
        self.id = id
        self.owner = owner
    }
}

/// Technical schema cleanup for one owner entity.
nonisolated struct GraphMutationDetailSchemaCleanupReference: Hashable, Sendable {
    let ownerEntityID: UUID
    let definitionIDs: [UUID]

    init(
        ownerEntityID: UUID,
        definitionIDs: [UUID]
    ) {
        self.ownerEntityID = ownerEntityID
        self.definitionIDs = definitionIDs
    }
}

/// Central construction point for data-minimal graph mutation classifications.
///
/// Every helper accepts technical identifiers only. No SwiftData model, label, note, detail value,
/// filename, title, image, or binary payload can enter the event layer through this API.
nonisolated enum GraphMutationBatchFactory {
    static func graphCreated(graphID: UUID) throws -> GraphMutationBatch {
        try graphEventBatch(graphID: graphID, kind: .graphCreated)
    }

    static func graphUpdated(graphID: UUID) throws -> GraphMutationBatch {
        try graphEventBatch(graphID: graphID, kind: .graphUpdated)
    }

    static func graphDeleted(graphID: UUID) throws -> GraphMutationBatch {
        try graphEventBatch(graphID: graphID, kind: .graphDeleted)
    }

    static func graphIntegrityRepair(graphID: UUID) throws -> GraphMutationBatch {
        try graphEventBatch(
            graphID: graphID,
            kind: .graphRequiresFullRebuild(.integrityRepair)
        )
    }

    static func graphImported(graphID: UUID) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [
                graphEvent(graphID: graphID, kind: .graphImported),
                graphEvent(
                    graphID: graphID,
                    kind: .graphRequiresFullRebuild(.graphImport)
                )
            ]
        )
    }

    static func graphReplaced(graphID: UUID) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [
                graphEvent(graphID: graphID, kind: .graphReplaced),
                graphEvent(
                    graphID: graphID,
                    kind: .graphRequiresFullRebuild(.graphReplacement)
                )
            ]
        )
    }

    static func detailTemplateCreated(
        graphID: UUID,
        templateID: UUID
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [
                GraphMutationEvent(
                    graphID: graphID,
                    kind: .detailTemplateCreated,
                    references: [.detailTemplate(id: templateID)]
                )
            ]
        )
    }

    static func entityCreated(
        graphID: UUID,
        entityID: UUID
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [
                nodeEvent(
                    graphID: graphID,
                    kind: .entityCreated,
                    node: NodeRefKey(kind: .entity, id: entityID),
                    schemaImpact: .structure
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

    static func nodeUpdated(
        graphID: UUID,
        node: NodeRefKey
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [
                nodeEvent(
                    graphID: graphID,
                    kind: updatedKind(for: node.kind),
                    node: node,
                    schemaImpact: GraphMutationSchemaImpact.none
                )
            ]
        )
    }

    /// Emits the renamed node first and then every actually relabeled link ordered by link ID.
    static func nodeRenamed(
        graphID: UUID,
        node: NodeRefKey,
        relabeledLinks: [GraphMutationLinkReference]
    ) throws -> GraphMutationBatch {
        let orderedLinks = stableUniqueLinks(relabeledLinks).sorted { lhs, rhs in
            uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
        }
        var events = [
            nodeEvent(
                graphID: graphID,
                kind: updatedKind(for: node.kind),
                node: node,
                schemaImpact: .structure
            )
        ]
        events.append(contentsOf: orderedLinks.map { link in
            linkEvent(graphID: graphID, kind: .linkUpdated, link: link)
        })
        return try batch(graphID: graphID, events: events)
    }

    /// Preserves the supplied order. Add-link and bulk-link flows provide their final plan order.
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
        let ordered = stableUniqueLinks(links).sorted { lhs, rhs in
            uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
        }
        return try batch(
            graphID: graphID,
            events: ordered.map { linkEvent(graphID: graphID, kind: .linkDeleted, link: $0) }
        )
    }

    /// Preserves the final media-import plan order.
    static func attachmentsCreated(
        graphID: UUID,
        attachments: [GraphMutationAttachmentReference]
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: stableUniqueAttachments(attachments).map { attachment in
                attachmentEvent(
                    graphID: graphID,
                    kind: .attachmentCreated,
                    attachment: attachment
                )
            }
        )
    }

    static func attachmentUpdated(
        graphID: UUID,
        attachment: GraphMutationAttachmentReference
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [
                attachmentEvent(
                    graphID: graphID,
                    kind: .attachmentUpdated,
                    attachment: attachment
                )
            ]
        )
    }

    static func attachmentsUpdated(
        graphID: UUID,
        attachments: [GraphMutationAttachmentReference]
    ) throws -> GraphMutationBatch {
        let ordered = stableUniqueAttachments(attachments).sorted { lhs, rhs in
            uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
        }
        return try batch(
            graphID: graphID,
            events: ordered.map { attachment in
                attachmentEvent(
                    graphID: graphID,
                    kind: .attachmentUpdated,
                    attachment: attachment
                )
            }
        )
    }

    static func attachmentsDeleted(
        graphID: UUID,
        attachments: [GraphMutationAttachmentReference]
    ) throws -> GraphMutationBatch {
        let ordered = stableUniqueAttachments(attachments).sorted { lhs, rhs in
            uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
        }
        return try batch(
            graphID: graphID,
            events: ordered.map { attachment in
                attachmentEvent(
                    graphID: graphID,
                    kind: .attachmentDeleted,
                    attachment: attachment
                )
            }
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

    static func detailValueConsolidated(
        graphID: UUID,
        authoritativeValue: GraphMutationDetailValueReference,
        deletedValues: [GraphMutationDetailValueReference]
    ) throws -> GraphMutationBatch {
        var events = orderedDetailValues(deletedValues).map { value in
            detailValueEvent(
                graphID: graphID,
                kind: .detailValueDeleted,
                value: value
            )
        }
        events.append(
            detailValueEvent(
                graphID: graphID,
                kind: .detailValueChanged,
                value: authoritativeValue
            )
        )
        return try batch(graphID: graphID, events: events)
    }

    static func detailValuesDeleted(
        graphID: UUID,
        values: [GraphMutationDetailValueReference]
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: orderedDetailValues(values).map { value in
                detailValueEvent(
                    graphID: graphID,
                    kind: .detailValueDeleted,
                    value: value
                )
            }
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
        let orderedValues = orderedDetailValues(deletedValues)
        let orderedDefinitionIDs = stableUnique(affectedDefinitionIDs).sorted { lhs, rhs in
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
            detailSchemaEvent(
                graphID: graphID,
                ownerEntityID: ownerEntityID,
                definitionIDs: orderedDefinitionIDs
            )
        )

        return try batch(graphID: graphID, events: events)
    }

    /// Stable cleanup order follows persistence dependencies:
    /// links, detail values, detail schemas, attachments, attributes, entities.
    static func nodeDeletion(
        graphID: UUID,
        links: [GraphMutationLinkReference],
        detailValues: [GraphMutationDetailValueReference],
        detailSchemas: [GraphMutationDetailSchemaCleanupReference],
        attachments: [GraphMutationAttachmentReference],
        attributeIDs: [UUID],
        entityIDs: [UUID]
    ) throws -> GraphMutationBatch {
        let orderedLinks = stableUniqueLinks(links).sorted { lhs, rhs in
            uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
        }
        let orderedValues = orderedDetailValues(detailValues)
        let orderedSchemas = stableUniqueSchemas(detailSchemas).sorted { lhs, rhs in
            uuidSortKey(lhs.ownerEntityID) < uuidSortKey(rhs.ownerEntityID)
        }
        let orderedAttachments = stableUniqueAttachments(attachments).sorted { lhs, rhs in
            uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
        }
        let orderedAttributeIDs = stableUnique(attributeIDs).sorted { lhs, rhs in
            uuidSortKey(lhs) < uuidSortKey(rhs)
        }
        let orderedEntityIDs = stableUnique(entityIDs).sorted { lhs, rhs in
            uuidSortKey(lhs) < uuidSortKey(rhs)
        }

        var events: [GraphMutationEvent] = []
        events.append(contentsOf: orderedLinks.map { link in
            linkEvent(graphID: graphID, kind: .linkDeleted, link: link)
        })
        events.append(contentsOf: orderedValues.map { value in
            detailValueEvent(
                graphID: graphID,
                kind: .detailValueDeleted,
                value: value
            )
        })
        events.append(contentsOf: orderedSchemas.map { schema in
            detailSchemaEvent(
                graphID: graphID,
                ownerEntityID: schema.ownerEntityID,
                definitionIDs: stableUnique(schema.definitionIDs).sorted { lhs, rhs in
                    uuidSortKey(lhs) < uuidSortKey(rhs)
                }
            )
        })
        events.append(contentsOf: orderedAttachments.map { attachment in
            attachmentEvent(
                graphID: graphID,
                kind: .attachmentDeleted,
                attachment: attachment
            )
        })
        events.append(contentsOf: orderedAttributeIDs.map { attributeID in
            nodeEvent(
                graphID: graphID,
                kind: .attributeDeleted,
                node: NodeRefKey(kind: .attribute, id: attributeID),
                schemaImpact: .structure
            )
        })
        events.append(contentsOf: orderedEntityIDs.map { entityID in
            nodeEvent(
                graphID: graphID,
                kind: .entityDeleted,
                node: NodeRefKey(kind: .entity, id: entityID),
                schemaImpact: .structure
            )
        })

        return try batch(graphID: graphID, events: events)
    }

    private static func graphEventBatch(
        graphID: UUID,
        kind: GraphMutationKind
    ) throws -> GraphMutationBatch {
        try batch(
            graphID: graphID,
            events: [graphEvent(graphID: graphID, kind: kind)]
        )
    }

    private static func graphEvent(
        graphID: UUID,
        kind: GraphMutationKind
    ) -> GraphMutationEvent {
        GraphMutationEvent(
            graphID: graphID,
            kind: kind,
            references: [.graph]
        )
    }

    private static func nodeEvent(
        graphID: UUID,
        kind: GraphMutationKind,
        node: NodeRefKey,
        schemaImpact: GraphMutationSchemaImpact
    ) -> GraphMutationEvent {
        GraphMutationEvent(
            graphID: graphID,
            kind: kind,
            references: [.node(node)],
            schemaImpact: schemaImpact
        )
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

    private static func detailSchemaEvent(
        graphID: UUID,
        ownerEntityID: UUID,
        definitionIDs: [UUID]
    ) -> GraphMutationEvent {
        GraphMutationEvent(
            graphID: graphID,
            kind: .detailSchemaChanged,
            references: definitionIDs.map { definitionID in
                .detailFieldDefinition(
                    id: definitionID,
                    ownerEntityID: ownerEntityID
                )
            }
        )
    }

    private static func attachmentEvent(
        graphID: UUID,
        kind: GraphMutationKind,
        attachment: GraphMutationAttachmentReference
    ) -> GraphMutationEvent {
        GraphMutationEvent(
            graphID: graphID,
            kind: kind,
            references: [
                .attachment(
                    id: attachment.id,
                    owner: attachment.owner
                )
            ]
        )
    }

    private static func updatedKind(for kind: NodeKind) -> GraphMutationKind {
        switch kind {
        case .entity:
            return .entityUpdated
        case .attribute:
            return .attributeUpdated
        }
    }

    private static func orderedDetailValues(
        _ values: [GraphMutationDetailValueReference]
    ) -> [GraphMutationDetailValueReference] {
        var seen = Set<UUID>()
        return values
            .filter { seen.insert($0.id).inserted }
            .sorted { lhs, rhs in
                let lhsField = uuidSortKey(lhs.fieldID)
                let rhsField = uuidSortKey(rhs.fieldID)
                if lhsField != rhsField {
                    return lhsField < rhsField
                }
                return uuidSortKey(lhs.id) < uuidSortKey(rhs.id)
            }
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

    private static func stableUniqueLinks(
        _ values: [GraphMutationLinkReference]
    ) -> [GraphMutationLinkReference] {
        var seen = Set<UUID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func stableUniqueAttachments(
        _ values: [GraphMutationAttachmentReference]
    ) -> [GraphMutationAttachmentReference] {
        var seen = Set<UUID>()
        return values.filter { seen.insert($0.id).inserted }
    }

    private static func stableUniqueSchemas(
        _ values: [GraphMutationDetailSchemaCleanupReference]
    ) -> [GraphMutationDetailSchemaCleanupReference] {
        var merged: [UUID: [UUID]] = [:]
        for value in values {
            merged[value.ownerEntityID, default: []].append(contentsOf: value.definitionIDs)
        }
        return merged.map { ownerEntityID, definitionIDs in
            GraphMutationDetailSchemaCleanupReference(
                ownerEntityID: ownerEntityID,
                definitionIDs: stableUnique(definitionIDs)
            )
        }
    }

    private static func uuidSortKey(_ value: UUID) -> String {
        value.uuidString
    }
}
