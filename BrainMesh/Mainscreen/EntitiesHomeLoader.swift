//
//  EntitiesHomeLoader.swift
//  BrainMesh
//
//  P0.1: Load Entities Home data off the UI thread.
//  Goal: Avoid blocking the main thread with SwiftData fetches when typing/searching
//  or switching graphs in the Home tab.
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
    let iconSymbolName: String?
    let attributeCount: Int
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

    // MARK: - Attribute count cache (avoid re-fetching all attributes while typing)

    private struct GraphScopeKey: Hashable, Sendable {
        let graphID: UUID?
    }

    private struct CountsCacheEntry: Sendable {
        let fetchedAt: Date
        let countsByEntityID: [UUID: Int]
    }

    private var countsCache: [GraphScopeKey: CountsCacheEntry] = [:]

    /// Small TTL so counts don't stay stale for long, but typing/search doesn't repeatedly load all attributes.
    private let countsCacheTTLSeconds: TimeInterval = 8

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func invalidateCache(for graphID: UUID?) {
        countsCache.removeValue(forKey: GraphScopeKey(graphID: graphID))
    }

    func loadSnapshot(activeGraphID: UUID?, foldedSearch: String) async throws -> EntitiesHomeSnapshot {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.EntitiesHomeLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "EntitiesHomeLoader not configured"]
            )
        }

        let gid = activeGraphID
        let term = foldedSearch

        return try await Task.detached(priority: .utility) { [configuredContainer, gid, term] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let entities = try EntitiesHomeLoader.fetchEntities(
                context: context,
                graphID: gid,
                foldedSearch: term
            )

            let entityIDs = Set(entities.map { $0.id })

            let now = Date()
            let shouldUseCache = !term.isEmpty
            let cachedCounts: [UUID: Int]? = shouldUseCache
                ? await EntitiesHomeLoader.shared.cachedCounts(for: gid, now: now)
                : nil

            let counts: [UUID: Int]
            if let cachedCounts {
                counts = cachedCounts
            } else {
                counts = try EntitiesHomeLoader.computeAttributeCounts(
                    context: context,
                    graphID: gid,
                    relevantEntityIDs: entityIDs
                )
                await EntitiesHomeLoader.shared.storeCounts(counts, for: gid, now: now)
            }

            let rows: [EntitiesHomeRow] = entities.map { e in
                EntitiesHomeRow(
                    id: e.id,
                    name: e.name,
                    iconSymbolName: e.iconSymbolName,
                    attributeCount: counts[e.id] ?? 0
                )
            }

            return EntitiesHomeSnapshot(rows: rows)
        }.value
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

    private static func fetchEntities(
        context: ModelContext,
        graphID: UUID?,
        foldedSearch: String
    ) throws -> [MetaEntity] {
        let gid = graphID

        // Empty search: show *all* entities for the active graph (plus legacy nil-scope).
        if foldedSearch.isEmpty {
            let fd = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { e in
                    gid == nil || e.graphID == gid || e.graphID == nil
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )

            return try context.fetch(fd)
        }

        let term = foldedSearch
        var unique: [UUID: MetaEntity] = [:]

        // 1) Entity name match
        let fdEntities = FetchDescriptor<MetaEntity>(
            predicate: #Predicate<MetaEntity> { e in
                (gid == nil || e.graphID == gid || e.graphID == nil) &&
                e.nameFolded.contains(term)
            },
            sortBy: [SortDescriptor(\MetaEntity.name)]
        )
        for e in try context.fetch(fdEntities) {
            unique[e.id] = e
        }

        // 2) Attribute displayName match (entity · attribute)
        let fdAttrs = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { a in
                (gid == nil || a.graphID == gid || a.graphID == nil) &&
                a.searchLabelFolded.contains(term)
            },
            sortBy: [SortDescriptor(\MetaAttribute.name)]
        )
        let attrs = try context.fetch(fdAttrs)

        // Note: `#Predicate` doesn't reliably support `ids.contains(e.id)` for UUID arrays.
        // We therefore resolve owners directly from the matching attributes.
        for a in attrs {
            guard let owner = a.owner else { continue }
            if gid == nil || owner.graphID == gid || owner.graphID == nil {
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
        graphID: UUID?,
        relevantEntityIDs: Set<UUID>
    ) throws -> [UUID: Int] {
        if relevantEntityIDs.isEmpty { return [:] }

        let gid = graphID
        let fd = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate<MetaAttribute> { a in
                gid == nil || a.graphID == gid || a.graphID == nil
            }
        )

        let attrs = try context.fetch(fd)
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(min(relevantEntityIDs.count, 512))

        for a in attrs {
            guard let owner = a.owner else { continue }
            let ownerID = owner.id
            guard relevantEntityIDs.contains(ownerID) else { continue }
            counts[ownerID, default: 0] += 1
        }

        return counts
    }
}
