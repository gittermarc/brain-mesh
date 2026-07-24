//
//  EntitiesHomeIndexedMatchProvider.swift
//  BrainMesh
//
//  Value-only mapping from the local graph search index to Entities Home
//  entity identifiers and the existing strong/notes-only match semantics.
//

import Foundation

nonisolated enum EntitiesHomeIndexedMatchClassification:
    Int,
    Hashable,
    Sendable
{
    case notesOnly = 0
    case strong = 1
}

nonisolated enum EntitiesHomeIndexedMatchOrigin:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case entitySource
    case entityNotes
    case attributeSource
    case attributeNotes
    case linkNotes

    var sortPrecedence: Int {
        switch self {
        case .entitySource:
            return 0
        case .entityNotes:
            return 1
        case .attributeSource:
            return 2
        case .attributeNotes:
            return 3
        case .linkNotes:
            return 4
        }
    }
}

nonisolated enum EntitiesHomeIndexedResultCompleteness:
    String,
    Equatable,
    Sendable
{
    case complete
    case potentiallyTruncated
    case indexUnavailable
    case reconciliationFailed
    case ownerResolutionIncomplete

    var isComplete: Bool {
        self == .complete
    }
}

nonisolated struct EntitiesHomeIndexedMatch: Hashable, Sendable {
    let entityID: UUID
    let classification: EntitiesHomeIndexedMatchClassification
    let origins: [EntitiesHomeIndexedMatchOrigin]
}

nonisolated struct EntitiesHomeIndexedMatchResult: Sendable {
    let matches: [EntitiesHomeIndexedMatch]
    let completeness: EntitiesHomeIndexedResultCompleteness
    let indexDocumentCount: Int

    static func unavailable(
        _ completeness: EntitiesHomeIndexedResultCompleteness
    ) -> EntitiesHomeIndexedMatchResult {
        EntitiesHomeIndexedMatchResult(
            matches: [],
            completeness: completeness,
            indexDocumentCount: 0
        )
    }
}

nonisolated protocol EntitiesHomeIndexedMatchProviding: Sendable {
    func matches(
        graphID: UUID,
        foldedQuery: String
    ) async throws -> EntitiesHomeIndexedMatchResult
}

