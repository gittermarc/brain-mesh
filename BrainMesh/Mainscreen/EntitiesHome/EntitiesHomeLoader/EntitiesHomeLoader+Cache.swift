//
//  EntitiesHomeLoader+Cache.swift
//  BrainMesh
//
//  Counts caching (TTL, keys, invalidation helpers)
//

import Foundation

extension EntitiesHomeLoader {

    struct GraphScopeKey: Hashable, Sendable {
        let graphID: UUID?
    }

    struct CountsCacheEntry: Sendable {
        let fetchedAt: Date
        let countsByEntityID: [UUID: Int]
    }

    struct LinkCountsCacheEntry: Sendable {
        let fetchedAt: Date
        let countsByEntityID: [UUID: Int]
    }

    func cachedCounts(for graphID: UUID?, now: Date) -> [UUID: Int]? {
        let key = GraphScopeKey(graphID: graphID)
        guard let entry = countsCache[key] else { return nil }
        if now.timeIntervalSince(entry.fetchedAt) > countsCacheTTLSeconds {
            return nil
        }
        return entry.countsByEntityID
    }

    func storeCounts(_ counts: [UUID: Int], for graphID: UUID?, now: Date) {
        let key = GraphScopeKey(graphID: graphID)
        countsCache[key] = CountsCacheEntry(fetchedAt: now, countsByEntityID: counts)
    }

    func cachedLinkCounts(for graphID: UUID?, now: Date) -> [UUID: Int]? {
        let key = GraphScopeKey(graphID: graphID)
        guard let entry = linkCountsCache[key] else { return nil }
        if now.timeIntervalSince(entry.fetchedAt) > countsCacheTTLSeconds {
            return nil
        }
        return entry.countsByEntityID
    }

    func storeLinkCounts(_ counts: [UUID: Int], for graphID: UUID?, now: Date) {
        let key = GraphScopeKey(graphID: graphID)
        linkCountsCache[key] = LinkCountsCacheEntry(fetchedAt: now, countsByEntityID: counts)
    }
}
