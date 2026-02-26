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

/// Value-only row snapshot for EntitiesHome.
///
/// Important: Do NOT pass SwiftData `@Model` instances across concurrency boundaries.
/// The UI navigates by `id` and resolves the model from its main `ModelContext`.
struct EntitiesHomeRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
    let iconSymbolName: String?

    let attributeCount: Int
    let linkCount: Int?

    let notesPreview: String?

    let imagePath: String?
    let hasImageData: Bool
}

/// Snapshot DTO returned to the UI.
/// This is intentionally a value-only container so the UI can commit state in one go.
struct EntitiesHomeSnapshot: @unchecked Sendable {
    let rows: [EntitiesHomeRow]
}

actor EntitiesHomeLoader {

    static let shared = EntitiesHomeLoader()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "EntitiesHomeLoader")

    // MARK: - Counts cache (avoid re-fetching all attributes/links while typing or toggling views)

    private struct GraphScopeKey: Hashable, Sendable {
        let graphID: UUID?
    }

    private struct CountsCacheEntry: Sendable {
        let fetchedAt: Date
        let countsByEntityID: [UUID: Int]
    }

    private struct LinkCountsCacheEntry: Sendable {
        let fetchedAt: Date
        let countsByEntityID: [UUID: Int]
    }

    private var countsCache: [GraphScopeKey: CountsCacheEntry] = [:]
    private var linkCountsCache: [GraphScopeKey: LinkCountsCacheEntry] = [:]

    /// Small TTL so counts don't stay stale for long, but typing/search doesn't repeatedly load everything.
    /// Cache is graph-wide to keep counts correct for any search subset (no partial-cache zeros).
    private let countsCacheTTLSeconds: TimeInterval = 8

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

        for (idx, e) in entities.enumerated() {
            if idx % 128 == 0 {
                try Task.checkCancellation()
            }

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
                    imagePath: e.imagePath,
                    hasImageData: hasData
                )
            )
        }

        return EntitiesHomeSnapshot(rows: rows)
    }

    private func cachedCounts(for graphID: UUID?, now: Date) -> [UUID: Int]? {
        let key = GraphScopeKey(graphID: graphID)
        guard let entry = countsCache[key] else { return nil }
        if now.timeIntervalSince(entry.fetchedAt) > countsCacheTTLSeconds {
            return nil
        }
        return entry.countsByEntityID
    }

    private func storeCounts(_ counts: [UUID: Int], for graphID: UUID?, now: Date) {
        let key = GraphScopeKey(graphID: graphID)
        countsCache[key] = CountsCacheEntry(fetchedAt: now, countsByEntityID: counts)
    }

    private func cachedLinkCounts(for graphID: UUID?, now: Date) -> [UUID: Int]? {
        let key = GraphScopeKey(graphID: graphID)
        guard let entry = linkCountsCache[key] else { return nil }
        if now.timeIntervalSince(entry.fetchedAt) > countsCacheTTLSeconds {
            return nil
        }
        return entry.countsByEntityID
    }

    private func storeLinkCounts(_ counts: [UUID: Int], for graphID: UUID?, now: Date) {
        let key = GraphScopeKey(graphID: graphID)
        linkCountsCache[key] = LinkCountsCacheEntry(fetchedAt: now, countsByEntityID: counts)
    }

    private static func fetchEntities(
        context: ModelContext,
        graphID: UUID?,
        foldedSearch: String
    ) throws -> [MetaEntity] {
        let gid = graphID

        // Empty search: show *all* entities for the active graph.
        if foldedSearch.isEmpty {
            if let gid {
                let fd = FetchDescriptor<MetaEntity>(
                    predicate: #Predicate<MetaEntity> { e in
                        e.graphID == gid
                    },
                    sortBy: [SortDescriptor(\MetaEntity.name)]
                )
                return try context.fetch(fd)
            } else {
                let fd = FetchDescriptor<MetaEntity>(sortBy: [SortDescriptor(\MetaEntity.name)])
                return try context.fetch(fd)
            }
        }

        let term = foldedSearch
        var unique: [UUID: MetaEntity] = [:]

        try Task.checkCancellation()

        // 1) Entity name match
        let fdEntities: FetchDescriptor<MetaEntity>
        if let gid {
            fdEntities = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { e in
                    e.graphID == gid && e.nameFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            fdEntities = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { e in
                    e.nameFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        }
        for e in try context.fetch(fdEntities) {
            unique[e.id] = e
        }

        // 2) Attribute displayName match (entity · attribute)
        let fdAttrs: FetchDescriptor<MetaAttribute>
        if let gid {
            fdAttrs = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { a in
                    a.graphID == gid && a.searchLabelFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        } else {
            fdAttrs = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { a in
                    a.searchLabelFolded.contains(term)
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        }
        let attrs = try context.fetch(fdAttrs)

        // Note: `#Predicate` doesn't reliably support `ids.contains(e.id)` for UUID arrays.
        // We therefore resolve owners directly from the matching attributes.
        for (idx, a) in attrs.enumerated() {
            if idx % 256 == 0 {
                try Task.checkCancellation()
            }
            guard let owner = a.owner else { continue }
            if let gid {
                if owner.graphID == gid { unique[owner.id] = owner }
            } else {
                unique[owner.id] = owner
            }
        }

        // Stable sort
        return unique.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func computeAttributeCounts(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [UUID: Int] {
        try Task.checkCancellation()

        let gid = graphID
        let attrs: [MetaAttribute]
        if let gid {
            let fd = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { a in
                    a.graphID == gid
                }
            )
            attrs = try context.fetch(fd)
        } else {
            let fd = FetchDescriptor<MetaAttribute>()
            attrs = try context.fetch(fd)
        }

        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(min(attrs.count / 3, 2048))

        for (idx, a) in attrs.enumerated() {
            if idx % 512 == 0 {
                try Task.checkCancellation()
            }
            guard let owner = a.owner else { continue }
            counts[owner.id, default: 0] += 1
        }

        return counts
    }

    private static func computeLinkCounts(
        context: ModelContext,
        graphID: UUID?
    ) throws -> [UUID: Int] {
        try Task.checkCancellation()

        let gid = graphID
        let links: [MetaLink]
        if let gid {
            let fd = FetchDescriptor<MetaLink>(
                predicate: #Predicate<MetaLink> { l in
                    l.graphID == gid
                }
            )
            links = try context.fetch(fd)
        } else {
            let fd = FetchDescriptor<MetaLink>()
            links = try context.fetch(fd)
        }

        let entityKindRaw = NodeKind.entity.rawValue
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(min(links.count / 2, 4096))

        for (idx, l) in links.enumerated() {
            if idx % 512 == 0 {
                try Task.checkCancellation()
            }
            if l.sourceKindRaw == entityKindRaw {
                counts[l.sourceID, default: 0] += 1
            }
            if l.targetKindRaw == entityKindRaw {
                counts[l.targetID, default: 0] += 1
            }
        }

        return counts
    }

    private static func makeNotesPreview(_ notes: String) -> String? {
        MarkdownCommands.notesPreviewLine(notes)
    }
}
