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

actor GraphStatsLoader {

    static let shared = GraphStatsLoader()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "GraphStatsLoader")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func loadSnapshot(
        graphIDs: [UUID],
        activeGraphID: UUID?,
        days: Int
    ) async throws -> GraphStatsSnapshot {
        let dashboard = try await loadDashboardSnapshot(
            graphIDs: graphIDs,
            activeGraphID: activeGraphID,
            days: days
        )

        let perGraphCounts = try await loadPerGraphCounts(graphIDs: graphIDs)

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
        days: Int
    ) async throws -> GraphStatsDashboardSnapshot {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.GraphStatsLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "GraphStatsLoader not configured"]
            )
        }

        let pickedGraphID = graphIDs.first(where: { $0 == activeGraphID }) ?? graphIDs.first
        let normalizedDays = max(1, days)

        return try await Task.detached(priority: .utility) { [configuredContainer, pickedGraphID, normalizedDays] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let service = GraphStatsService(context: context)

            let total = try service.totalCounts()

            var per: [UUID?: GraphCounts] = [:]
            per[nil] = try service.counts(for: nil)

            if let gid = pickedGraphID {
                per[gid] = try service.counts(for: gid)
            }

            // Details for dashboard graph; if there are no graphs yet, compute for legacy (nil).
            let media = try service.mediaSnapshot(for: pickedGraphID)
            let structure = try service.structureSnapshot(for: pickedGraphID)
            let trends = try service.trendsSnapshot(for: pickedGraphID, days: normalizedDays)

            return GraphStatsDashboardSnapshot(
                total: total,
                perGraph: per,
                dashboardGraphID: pickedGraphID,
                activeMedia: media,
                activeStructure: structure,
                activeTrends: trends
            )
        }.value
    }

    /// Loads per-graph counts for the given graph IDs.
    ///
    /// Intended to be triggered lazily when the user expands "Pro Graph".
    func loadPerGraphCounts(
        graphIDs: [UUID]
    ) async throws -> [UUID?: GraphCounts] {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.GraphStatsLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "GraphStatsLoader not configured"]
            )
        }

        return try await Task.detached(priority: .utility) { [configuredContainer, graphIDs] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let service = GraphStatsService(context: context)

            var per: [UUID?: GraphCounts] = [:]

            for gid in graphIDs {
                try Task.checkCancellation()
                per[gid] = try service.counts(for: gid)
                await Task.yield()
            }

            return per
        }.value
    }
}
