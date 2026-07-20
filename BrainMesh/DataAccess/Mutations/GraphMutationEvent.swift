//
//  GraphMutationEvent.swift
//  BrainMesh
//
//  Data-minimal, graph-scoped mutation values for post-commit notifications.
//

import Foundation

/// Closed technical reasons for requesting a complete graph-source rebuild.
///
/// The enum intentionally carries no arbitrary text so mutation events cannot accidentally
/// transport names, notes, detail values, prompts, filenames, or other user content.
nonisolated enum GraphMutationFullRebuildReason: String, CaseIterable, Hashable, Sendable {
    case graphImport
    case graphReplacement
    case remoteChangeReconciliation
    case integrityRepair
    case unsupportedMutation
    case subscriberBufferOverflow
    case manualRecovery
}

/// The domain-level mutation represented by a `GraphMutationEvent`.
nonisolated enum GraphMutationKind: Hashable, Sendable {
    case entityCreated
    case entityUpdated
    case entityDeleted
    case attributeCreated
    case attributeUpdated
    case attributeDeleted
    case linkCreated
    case linkUpdated
    case linkDeleted
    case detailSchemaChanged
    case detailValueChanged
    case detailValueDeleted
    case attachmentCreated
    case attachmentUpdated
    case attachmentDeleted
    case detailTemplateCreated
    case graphCreated
    case graphUpdated
    case graphImported
    case graphReplaced
    case graphDeleted
    case graphRequiresFullRebuild(GraphMutationFullRebuildReason)

    var fullRebuildReason: GraphMutationFullRebuildReason? {
        guard case .graphRequiresFullRebuild(let reason) = self else {
            return nil
        }
        return reason
    }
}

/// An affected source record or graph node, expressed only through technical identifiers.
nonisolated enum GraphMutationReference: Hashable, Sendable {
    case graph
    case node(NodeRefKey)
    case link(
        id: UUID,
        source: NodeRefKey?,
        target: NodeRefKey?
    )
    case detailFieldDefinition(
        id: UUID,
        ownerEntityID: UUID?
    )
    case detailValue(
        id: UUID,
        ownerAttributeID: UUID?,
        fieldID: UUID?
    )
    case attachment(
        id: UUID,
        owner: NodeRefKey?
    )
    case detailTemplate(id: UUID)
}

/// A single graph-scoped mutation notification.
///
/// Events are value-only and intentionally exclude all user-authored content. Their timestamp
/// records local creation; delivery sequence is assigned later by `GraphMutationEventBus`.
nonisolated struct GraphMutationEvent: Hashable, Sendable {
    let graphID: UUID
    let kind: GraphMutationKind
    let references: [GraphMutationReference]
    let createdAt: Date

    init(
        graphID: UUID,
        kind: GraphMutationKind,
        references: [GraphMutationReference] = [],
        createdAt: Date = Date()
    ) {
        self.graphID = graphID
        self.kind = kind
        self.references = references
        self.createdAt = createdAt
    }

    init(
        scope: GraphScope,
        kind: GraphMutationKind,
        references: [GraphMutationReference] = [],
        createdAt: Date = Date()
    ) {
        self.init(
            graphID: scope.graphID,
            kind: kind,
            references: references,
            createdAt: createdAt
        )
    }

    var scope: GraphScope {
        GraphScope(graphID: graphID)
    }

    var fullRebuildReason: GraphMutationFullRebuildReason? {
        kind.fullRebuildReason
    }
}

nonisolated enum GraphMutationBatchError: LocalizedError, Equatable, Sendable {
    case empty
    case mixedGraphScopes

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Ein Mutation-Batch muss mindestens ein Event enthalten."
        case .mixedGraphScopes:
            return "Ein Mutation-Batch darf nur Events desselben Graphen enthalten."
        }
    }
}

/// An atomic group of post-commit events produced by one successful user action.
///
/// The initializer enforces a single graph scope. Event order is preserved exactly and is the
/// order subscribers receive within the batch.
nonisolated struct GraphMutationBatch: Identifiable, Hashable, Sendable {
    let id: UUID
    let graphID: UUID
    let createdAt: Date
    let events: [GraphMutationEvent]

    init(
        id: UUID = UUID(),
        graphID: UUID,
        events: [GraphMutationEvent],
        createdAt: Date = Date()
    ) throws {
        guard events.isEmpty == false else {
            throw GraphMutationBatchError.empty
        }
        guard events.allSatisfy({ $0.graphID == graphID }) else {
            throw GraphMutationBatchError.mixedGraphScopes
        }

        self.id = id
        self.graphID = graphID
        self.createdAt = createdAt
        self.events = events
    }

    init(
        id: UUID = UUID(),
        scope: GraphScope,
        events: [GraphMutationEvent],
        createdAt: Date = Date()
    ) throws {
        try self.init(
            id: id,
            graphID: scope.graphID,
            events: events,
            createdAt: createdAt
        )
    }

    var scope: GraphScope {
        GraphScope(graphID: graphID)
    }
}

/// A bus-assigned, monotonic delivery wrapper around one committed mutation batch.
nonisolated struct GraphMutationDelivery: Identifiable, Hashable, Sendable {
    let sequenceNumber: UInt64
    let publishedAt: Date
    let batch: GraphMutationBatch

    var id: UInt64 {
        sequenceNumber
    }

    var graphID: UUID {
        batch.graphID
    }
}
