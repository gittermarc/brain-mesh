//
//  BrainMeshSearchDependencies.swift
//  BrainMesh
//
//  Search-source boundaries used by the global search orchestrator and its tests.
//

import Foundation
import SwiftData

nonisolated protocol BrainMeshSearchIndexReadinessProviding: Sendable {
    func ensureReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult

    func invalidate(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async
}

extension GraphSearchIndexReconciler: BrainMeshSearchIndexReadinessProviding {}

nonisolated protocol BrainMeshLegacySearchCandidateProviding: Sendable {
    func candidates(
        container: AnyModelContainer,
        graphID: UUID?,
        foldedQuery: String
    ) async throws -> [BrainMeshSearchCandidate]
}

nonisolated struct LiveBrainMeshLegacySearchCandidateProvider: BrainMeshLegacySearchCandidateProviding {
    func candidates(
        container: AnyModelContainer,
        graphID: UUID?,
        foldedQuery: String
    ) async throws -> [BrainMeshSearchCandidate] {
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) {
            let context = ModelContext(container.container)
            context.autosaveEnabled = false
            let request = BrainMeshSearchCandidateRequest(
                modelContext: context,
                graphID: graphID,
                foldedQuery: foldedQuery
            )
            try request.checkCancellation()

            var candidates: [BrainMeshSearchCandidate] = []
            for provider in BrainMeshSearchCandidateProviders.ordered {
                try request.checkCancellation()
                candidates.append(contentsOf: try provider.candidates(for: request))
                try request.checkCancellation()
            }
            return candidates
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

nonisolated struct BrainMeshSearchGraphScopeResolution: Equatable, Sendable {
    let graphIDs: [UUID]
    let canUseIndex: Bool
    let fallbackReason: BrainMeshSearchFallbackReason?
}

nonisolated protocol BrainMeshSearchGraphScopeResolving: Sendable {
    func resolveGlobalScope(
        container: AnyModelContainer
    ) async throws -> BrainMeshSearchGraphScopeResolution
}

nonisolated struct LiveBrainMeshSearchGraphScopeResolver: BrainMeshSearchGraphScopeResolving {
    func resolveGlobalScope(
        container: AnyModelContainer
    ) async throws -> BrainMeshSearchGraphScopeResolution {
        try Task.checkCancellation()
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let context = ModelContext(container.container)
            context.autosaveEnabled = false

            let graphs = try context.fetch(FetchDescriptor<MetaGraph>())
            try Task.checkCancellation()
            let graphIDs = GraphSearchIndexStore.normalizedGraphIDs(graphs.map(\.id))
            guard graphIDs.count <= GraphSearchIndexStore.maximumScopedGraphCount else {
                return BrainMeshSearchGraphScopeResolution(
                    graphIDs: graphIDs,
                    canUseIndex: false,
                    fallbackReason: .globalScopeTooLarge
                )
            }

            let hasUnscopedSources = try Self.hasUnscopedSearchSources(context: context)
            try Task.checkCancellation()
            return BrainMeshSearchGraphScopeResolution(
                graphIDs: graphIDs,
                canUseIndex: hasUnscopedSources == false,
                fallbackReason: hasUnscopedSources ? .unscopedLegacySources : nil
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func hasUnscopedSearchSources(
        context: ModelContext
    ) throws -> Bool {
        let entityCount = try context.fetchCount(
            FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { entity in entity.graphID == nil }
            )
        )
        guard entityCount == 0 else { return true }

        let attributeCount = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in attribute.graphID == nil }
            )
        )
        guard attributeCount == 0 else { return true }

        let linkCount = try context.fetchCount(
            FetchDescriptor<MetaLink>(
                predicate: #Predicate<MetaLink> { link in link.graphID == nil }
            )
        )
        guard linkCount == 0 else { return true }

        let definitionCount = try context.fetchCount(
            FetchDescriptor<MetaDetailFieldDefinition>(
                predicate: #Predicate<MetaDetailFieldDefinition> { field in field.graphID == nil }
            )
        )
        guard definitionCount == 0 else { return true }

        let valueCount = try context.fetchCount(
            FetchDescriptor<MetaDetailFieldValue>(
                predicate: #Predicate<MetaDetailFieldValue> { value in value.graphID == nil }
            )
        )
        guard valueCount == 0 else { return true }

        let attachmentCount = try context.fetchCount(
            FetchDescriptor<MetaAttachment>(
                predicate: #Predicate<MetaAttachment> { attachment in attachment.graphID == nil }
            )
        )
        return attachmentCount > 0
    }
}

nonisolated enum BrainMeshSearchExecutionSource: String, Sendable {
    case index
    case legacyFallback
}

nonisolated enum BrainMeshSearchFallbackReason: String, Equatable, Sendable {
    case indexNotConfigured
    case globalScopeUnavailable
    case globalScopeTooLarge
    case unscopedLegacySources
    case readinessUnavailable
    case indexQueryFailed
}

nonisolated struct BrainMeshSearchServiceDependencies: Sendable {
    let readinessProvider: (any BrainMeshSearchIndexReadinessProviding)?
    let indexedProvider: (any BrainMeshIndexedSearchCandidateProviding)?
    let legacyProvider: any BrainMeshLegacySearchCandidateProviding
    let scopeResolver: any BrainMeshSearchGraphScopeResolving

    init(
        readinessProvider: (any BrainMeshSearchIndexReadinessProviding)?,
        indexedProvider: (any BrainMeshIndexedSearchCandidateProviding)?,
        legacyProvider: any BrainMeshLegacySearchCandidateProviding,
        scopeResolver: any BrainMeshSearchGraphScopeResolving
    ) {
        self.readinessProvider = readinessProvider
        self.indexedProvider = indexedProvider
        self.legacyProvider = legacyProvider
        self.scopeResolver = scopeResolver
    }

    static let live = BrainMeshSearchServiceDependencies(
        readinessProvider: GraphSearchIndexReconciler.shared,
        indexedProvider: IndexedSearchCandidateProvider(),
        legacyProvider: LiveBrainMeshLegacySearchCandidateProvider(),
        scopeResolver: LiveBrainMeshSearchGraphScopeResolver()
    )

    static let legacyOnly = BrainMeshSearchServiceDependencies(
        readinessProvider: nil,
        indexedProvider: nil,
        legacyProvider: LiveBrainMeshLegacySearchCandidateProvider(),
        scopeResolver: LiveBrainMeshSearchGraphScopeResolver()
    )
}
