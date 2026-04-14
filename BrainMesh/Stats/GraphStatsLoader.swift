//
//  GraphStatsLoader.swift
//  BrainMesh
//
//  P0.1: Load Stats data off the UI thread.
//  Goal: Avoid blocking the main thread with SwiftData fetches when opening/switching graphs.
//

import Foundation
import SwiftData
import os

/// Snapshot DTO returned to the UI.
///
/// NOTE: This is intentionally a value-only container so the UI can commit state in one go.
struct GraphStatsSnapshot: @unchecked Sendable {
    let total: GraphCounts
    let perGraph: [UUID?: GraphCounts]

    /// Graph chosen for the dashboard/details (usually active graph, otherwise first graph).
    /// If no graphs exist, this is `nil`.
    let dashboardGraphID: UUID?

    /// Detailed breakdowns for the dashboard graph.
    /// If no graphs exist, these are computed for legacy (graphID == nil) to avoid a perpetual loading state.
    let activeMedia: GraphMediaSnapshot?
    let activeStructure: GraphStructureSnapshot?
    let activeTrends: GraphTrendsSnapshot?
}

/// Dashboard snapshot DTO returned to the UI.
///
/// This intentionally omits per-graph counts for all graphs. The UI loads those lazily when needed.
struct GraphStatsDashboardSnapshot: @unchecked Sendable {
    let total: GraphCounts

    /// Partial per-graph map. Contains legacy (nil) and the current dashboard graph (if any).
    let perGraph: [UUID?: GraphCounts]

    /// Graph chosen for the dashboard/details (usually active graph, otherwise first graph).
    /// If no graphs exist, this is `nil`.
    let dashboardGraphID: UUID?

    /// Detailed breakdowns for the dashboard graph.
    /// If no graphs exist, these are computed for legacy (graphID == nil) to avoid a perpetual loading state.
    let activeMedia: GraphMediaSnapshot?
    let activeStructure: GraphStructureSnapshot?
    let activeTrends: GraphTrendsSnapshot?
}

private nonisolated struct GraphStatsDashboardCacheKey: Hashable, Sendable {
    let graphIDs: [UUID]
    let activeGraphID: UUID?
    let days: Int
}

private struct GraphStatsDashboardCacheEntry {
    let totalRevision: GraphStatsScopeRevision
    let legacyRevision: GraphStatsScopeRevision
    let activeRevision: GraphStatsScopeRevision
    let snapshot: GraphStatsDashboardSnapshot
}

private struct GraphStatsCountsCacheEntry {
    let revision: GraphStatsScopeRevision
    let counts: GraphCounts
}

private struct GraphStatsDashboardCacheState: Sendable {
    let totalRevision: GraphStatsScopeRevision
    let legacyRevision: GraphStatsScopeRevision
    let activeRevision: GraphStatsScopeRevision
}