nonisolated struct EntitiesHomeIndexedMatchProvider:
    EntitiesHomeIndexedMatchProviding,
    Sendable
{
    static let allowedDocumentKinds: Set<GraphSearchDocumentKind> = [
        .entity,
        .entityNotes,
        .attribute,
        .attributeNotes,
        .linkNotes
    ]
    // Keeps the single SwiftData owner query below a conservative SQLite
    // parameter ceiling, including its graph-scope binding.
    static let maximumAttributeOwnerResolutionCount = 900

    private struct AccumulatedMatch {
        var classification: EntitiesHomeIndexedMatchClassification
        var origins: Set<EntitiesHomeIndexedMatchOrigin>
    }

    private struct PendingAttributeMatch {
        let attributeID: UUID
        let expectedOwnerEntityID: UUID?
        let classification: EntitiesHomeIndexedMatchClassification
        let origin: EntitiesHomeIndexedMatchOrigin
    }

    private let store: GraphSearchIndexStore
    private let readinessProvider: any BrainMeshSearchIndexReadinessProviding
    private let attributeOwnerResolver: any EntitiesHomeAttributeOwnerResolving
    private let maximumDocumentCount: Int

    init(
        store: GraphSearchIndexStore = GraphSearchIndexStore.shared,
        readinessProvider: any BrainMeshSearchIndexReadinessProviding =
            GraphSearchIndexReconciler.shared,
        attributeOwnerResolver: any EntitiesHomeAttributeOwnerResolving =
            EntitiesHomeAttributeOwnerResolver.shared,
        maximumDocumentCount: Int = GraphSearchIndexStore.maximumSearchLimit
    ) {
        self.store = store
        self.readinessProvider = readinessProvider
        self.attributeOwnerResolver = attributeOwnerResolver
        self.maximumDocumentCount = max(
            1,
            min(
                maximumDocumentCount,
                GraphSearchIndexStore.maximumSearchLimit
            )
        )
    }

    func matches(
        graphID: UUID,
        foldedQuery: String
    ) async throws -> EntitiesHomeIndexedMatchResult {
        try Task.checkCancellation()
        let query = BMSearch.fold(foldedQuery)
        guard query.isEmpty == false else {
            return EntitiesHomeIndexedMatchResult(
                matches: [],
                completeness: .complete,
                indexDocumentCount: 0
            )
        }

        let scope = GraphScope(graphID: graphID)
        let readiness = await readinessProvider.ensureReady(
            scope: scope,
            reason: .firstSearch
        )
        try Task.checkCancellation()

        switch readiness.outcome {
        case .cancelled:
            throw CancellationError()
        case .failed:
            return .unavailable(.reconciliationFailed)
        case .unavailable:
            return .unavailable(.indexUnavailable)
        case .ready, .reconciled, .rebuilt:
            guard readiness.isIndexUsable else {
                return .unavailable(.indexUnavailable)
            }
        }

        let queryResult: GraphSearchDocumentQueryResult
        do {
            queryResult = try await store.matchingDocuments(
                in: graphID,
                text: query,
                documentKinds: Self.allowedDocumentKinds,
                limit: maximumDocumentCount
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            await readinessProvider.invalidate(
                scope: scope,
                reason: .indexFailure
            )
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()

        guard queryResult.isComplete else {
            return EntitiesHomeIndexedMatchResult(
                matches: [],
                completeness: .potentiallyTruncated,
                indexDocumentCount: queryResult.documents.count
            )
        }

        var accumulatedMatches: [UUID: AccumulatedMatch] = [:]
        var pendingAttributeMatches: [PendingAttributeMatch] = []
        pendingAttributeMatches.reserveCapacity(queryResult.documents.count)

        for (index, document) in queryResult.documents.enumerated() {
            if index.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            guard document.graphID == graphID else {
                return .unavailable(.reconciliationFailed)
            }

            switch document.documentKind {
            case .entity:
                Self.merge(
                    entityID: document.sourceID,
                    classification: .strong,
                    origin: .entitySource,
                    into: &accumulatedMatches
                )
            case .entityNotes:
                Self.merge(
                    entityID: document.sourceID,
                    classification: .notesOnly,
                    origin: .entityNotes,
                    into: &accumulatedMatches
                )
            case .attribute:
                guard document.ownerKind == .entity,
                      let ownerEntityID = document.ownerID
                else {
                    return .unavailable(.ownerResolutionIncomplete)
                }
                pendingAttributeMatches.append(
                    PendingAttributeMatch(
                        attributeID: document.sourceID,
                        expectedOwnerEntityID: ownerEntityID,
                        classification: .strong,
                        origin: .attributeSource
                    )
                )
            case .attributeNotes:
                guard document.ownerKind == .entity,
                      let ownerEntityID = document.ownerID
                else {
                    return .unavailable(.ownerResolutionIncomplete)
                }
                pendingAttributeMatches.append(
                    PendingAttributeMatch(
                        attributeID: document.sourceID,
                        expectedOwnerEntityID: ownerEntityID,
                        classification: .notesOnly,
                        origin: .attributeNotes
                    )
                )
            case .linkNotes:
                guard let sourceNode = document.navigation.sourceNode,
                      let targetNode = document.navigation.targetNode
                else {
                    return .unavailable(.ownerResolutionIncomplete)
                }
                guard Self.collect(
                    endpoint: sourceNode,
                    pendingAttributeMatches: &pendingAttributeMatches,
                    accumulatedMatches: &accumulatedMatches
                ),
                Self.collect(
                    endpoint: targetNode,
                    pendingAttributeMatches: &pendingAttributeMatches,
                    accumulatedMatches: &accumulatedMatches
                ) else {
                    return .unavailable(.ownerResolutionIncomplete)
                }
            case .link, .detailFieldDefinition, .detailValue, .attachmentMetadata:
                continue
            }
        }

        if pendingAttributeMatches.isEmpty == false {
            let attributeIDs = Array(
                Set(pendingAttributeMatches.map(\.attributeID))
            ).sorted {
                $0.uuidString < $1.uuidString
            }
            guard attributeIDs.count <= Self.maximumAttributeOwnerResolutionCount else {
                return EntitiesHomeIndexedMatchResult(
                    matches: [],
                    completeness: .ownerResolutionIncomplete,
                    indexDocumentCount: queryResult.documents.count
                )
            }

            let resolvedOwners = try await attributeOwnerResolver.ownerEntityIDs(
                graphID: graphID,
                attributeIDs: attributeIDs
            )
            try Task.checkCancellation()

            for (index, pendingMatch) in pendingAttributeMatches.enumerated() {
                if index.isMultiple(of: 64) {
                    try Task.checkCancellation()
                }
                guard let ownerEntityID = resolvedOwners[pendingMatch.attributeID],
                      pendingMatch.expectedOwnerEntityID == nil
                        || pendingMatch.expectedOwnerEntityID == ownerEntityID
                else {
                    return EntitiesHomeIndexedMatchResult(
                        matches: [],
                        completeness: .ownerResolutionIncomplete,
                        indexDocumentCount: queryResult.documents.count
                    )
                }
                Self.merge(
                    entityID: ownerEntityID,
                    classification: pendingMatch.classification,
                    origin: pendingMatch.origin,
                    into: &accumulatedMatches
                )
            }
        }

        try Task.checkCancellation()
        let matches = accumulatedMatches.map { entityID, accumulated in
            EntitiesHomeIndexedMatch(
                entityID: entityID,
                classification: accumulated.classification,
                origins: accumulated.origins.sorted {
                    if $0.sortPrecedence != $1.sortPrecedence {
                        return $0.sortPrecedence < $1.sortPrecedence
                    }
                    return $0.rawValue < $1.rawValue
                }
            )
        }.sorted {
            $0.entityID.uuidString < $1.entityID.uuidString
        }

        return EntitiesHomeIndexedMatchResult(
            matches: matches,
            completeness: .complete,
            indexDocumentCount: queryResult.documents.count
        )
    }

    private static func collect(
        endpoint: GraphSearchNodeReference,
        pendingAttributeMatches: inout [PendingAttributeMatch],
        accumulatedMatches: inout [UUID: AccumulatedMatch]
    ) -> Bool {
        guard let endpointKind = endpoint.kind else { return false }
        switch endpointKind {
        case .entity:
            merge(
                entityID: endpoint.id,
                classification: .notesOnly,
                origin: .linkNotes,
                into: &accumulatedMatches
            )
        case .attribute:
            pendingAttributeMatches.append(
                PendingAttributeMatch(
                    attributeID: endpoint.id,
                    expectedOwnerEntityID: nil,
                    classification: .notesOnly,
                    origin: .linkNotes
                )
            )
        }
        return true
    }

    private static func merge(
        entityID: UUID,
        classification: EntitiesHomeIndexedMatchClassification,
        origin: EntitiesHomeIndexedMatchOrigin,
        into matches: inout [UUID: AccumulatedMatch]
    ) {
        if var existing = matches[entityID] {
            if classification.rawValue > existing.classification.rawValue {
                existing.classification = classification
            }
            existing.origins.insert(origin)
            matches[entityID] = existing
        } else {
            matches[entityID] = AccumulatedMatch(
                classification: classification,
                origins: [origin]
            )
        }
    }
}
