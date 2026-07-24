//
//  EntitiesHomeHealthSummaryProvider.swift
//  BrainMesh
//
//  Revision-cached, graph-scoped Health provider for Entities Home.
//

import Foundation
import SwiftData

nonisolated struct EntitiesHomeHealthSummarySnapshot: Equatable, Sendable {
    let graphID: UUID
    let revision: GraphStatsScopeRevision
    let summary: GraphHealthSummary
}

actor EntitiesHomeHealthSummaryProvider {
    static let shared = EntitiesHomeHealthSummaryProvider()

    private struct CacheKey: Hashable, Sendable {
        let graphID: UUID
        let revision: GraphStatsScopeRevision
    }

    private struct InFlight {
        let id: UUID
        let task: Task<EntitiesHomeHealthSummarySnapshot, Error>
    }

    private var container: AnyModelContainer?
    private var cache: [CacheKey: EntitiesHomeHealthSummarySnapshot] = [:]
    private var inFlight: [UUID: InFlight] = [:]
    private var generationsByGraphID: [UUID: UInt] = [:]
    private var invalidationContinuations: [
        UUID: AsyncStream<UUID>.Continuation
    ] = [:]

    private let revisionLoader:
        @Sendable (
            AnyModelContainer,
            UUID
        ) async throws -> GraphStatsScopeRevision
    private let summaryLoader:
        @Sendable (
            AnyModelContainer,
            UUID
        ) async throws -> GraphHealthSummary

    private var cacheHitCount = 0
    private var computeCount = 0

    init(
        revisionLoader: (
            @Sendable (
                AnyModelContainer,
                UUID
            ) async throws -> GraphStatsScopeRevision
        )? = nil,
        summaryLoader: (
            @Sendable (
                AnyModelContainer,
                UUID
            ) async throws -> GraphHealthSummary
        )? = nil
    ) {
        self.revisionLoader =
            revisionLoader ?? Self.defaultRevisionLoader
        self.summaryLoader =
            summaryLoader ?? Self.defaultSummaryLoader
    }

    func configure(container: AnyModelContainer) {
        if self.container?.identity == container.identity {
            return
        }

        self.container = container
        invalidateAll()
    }

    func summary(
        for graphID: UUID,
        forceReload: Bool = false
    ) async throws -> EntitiesHomeHealthSummarySnapshot {
        try await AppLoadersConfigurator.waitUntilReadyIfNeeded(
            serviceContainerID: container?.identity
        )
        guard let configuredContainer = container else {
            throw NSError(
                domain: "BrainMesh.EntitiesHomeHealthSummaryProvider",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "EntitiesHomeHealthSummaryProvider not configured"
                ]
            )
        }

        if forceReload {
            invalidate(for: graphID)
        }

        try Task.checkCancellation()
        if let existing = inFlight[graphID] {
            let snapshot = try await existing.task.value
            try Task.checkCancellation()
            return snapshot
        }

        let requestID = UUID()
        let generation = generationsByGraphID[graphID, default: 0]
        let task = Task {
            try await self.performRequest(
                graphID: graphID,
                generation: generation,
                container: configuredContainer
            )
        }
        inFlight[graphID] = InFlight(
            id: requestID,
            task: task
        )

        do {
            let snapshot = try await task.value
            try Task.checkCancellation()
            finishInFlight(graphID: graphID, requestID: requestID)
            return snapshot
        } catch {
            removeInFlight(graphID: graphID, requestID: requestID)
            throw error
        }
    }

    func invalidate(for graphID: UUID) {
        generationsByGraphID[graphID, default: 0] &+= 1
        cache = cache.filter { $0.key.graphID != graphID }

        inFlight.removeValue(forKey: graphID)?.task.cancel()
        for continuation in invalidationContinuations.values {
            continuation.yield(graphID)
        }
    }

    func invalidateAll() {
        let tasks = inFlight.values.map(\.task)
        inFlight.removeAll()
        cache.removeAll()
        generationsByGraphID.removeAll()
        for task in tasks {
            task.cancel()
        }
    }

    func invalidations() -> AsyncStream<UUID> {
        let subscriberID = UUID()
        let pair = AsyncStream<UUID>.makeStream(
            bufferingPolicy: .unbounded
        )
        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeInvalidationSubscriber(
                    id: subscriberID
                )
            }
        }
        invalidationContinuations[subscriberID] = pair.continuation
        return pair.stream
    }

    func cacheHitCountForTesting() -> Int {
        cacheHitCount
    }

    func computeCountForTesting() -> Int {
        computeCount
    }

    func cacheEntryCountForTesting() -> Int {
        cache.count
    }

    func hasCachedSummaryForTesting(graphID: UUID) -> Bool {
        cache.keys.contains { $0.graphID == graphID }
    }

    func resetMetricsForTesting() {
        cacheHitCount = 0
        computeCount = 0
    }

    func seedCacheForTesting(
        graphID: UUID,
        revision: GraphStatsScopeRevision,
        summary: GraphHealthSummary = .empty
    ) {
        let key = CacheKey(graphID: graphID, revision: revision)
        cache[key] = EntitiesHomeHealthSummarySnapshot(
            graphID: graphID,
            revision: revision,
            summary: summary
        )
    }
}