actor GraphStatsLoader {

    static let shared = GraphStatsLoader()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "GraphStatsLoader")

    private var dashboardCache: [GraphStatsDashboardCacheKey: GraphStatsDashboardCacheEntry] = [:]
    private var countsCache: [GraphStatsCountScope: GraphStatsCountsCacheEntry] = [:]

    private var dashboardCacheHits: Int = 0
    private var countsCacheHits: Int = 0

    func configure(container: AnyModelContainer) {
        self.container = container
        invalidateAllCaches()
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func invalidateAllCaches() {
        dashboardCache.removeAll()
        countsCache.removeAll()
    }

    private func invalidateCountsCache(for graphIDs: [UUID]) {
        let scopes = graphIDs.map { GraphStatsCountScope.graph($0) }
        invalidateCountsCache(for: scopes)
    }

    private func invalidateCountsCache(for scopes: [GraphStatsCountScope]) {
        for scope in scopes {
            countsCache.removeValue(forKey: scope)
        }
    }

    private func cachedDashboardSnapshot(
        for cacheKey: GraphStatsDashboardCacheKey,
        state: GraphStatsDashboardCacheState
    ) -> GraphStatsDashboardSnapshot? {
        guard let cached = dashboardCache[cacheKey],
              cached.totalRevision == state.totalRevision,
              cached.legacyRevision == state.legacyRevision,
              cached.activeRevision == state.activeRevision else {
            return nil
        }

        dashboardCacheHits += 1
        return cached.snapshot
    }

    private func storeDashboardSnapshot(
        _ snapshot: GraphStatsDashboardSnapshot,
        for cacheKey: GraphStatsDashboardCacheKey,
        state: GraphStatsDashboardCacheState
    ) {
        dashboardCache[cacheKey] = GraphStatsDashboardCacheEntry(
            totalRevision: state.totalRevision,
            legacyRevision: state.legacyRevision,
            activeRevision: state.activeRevision,
            snapshot: snapshot
        )
    }

    private func cachedCounts(
        for scope: GraphStatsCountScope,
        revision: GraphStatsScopeRevision
    ) -> GraphCounts? {
        guard let cached = countsCache[scope], cached.revision == revision else {
            return nil
        }

        countsCacheHits += 1
        return cached.counts
    }

    private func storeCounts(
        _ counts: GraphCounts,
        for scope: GraphStatsCountScope,
        revision: GraphStatsScopeRevision
    ) {
        countsCache[scope] = GraphStatsCountsCacheEntry(
            revision: revision,
            counts: counts
        )
    }

    func loadSnapshot(
        graphIDs: [UUID],
        activeGraphID: UUID?,
        days: Int,
        forceReload: Bool = false
    ) async throws -> GraphStatsSnapshot {
        let dashboard = try await loadDashboardSnapshot(
            graphIDs: graphIDs,
            activeGraphID: activeGraphID,
            days: days,
            forceReload: forceReload
        )

        let perGraphCounts = try await loadPerGraphCounts(
            graphIDs: graphIDs,
            forceReload: forceReload
        )

        var merged = dashboard.perGraph
        for (k, v) in perGraphCounts {
            merged[k] = v
        }

        return GraphStatsSnapshot(
            total: dashboard.total,
            perGraph: merged,
            dashboardGraphID: dashboard.dashboardGraphID,
            activeMedia: dashboard.activeMedia,
            activeStructure: dashboard.activeStructure,
            activeTrends: dashboard.activeTrends
        )
    }

    /// Loads only what's needed for the dashboard (total + legacy + dashboard graph + details).
    ///
    /// This is meant to be fast even when the user has many graphs.
    func loadDashboardSnapshot(
        graphIDs: [UUID],
        activeGraphID: UUID?,
        days: Int,
        forceReload: Bool = false
    ) async throws -> GraphStatsDashboardSnapshot {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.GraphStatsLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "GraphStatsLoader not configured"]
            )
        }

        if forceReload {
            invalidateAllCaches()
        }

        let pickedGraphID = graphIDs.first(where: { $0 == activeGraphID }) ?? graphIDs.first
        let normalizedDays = max(1, days)
        let cacheKey = GraphStatsDashboardCacheKey(
            graphIDs: graphIDs,
            activeGraphID: activeGraphID,
            days: normalizedDays
        )

        let state = try await Task.detached(priority: .utility) { [configuredContainer, pickedGraphID] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let service = GraphStatsService(context: context)
            let totalRevision = try service.totalRevision()
            let legacyRevision = try service.revision(for: nil)
            let activeRevision = try service.revision(for: pickedGraphID)

            return GraphStatsDashboardCacheState(
                totalRevision: totalRevision,
                legacyRevision: legacyRevision,
                activeRevision: activeRevision
            )
        }.value

        if let cached = cachedDashboardSnapshot(for: cacheKey, state: state) {
            return cached
        }

        let snapshot = try await Task.detached(priority: .utility) { [configuredContainer, pickedGraphID, normalizedDays, state] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let service = GraphStatsService(context: context)

            var per: [UUID?: GraphCounts] = [:]
            per[nil] = state.legacyRevision.counts

            if let gid = pickedGraphID {
                per[gid] = state.activeRevision.counts
            }

            // Details for dashboard graph; if there are no graphs yet, compute for legacy (nil).
            let media = try service.mediaSnapshot(for: pickedGraphID)
            let structure = try service.structureSnapshot(for: pickedGraphID)
            let trends = try service.trendsSnapshot(for: pickedGraphID, days: normalizedDays)

            return GraphStatsDashboardSnapshot(
                total: state.totalRevision.counts,
                perGraph: per,
                dashboardGraphID: pickedGraphID,
                activeMedia: media,
                activeStructure: structure,
                activeTrends: trends
            )
        }.value

        storeDashboardSnapshot(snapshot, for: cacheKey, state: state)

        return snapshot
    }

    /// Loads per-graph counts for the given graph IDs.
    ///
    /// Intended to be triggered lazily when the user expands "Pro Graph".
    func loadPerGraphCounts(
        graphIDs: [UUID],
        forceReload: Bool = false
    ) async throws -> [UUID?: GraphCounts] {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.GraphStatsLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "GraphStatsLoader not configured"]
            )
        }

        if forceReload {
            invalidateCountsCache(for: graphIDs)
        }

        let revisions = try await Task.detached(priority: .utility) { [configuredContainer, graphIDs] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let service = GraphStatsService(context: context)
            var revisions: [UUID: GraphStatsScopeRevision] = [:]

            for gid in graphIDs {
                try Task.checkCancellation()
                revisions[gid] = try service.revision(for: gid)
                await Task.yield()
            }

            return revisions
        }.value

        var countsByGraph: [UUID?: GraphCounts] = [:]

        for gid in graphIDs {
            let scope = GraphStatsCountScope.graph(gid)
            guard let revision = revisions[gid] else { continue }

            if let cached = cachedCounts(for: scope, revision: revision) {
                countsByGraph[gid] = cached
                continue
            }

            storeCounts(revision.counts, for: scope, revision: revision)
            countsByGraph[gid] = revision.counts
        }

        return countsByGraph
    }

    func dashboardCacheEntryCountForTesting() -> Int {
        dashboardCache.count
    }

    func countsCacheEntryCountForTesting() -> Int {
        countsCache.count
    }

    func dashboardCacheHitsForTesting() -> Int {
        dashboardCacheHits
    }

    func countsCacheHitsForTesting() -> Int {
        countsCacheHits
    }
}
