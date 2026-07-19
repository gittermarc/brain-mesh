//
//  BrainMeshSearchService.swift
//  BrainMesh
//
//  Global graph-scoped search orchestrator. The service returns value-only DTOs and never exposes SwiftData models.
//

import Foundation
import SwiftData
import os

actor BrainMeshSearchService {
    static let shared = BrainMeshSearchService()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "BrainMeshSearchService")

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
        let configuredContainer = self.container
        guard let configuredContainer else {
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

        let gid = graphID

        return try await Task.detached(
            priority: .utility
        ) { [configuredContainer, gid, query, safeLimit] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let request = BrainMeshSearchCandidateRequest(
                modelContext: context,
                graphID: gid,
                foldedQuery: query
            )
            try request.checkCancellation()

            var candidates: [BrainMeshSearchCandidate] = []
            for provider in BrainMeshSearchCandidateProviders.ordered {
                try request.checkCancellation()
                candidates.append(contentsOf: try provider.candidates(for: request))
                try request.checkCancellation()
            }

            let sorted = BrainMeshSearchRanking.sortedCandidates(candidates)
            let results = sorted.prefix(safeLimit).map(\.result)
            return BrainMeshSearchSnapshot(query: query, results: Array(results))
        }.value
    }
}
