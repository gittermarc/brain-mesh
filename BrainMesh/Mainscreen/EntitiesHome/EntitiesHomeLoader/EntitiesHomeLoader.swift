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
    var linkCountsCache: [GraphScopeKey: LinkCountsCacheEntry] = [:]

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

    func loadSnapshot(
        activeGraphID: UUID?,
        foldedSearch: String,
        includeAttributeCounts: Bool,
        includeLinkCounts: Bool,
        includeNotesPreview: Bool
    ) async throws -> EntitiesHomeSnapshot {
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
        let includeAttrs = includeAttributeCounts
        let includeLinks = includeLinkCounts
        let includeNotes = includeNotesPreview

        try Task.checkCancellation()

        let entities = try EntitiesHomeLoader.fetchEntities(
            context: context,
            graphID: gid,
            foldedSearch: term
        )

        try Task.checkCancellation()

        let now = Date()
        let attrCounts: [UUID: Int]
        if includeAttrs {
            let cachedAttrCounts: [UUID: Int]? = cachedCounts(for: gid, now: now)

            if let cachedAttrCounts {
                attrCounts = cachedAttrCounts
            } else {
                let computed = try EntitiesHomeLoader.computeAttributeCounts(
                    context: context,
                    graphID: gid
                )
                try Task.checkCancellation()
                storeCounts(computed, for: gid, now: now)
                attrCounts = computed
            }
        } else {
            attrCounts = [:]
        }

        let linkCountsByEntityID: [UUID: Int]?
        if includeLinks {
            let cachedLinkCounts: [UUID: Int]? = cachedLinkCounts(for: gid, now: now)

            if let cachedLinkCounts {
                linkCountsByEntityID = cachedLinkCounts
            } else {
                let computed = try EntitiesHomeLoader.computeLinkCounts(
                    context: context,
                    graphID: gid
                )
                try Task.checkCancellation()
                storeLinkCounts(computed, for: gid, now: now)
                linkCountsByEntityID = computed
            }
        } else {
            linkCountsByEntityID = nil
        }

        var rows: [EntitiesHomeRow] = []
        rows.reserveCapacity(entities.count)

        for (idx, match) in entities.enumerated() {
            if idx % 128 == 0 {
                try Task.checkCancellation()
            }

            let e = match.entity

            let preview: String? = includeNotes ? EntitiesHomeLoader.makeNotesPreview(e.notes) : nil
            let hasData = (e.imageData?.isEmpty == false)

            rows.append(
                EntitiesHomeRow(
                    id: e.id,
                    name: e.name,
                    createdAt: e.createdAt,
                    iconSymbolName: e.iconSymbolName,
                    attributeCount: includeAttrs ? (attrCounts[e.id] ?? 0) : 0,
                    linkCount: includeLinks ? (linkCountsByEntityID?[e.id] ?? 0) : nil,
                    notesPreview: preview,
                    isNotesOnlyHit: match.isNotesOnlyHit,
                    imagePath: e.imagePath,
                    hasImageData: hasData
                )
            )
        }

        return EntitiesHomeSnapshot(rows: rows)
    }
}
