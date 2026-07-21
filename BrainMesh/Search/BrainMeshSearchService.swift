//
//  BrainMeshSearchService.swift
//  BrainMesh
//
//  Global graph-scoped search orchestrator. The service returns value-only DTOs and never exposes SwiftData models.
//

import Foundation
import os

actor BrainMeshSearchService {
    static let shared = BrainMeshSearchService(dependencies: .live)

    private struct SearchScope: Sendable {
        let graphIDs: [UUID]
        let graphID: UUID?
    }

    private struct CandidateLoadResult: Sendable {
        let candidates: [BrainMeshSearchCandidate]
        let indexDocumentCount: Int
        let source: BrainMeshSearchExecutionSource
        let fallbackReason: BrainMeshSearchFallbackReason?
        let readinessOutcomes: [GraphSearchIndexReadinessOutcome]
        let graphCount: Int
    }

    private var container: AnyModelContainer? = nil
    private let dependencies: BrainMeshSearchServiceDependencies
    private let log = Logger(subsystem: "BrainMesh", category: "BrainMeshSearchService")

    init(
        dependencies: BrainMeshSearchServiceDependencies = .legacyOnly
    ) {
        self.dependencies = dependencies
    }

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func search(
        graphID: UUID?,
        foldedQuery: String,
        limit: Int
    ) async throws -> BrainMeshSearchSnapshot {
        let query = BMSearch.fold(foldedQuery)
        guard query.isEmpty == false else {
            return BrainMeshSearchSnapshot(query: query, results: [])
        }

        try await AppLoadersConfigurator.waitUntilReadyIfNeeded(
            serviceContainerID: self.container?.identity
        )
        guard let configuredContainer = self.container else {
            throw NSError(
                domain: "BrainMesh.BrainMeshSearchService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "BrainMeshSearchService not configured"]
            )
        }

        let safeLimit = max(0, min(limit, 100))
        guard safeLimit > 0 else {
            return BrainMeshSearchSnapshot(query: query, results: [])
        }

        try Task.checkCancellation()
        let startedAt = BMDuration()
        let loaded = try await loadCandidates(
            container: configuredContainer,
            graphID: graphID,
            foldedQuery: query,
            resultLimit: safeLimit
        )
        try Task.checkCancellation()

        let sorted = BrainMeshSearchRanking.sortedCandidates(loaded.candidates)
        try Task.checkCancellation()
        let results = Array(sorted.prefix(safeLimit).map(\.result))
        try Task.checkCancellation()

        let readinessSummary = loaded.readinessOutcomes
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        let fallbackDescription = loaded.fallbackReason?.rawValue ?? "none"
        let scopeDescription = graphID == nil ? "global" : "graph"
        log.info(
            "Search completed source=\(loaded.source.rawValue, privacy: .public) fallback=\(fallbackDescription, privacy: .public) scope=\(scopeDescription, privacy: .public) graphs=\(loaded.graphCount) indexDocuments=\(loaded.indexDocumentCount) rankingCandidates=\(loaded.candidates.count) results=\(results.count) readiness=\(readinessSummary, privacy: .public) durationMS=\(startedAt.millisecondsElapsed, format: .fixed(precision: 2))"
        )
        return BrainMeshSearchSnapshot(query: query, results: results)
    }

    private func loadCandidates(
        container: AnyModelContainer,
        graphID: UUID?,
        foldedQuery: String,
        resultLimit: Int
    ) async throws -> CandidateLoadResult {
        guard let readinessProvider = dependencies.readinessProvider,
              let indexedProvider = dependencies.indexedProvider
        else {
            return try await loadLegacyCandidates(
                container: container,
                graphID: graphID,
                foldedQuery: foldedQuery,
                graphCount: graphID == nil ? 0 : 1,
                fallbackReason: .indexNotConfigured,
                readinessOutcomes: []
            )
        }

        let scopeResolution: SearchScope
        if let graphID {
            scopeResolution = SearchScope(
                graphIDs: [graphID],
                graphID: graphID
            )
        } else {
            let resolution: BrainMeshSearchGraphScopeResolution
            do {
                resolution = try await dependencies.scopeResolver.resolveGlobalScope(
                    container: container
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return try await loadLegacyCandidates(
                    container: container,
                    graphID: nil,
                    foldedQuery: foldedQuery,
                    graphCount: 0,
                    fallbackReason: .globalScopeUnavailable,
                    readinessOutcomes: []
                )
            }
            try Task.checkCancellation()
            guard resolution.canUseIndex else {
                return try await loadLegacyCandidates(
                    container: container,
                    graphID: nil,
                    foldedQuery: foldedQuery,
                    graphCount: resolution.graphIDs.count,
                    fallbackReason: resolution.fallbackReason ?? .globalScopeUnavailable,
                    readinessOutcomes: []
                )
            }
            let normalizedGraphIDs = GraphSearchIndexStore.normalizedGraphIDs(
                resolution.graphIDs
            )
            if normalizedGraphIDs.isEmpty {
                return CandidateLoadResult(
                    candidates: [],
                    indexDocumentCount: 0,
                    source: .index,
                    fallbackReason: nil,
                    readinessOutcomes: [],
                    graphCount: 0
                )
            }
            scopeResolution = SearchScope(
                graphIDs: normalizedGraphIDs,
                graphID: nil
            )
        }

        let readinessResults = await readinessResults(
            graphIDs: scopeResolution.graphIDs,
            provider: readinessProvider
        )
        try Task.checkCancellation()
        let readinessOutcomes = readinessResults.map(\.outcome)
        guard readinessResults.count == scopeResolution.graphIDs.count,
              readinessResults.allSatisfy(\.isIndexUsable)
        else {
            return try await loadLegacyCandidates(
                container: container,
                graphID: scopeResolution.graphID,
                foldedQuery: foldedQuery,
                graphCount: scopeResolution.graphIDs.count,
                fallbackReason: .readinessUnavailable,
                readinessOutcomes: readinessOutcomes
            )
        }

        do {
            let response = try await indexedProvider.candidates(
                graphIDs: scopeResolution.graphIDs,
                foldedQuery: foldedQuery,
                resultLimit: resultLimit
            )
            try Task.checkCancellation()
            return CandidateLoadResult(
                candidates: response.candidates,
                indexDocumentCount: response.indexDocumentCount,
                source: .index,
                fallbackReason: nil,
                readinessOutcomes: readinessOutcomes,
                graphCount: scopeResolution.graphIDs.count
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            for graphID in scopeResolution.graphIDs {
                await readinessProvider.invalidate(
                    scope: GraphScope(graphID: graphID),
                    reason: .indexFailure
                )
            }
            try Task.checkCancellation()
            return try await loadLegacyCandidates(
                container: container,
                graphID: scopeResolution.graphID,
                foldedQuery: foldedQuery,
                graphCount: scopeResolution.graphIDs.count,
                fallbackReason: .indexQueryFailed,
                readinessOutcomes: readinessOutcomes
            )
        }
    }

    private func readinessResults(
        graphIDs: [UUID],
        provider: any BrainMeshSearchIndexReadinessProviding
    ) async -> [GraphSearchIndexReadinessResult] {
        await withTaskGroup(
            of: GraphSearchIndexReadinessResult.self,
            returning: [GraphSearchIndexReadinessResult].self
        ) { group in
            for graphID in graphIDs {
                group.addTask {
                    await provider.ensureReady(
                        scope: GraphScope(graphID: graphID),
                        reason: .firstSearch
                    )
                }
            }

            var results: [GraphSearchIndexReadinessResult] = []
            results.reserveCapacity(graphIDs.count)
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in
                lhs.graphID.uuidString < rhs.graphID.uuidString
            }
        }
    }

    private func loadLegacyCandidates(
        container: AnyModelContainer,
        graphID: UUID?,
        foldedQuery: String,
        graphCount: Int,
        fallbackReason: BrainMeshSearchFallbackReason,
        readinessOutcomes: [GraphSearchIndexReadinessOutcome]
    ) async throws -> CandidateLoadResult {
        try Task.checkCancellation()
        let candidates = try await dependencies.legacyProvider.candidates(
            container: container,
            graphID: graphID,
            foldedQuery: foldedQuery
        )
        try Task.checkCancellation()
        return CandidateLoadResult(
            candidates: candidates,
            indexDocumentCount: 0,
            source: .legacyFallback,
            fallbackReason: fallbackReason,
            readinessOutcomes: readinessOutcomes,
            graphCount: graphCount
        )
    }
}
