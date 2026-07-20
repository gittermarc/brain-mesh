//
//  EntitiesHomeLoader.swift
//  BrainMesh
//
//  P0.1: Load Entities Home data off the UI thread.
//  Goal: Avoid blocking the main thread with SwiftData fetches when typing/searching
//  or switching graphs in the Home tab
//

import Foundation
import SwiftData
import os

actor EntitiesHomeLoader {

    static let shared = EntitiesHomeLoader()

    // NOTE: Some members are `internal` so they remain accessible from the split extension files.
    // This is intentional for a mechanical refactor (move-only, no behavioral change).
    var container: AnyModelContainer? = nil
    let log = Logger(subsystem: "BrainMesh", category: "EntitiesHomeLoader")

    // MARK: - Counts cache (avoid re-fetching all attributes/links while typing or toggling views)

    var countsCache: [GraphScopeKey: CountsCacheEntry] = [:]
    var linkCountsCache: [GraphScopeKey: CountsCacheEntry] = [:]

    /// Small TTL so counts don't stay stale for long, but typing/search doesn't repeatedly load everything.
    /// Cache is graph-wide to keep counts correct for any search subset (no partial-cache zeros).
    let countsCacheTTLSeconds: TimeInterval = 8

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func invalidateCache(for graphID: UUID?) {
        let key = GraphScopeKey(graphID: graphID)
        countsCache.removeValue(forKey: key)
        linkCountsCache.removeValue(forKey: key)
    }

    func invalidateCaches(forGraphID graphID: UUID) {
        invalidateCache(for: graphID)
    }

    func hasCachedCountsForTesting(
        kind: EntitiesHomeDerivedCountKind,
        graphID: UUID
    ) -> Bool {
        cachedCountEntry(for: kind, graphID: graphID) != nil
    }

    func loadSnapshot(
        activeGraphID: UUID?,
        foldedSearch: String,
        includeAttributeCounts: Bool,
        includeLinkCounts: Bool,
        includeNotesPreview: Bool
    ) async throws -> EntitiesHomeSnapshot {
        try await AppLoadersConfigurator.waitUntilReadyIfNeeded(
            serviceContainerID: self.container?.identity
        )
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.EntitiesHomeLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "EntitiesHomeLoader not configured"]
            )
        }

        try Task.checkCancellation()

        let context = ModelContext(configuredContainer.container)
        context.autosaveEnabled = false

        let gid = activeGraphID
        let term = foldedSearch
        let includeNotes = includeNotesPreview

        try Task.checkCancellation()

        let entities = try EntitiesHomeLoader.fetchEntities(
            context: context,
            graphID: gid,
            foldedSearch: term
        )

        try Task.checkCancellation()

        let countRequirements = EntitiesHomeCountRequirements(
            includeAttributeCounts: includeAttributeCounts,
            includeLinkCounts: includeLinkCounts
        )
        let derivedCounts = try resolveDerivedCounts(
            context: context,
            graphID: gid,
            requirements: countRequirements,
            now: Date()
        )

        var rows: [EntitiesHomeRow] = []
        rows.reserveCapacity(entities.count)

        for (idx, match) in entities.enumerated() {
            if idx % 128 == 0 {
                try Task.checkCancellation()
            }

            let entity = match.entity
            let preview: String? = includeNotes ? EntitiesHomeLoader.makeNotesPreview(entity.notes) : nil
            let hasData = (entity.imageData?.isEmpty == false)

            rows.append(
                EntitiesHomeRow(
                    id: entity.id,
                    name: entity.name,
                    createdAt: entity.createdAt,
                    iconSymbolName: entity.iconSymbolName,
                    attributeCount: derivedCounts.attributeCount(
                        for: entity.id,
                        includeAttributeCounts: countRequirements.includeAttributeCounts
                    ),
                    linkCount: derivedCounts.linkCount(
                        for: entity.id,
                        includeLinkCounts: countRequirements.includeLinkCounts
                    ),
                    notesPreview: preview,
                    isNotesOnlyHit: match.isNotesOnlyHit,
                    imagePath: entity.imagePath,
                    hasImageData: hasData
                )
            )
        }

        return EntitiesHomeSnapshot(rows: rows)
    }
}
