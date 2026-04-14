//
//  EntitiesHomeLoader+Cache.swift
//  BrainMesh
//
//  Counts caching (TTL, keys, invalidation helpers)
//

import Foundation

extension EntitiesHomeLoader {

    enum EntitiesHomeDerivedCountKind: String, Sendable {
        case attributes
        case links
    }

    struct GraphScopeKey: Hashable, Sendable {
        let graphID: UUID?
    }

    struct CountsCacheEntry: Sendable {
        let fetchedAt: Date
        let countsByEntityID: [UUID: Int]
    }

    func cachedCounts(
        for kind: EntitiesHomeDerivedCountKind,
        graphID: UUID?,
        now: Date
    ) -> [UUID: Int]? {
        guard let entry = cachedCountEntry(for: kind, graphID: graphID) else {
            return nil
        }
        guard isFresh(entry, now: now) else {
            return nil
        }
        return entry.countsByEntityID
    }

    func storeCounts(
        _ counts: [UUID: Int],
        for kind: EntitiesHomeDerivedCountKind,
        graphID: UUID?,
        now: Date
    ) {
        let entry = CountsCacheEntry(fetchedAt: now, countsByEntityID: counts)
        let key = GraphScopeKey(graphID: graphID)

        switch kind {
        case .attributes:
            countsCache[key] = entry
        case .links:
            linkCountsCache[key] = entry
        }
    }

    func cachedCountEntry(
        for kind: EntitiesHomeDerivedCountKind,
        graphID: UUID?
    ) -> CountsCacheEntry? {
        let key = GraphScopeKey(graphID: graphID)
        switch kind {
        case .attributes:
            return countsCache[key]
        case .links:
            return linkCountsCache[key]
        }
    }

    func isFresh(_ entry: CountsCacheEntry, now: Date) -> Bool {
        now.timeIntervalSince(entry.fetchedAt) <= countsCacheTTLSeconds
    }
}
