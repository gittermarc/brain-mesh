//
//  SearchGraphTool.swift
//  BrainMesh
//
//  Local-index search with mandatory SwiftData source revalidation.
//

import Foundation

nonisolated struct SearchGraphInput: Sendable {
    let query: String
    let limit: Int

    init(query: String, limit: Int = 20) {
        self.query = query
        self.limit = limit
    }
}

nonisolated struct GraphChatSearchHit: Hashable, Sendable, Identifiable {
    let sourceReference: GraphSourceReference
    let kind: BrainMeshSearchResultKind
    let title: String
    let subtitle: String
    let matchReason: String
    let evidenceID: GraphEvidenceID

    var id: GraphSourceReference {
        sourceReference
    }
}

nonisolated struct SearchGraphOutput: Sendable {
    let query: String
    let hits: [GraphChatSearchHit]
}

nonisolated struct SearchGraphTool: GraphChatTool {
    let kind = GraphChatToolKind.searchGraph
    static let maximumResultCount = 50

    private struct ResolvedSource: Sendable {
        let reference: GraphSourceReference
        let title: String
        let subtitle: String
    }

    private struct ResolvedCandidate: Sendable {
        let candidate: BrainMeshSearchCandidate
        let source: ResolvedSource
        let evidence: GraphEvidence
    }

    private let readinessProvider: any BrainMeshSearchIndexReadinessProviding
    private let indexedProvider: any BrainMeshIndexedSearchCandidateProviding
    private let sourceRepository: any GraphEvidenceSourceReading
    private let evidenceValidator: any GraphEvidenceValidating
    private let logger: any GraphChatToolLogging

    init(
        readinessProvider: any BrainMeshSearchIndexReadinessProviding = GraphSearchIndexReconciler.shared,
        indexedProvider: any BrainMeshIndexedSearchCandidateProviding = IndexedSearchCandidateProvider(),
        sourceRepository: any GraphEvidenceSourceReading = GraphReadRepository.shared,
        evidenceValidator: any GraphEvidenceValidating = GraphEvidenceSourceValidator.shared,
        logger: any GraphChatToolLogging = GraphChatTechnicalLogger()
    ) {
        self.readinessProvider = readinessProvider
        self.indexedProvider = indexedProvider
        self.sourceRepository = sourceRepository
        self.evidenceValidator = evidenceValidator
        self.logger = logger
    }

    func execute(
        _ input: SearchGraphInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<SearchGraphOutput> {
        let timer = GraphChatToolTimer()
        var usedIndexFallback = false
        do {
            let foldedQuery = BMSearch.fold(input.query)
            guard foldedQuery.isEmpty == false else {
                throw GraphChatToolError(
                    code: .invalidInput,
                    message: "Die Suche benötigt einen nicht leeren Suchtext."
                )
            }
            let limit = try await context.budget.beginCall(
                tool: kind,
                requestedResultCount: input.limit,
                toolMaximumResultCount: Self.maximumResultCount
            )
            try Task.checkCancellation()

            let readiness = await readinessProvider.ensureReady(
                scope: context.scope.graphScope,
                reason: .chatSession
            )
            if readiness.outcome == .cancelled {
                throw CancellationError()
            }
            guard readiness.graphID == context.scope.graphScope.graphID,
                  readiness.isIndexUsable else {
                throw GraphChatToolError(
                    code: .indexUnavailable,
                    message: "Der lokale Suchindex ist für diesen Graphen nicht verfügbar."
                )
            }
            usedIndexFallback = readiness.outcome == .failed

            let candidateLimit = min(
                Self.maximumResultCount,
                max(limit, limit * 3)
            )
            let response = try await indexedProvider.candidates(
                graphIDs: [context.scope.graphScope.graphID],
                foldedQuery: foldedQuery,
                resultLimit: candidateLimit
            )
            try Task.checkCancellation()
            let sortedCandidates = BrainMeshSearchRanking.sortedCandidates(response.candidates)

            var resolved: [ResolvedCandidate] = []
            resolved.reserveCapacity(min(limit, sortedCandidates.count))
            for (index, candidate) in sortedCandidates.enumerated() {
                if index.isMultiple(of: 16) {
                    try Task.checkCancellation()
                }
                guard resolved.count < limit else {
                    break
                }
                guard candidate.result.graphID == context.scope.graphScope.graphID,
                      let source = try await resolvedSource(
                        for: candidate.result,
                        graphScope: context.scope.graphScope
                      ) else {
                    continue
                }
                let evidence = GraphEvidence(
                    sourceReference: source.reference,
                    summary: "\(source.title) — \(source.subtitle)",
                    navigationTitle: source.title,
                    identitySuffix: "search:\(foldedQuery):\(candidate.result.matchReason)"
                )
                resolved.append(
                    ResolvedCandidate(
                        candidate: candidate,
                        source: source,
                        evidence: evidence
                    )
                )
            }

            guard resolved.isEmpty == false else {
                logger.record(
                    timer.metric(
                        tool: kind,
                        resultCount: 0,
                        wasCancelled: false,
                        usedIndexFallback: usedIndexFallback
                    )
                )
                return .noResults()
            }

            let evidence = try await evidenceValidator.validatedEvidence(
                resolved.map(\.evidence),
                in: context.scope
            )
            try Task.checkCancellation()
            let evidenceByID = Dictionary(uniqueKeysWithValues: evidence.map { ($0.id, $0) })
            let hits = resolved.compactMap { item -> GraphChatSearchHit? in
                guard evidenceByID[item.evidence.id] != nil else {
                    return nil
                }
                return GraphChatSearchHit(
                    sourceReference: item.source.reference,
                    kind: item.candidate.result.kind,
                    title: item.source.title,
                    subtitle: item.source.subtitle,
                    matchReason: item.candidate.result.matchReason,
                    evidenceID: item.evidence.id
                )
            }

            guard hits.isEmpty == false else {
                logger.record(
                    timer.metric(
                        tool: kind,
                        resultCount: 0,
                        wasCancelled: false,
                        usedIndexFallback: usedIndexFallback
                    )
                )
                return .noResults()
            }
            try await context.budget.consumeEvidence(evidence.count)
            logger.record(
                timer.metric(
                    tool: kind,
                    resultCount: hits.count,
                    wasCancelled: false,
                    usedIndexFallback: usedIndexFallback
                )
            )
            return .success(
                SearchGraphOutput(query: foldedQuery, hits: hits),
                evidence: evidence
            )
        } catch is CancellationError {
            logger.record(
                timer.metric(
                    tool: kind,
                    resultCount: 0,
                    wasCancelled: true,
                    usedIndexFallback: usedIndexFallback
                )
            )
            throw GraphChatToolError.cancelled()
        } catch {
            logger.record(
                timer.metric(
                    tool: kind,
                    resultCount: 0,
                    wasCancelled: false,
                    usedIndexFallback: usedIndexFallback
                )
            )
            throw error
        }
    }

    private func resolvedSource(
        for result: BrainMeshSearchResult,
        graphScope: GraphScope
    ) async throws -> ResolvedSource? {
        switch result.kind {
        case .entity:
            guard let entity = try await sourceRepository.entity(id: result.id, in: graphScope) else {
                return nil
            }
            return ResolvedSource(
                reference: GraphSourceReference(
                    graphID: graphScope.graphID,
                    sourceKind: .entity,
                    sourceID: entity.id,
                    node: GraphSourceNodeReference(kind: .entity, id: entity.id)
                ),
                title: entity.name,
                subtitle: "Entity"
            )

        case .attribute:
            guard let attribute = try await sourceRepository.attribute(id: result.id, in: graphScope) else {
                return nil
            }
            return ResolvedSource(
                reference: GraphSourceReference(
                    graphID: graphScope.graphID,
                    sourceKind: .attribute,
                    sourceID: attribute.id,
                    node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                    owner: attribute.ownerEntityID.map {
                        GraphSourceNodeReference(kind: .entity, id: $0)
                    }
                ),
                title: attribute.displayLabel,
                subtitle: "Attribut"
            )

        case .link:
            guard let link = try await sourceRepository.link(id: result.id, in: graphScope) else {
                return nil
            }
            let navigationNode = link.sourceNodeKey ?? link.targetNodeKey
            return ResolvedSource(
                reference: GraphSourceReference(
                    graphID: graphScope.graphID,
                    sourceKind: .link,
                    sourceID: link.id,
                    node: navigationNode.map {
                        GraphSourceNodeReference(kind: $0.kind, id: $0.id)
                    },
                    linkID: link.id
                ),
                title: "\(link.sourceLabel) → \(link.targetLabel)",
                subtitle: link.note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? link.note ?? "Verbindung"
                    : "Verbindung"
            )

        case .detail:
            if let value = try await sourceRepository.detailValue(id: result.id, in: graphScope),
               let attribute = try await sourceRepository.attribute(
                id: value.attributeID,
                in: graphScope
               ) {
                let fieldName = value.fieldName ?? "Detail"
                return ResolvedSource(
                    reference: GraphSourceReference(
                        graphID: graphScope.graphID,
                        sourceKind: .detailValue,
                        sourceID: value.id,
                        node: GraphSourceNodeReference(kind: .attribute, id: attribute.id),
                        owner: attribute.ownerEntityID.map {
                            GraphSourceNodeReference(kind: .entity, id: $0)
                        },
                        fieldID: value.fieldID
                    ),
                    title: "\(attribute.displayLabel): \(fieldName)",
                    subtitle: "Detailwert"
                )
            }
            if let field = try await sourceRepository.detailFieldDefinition(
                id: result.id,
                in: graphScope
            ) {
                return ResolvedSource(
                    reference: GraphSourceReference(
                        graphID: graphScope.graphID,
                        sourceKind: .detailField,
                        sourceID: field.id,
                        owner: GraphSourceNodeReference(kind: .entity, id: field.entityID),
                        fieldID: field.id
                    ),
                    title: field.name,
                    subtitle: field.entityLabel ?? "Detailfeld"
                )
            }
            return nil

        case .attachment:
            guard let attachment = try await sourceRepository.attachmentMetadata(
                id: result.id,
                in: graphScope
            ), let owner = attachment.ownerNodeKey else {
                return nil
            }
            return ResolvedSource(
                reference: GraphSourceReference(
                    graphID: graphScope.graphID,
                    sourceKind: .attachment,
                    sourceID: attachment.id,
                    owner: GraphSourceNodeReference(kind: owner.kind, id: owner.id),
                    attachmentID: attachment.id
                ),
                title: attachment.title,
                subtitle: attachment.originalFilename
            )
        }
    }

}