private extension EntitiesHomeHealthSummaryProvider {
    static let defaultRevisionLoader:
        @Sendable (
            AnyModelContainer,
            UUID
        ) async throws -> GraphStatsScopeRevision = {
        container,
        graphID in
        let task = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let context = ModelContext(container.container)
            context.autosaveEnabled = false
            let service = GraphStatsService(context: context)
            let revision = try service.revision(for: graphID)
            try Task.checkCancellation()
            return revision
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static let defaultSummaryLoader:
        @Sendable (
            AnyModelContainer,
            UUID
        ) async throws -> GraphHealthSummary = {
        container,
        graphID in
        let task = Task.detached(priority: .utility) {
            let context = ModelContext(container.container)
            context.autosaveEnabled = false

            try Task.checkCancellation()
            let entities = try context.fetch(
                FetchDescriptor<MetaEntity>(
                    predicate: #Predicate<MetaEntity> { entity in
                        entity.graphID == graphID
                    }
                )
            )

            try Task.checkCancellation()
            let attributes = try context.fetch(
                FetchDescriptor<MetaAttribute>(
                    predicate: #Predicate<MetaAttribute> { attribute in
                        attribute.graphID == graphID
                    }
                )
            )

            try Task.checkCancellation()
            let links = try context.fetch(
                FetchDescriptor<MetaLink>(
                    predicate: #Predicate<MetaLink> { link in
                        link.graphID == graphID
                    }
                )
            )

            try Task.checkCancellation()
            let detailFields = try context.fetch(
                FetchDescriptor<MetaDetailFieldDefinition>(
                    predicate: #Predicate<MetaDetailFieldDefinition> { field in
                        field.graphID == graphID
                    }
                )
            )

            try Task.checkCancellation()
            let attachments = try context.fetch(
                FetchDescriptor<MetaAttachment>(
                    predicate: #Predicate<MetaAttachment> { attachment in
                        attachment.graphID == graphID
                    }
                )
            )

            try Task.checkCancellation()
            return GraphHealthSummary.make(
                entities: entities.map { entity in
                    GraphHealthEntityInput(
                        id: entity.id,
                        hasHeaderImage: entity.imageData?.isEmpty == false
                    )
                },
                attributes: attributes.map { attribute in
                    let ownerEntityID: UUID?
                    if let owner = attribute.owner,
                       owner.graphID == graphID {
                        ownerEntityID = owner.id
                    } else {
                        ownerEntityID = nil
                    }

                    return GraphHealthAttributeInput(
                        id: attribute.id,
                        ownerEntityID: ownerEntityID,
                        hasHeaderImage:
                            attribute.imageData?.isEmpty == false
                    )
                },
                links: links.map { link in
                    GraphHealthLinkInput(
                        sourceKindRaw: link.sourceKindRaw,
                        sourceID: link.sourceID,
                        targetKindRaw: link.targetKindRaw,
                        targetID: link.targetID
                    )
                },
                detailFields: detailFields.map { field in
                    GraphHealthDetailFieldInput(
                        entityID: field.entityID
                    )
                },
                attachments: attachments.map { attachment in
                    GraphHealthAttachmentInput(
                        ownerKindRaw: attachment.ownerKindRaw,
                        ownerID: attachment.ownerID,
                        byteCount: attachment.byteCount
                    )
                }
            )
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func performRequest(
        graphID: UUID,
        generation: UInt,
        container: AnyModelContainer
    ) async throws -> EntitiesHomeHealthSummarySnapshot {
        let revision = try await revisionLoader(container, graphID)
        try Task.checkCancellation()

        let key = CacheKey(graphID: graphID, revision: revision)
        if let cached = cache[key] {
            cacheHitCount += 1
            return cached
        }

        computeCount += 1
        let summary = try await summaryLoader(container, graphID)
        try Task.checkCancellation()
        let snapshot = EntitiesHomeHealthSummarySnapshot(
            graphID: graphID,
            revision: revision,
            summary: summary.replacingCounts(with: revision.counts)
        )

        guard generationsByGraphID[graphID, default: 0] == generation else {
            throw CancellationError()
        }

        cache = cache.filter {
            $0.key.graphID != graphID || $0.key == key
        }
        cache[key] = snapshot
        return snapshot
    }

    func finishInFlight(graphID: UUID, requestID: UUID) {
        guard let current = inFlight[graphID],
              current.id == requestID else {
            return
        }
        inFlight.removeValue(forKey: graphID)
    }

    func removeInFlight(graphID: UUID, requestID: UUID) {
        guard inFlight[graphID]?.id == requestID else {
            return
        }
        inFlight.removeValue(forKey: graphID)
    }

    func removeInvalidationSubscriber(id: UUID) {
        invalidationContinuations.removeValue(forKey: id)
    }
}
