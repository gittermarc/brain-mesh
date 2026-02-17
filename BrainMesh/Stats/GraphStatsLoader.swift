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

        return try await Task.detached(priority: .utility) { [configuredContainer, graphIDs, pickedGraphID, normalizedDays] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            let service = GraphStatsService(context: context)

            let total = try service.totalCounts()

            var per: [UUID?: GraphCounts] = [:]
            per[nil] = try service.counts(for: nil)

            var media: GraphMediaSnapshot? = nil
            var structure: GraphStructureSnapshot? = nil
            var trends: GraphTrendsSnapshot? = nil

            for gid in graphIDs {
                try Task.checkCancellation()

                per[gid] = try service.counts(for: gid)

                if gid == pickedGraphID {
                    media = try service.mediaSnapshot(for: gid)
                    structure = try service.structureSnapshot(for: gid)
                    trends = try service.trendsSnapshot(for: gid, days: normalizedDays)
                }

                await Task.yield()
            }

            // If there are no graphs yet, compute details for legacy (graphID == nil).
            // This prevents the UI sections from showing an endless "loading" placeholder.
            if pickedGraphID == nil {
                media = try service.mediaSnapshot(for: nil)
                structure = try service.structureSnapshot(for: nil)
                trends = try service.trendsSnapshot(for: nil, days: normalizedDays)
            }

            // Safety: if the picked graph exists but details were not set in the loop,
            // compute them once (e.g. if graphIDs was modified during the run).
            if pickedGraphID != nil && (media == nil || structure == nil || trends == nil) {
                if let gid = pickedGraphID {
                    media = try (media ?? service.mediaSnapshot(for: gid))
                    structure = try (structure ?? service.structureSnapshot(for: gid))
                    trends = try (trends ?? service.trendsSnapshot(for: gid, days: normalizedDays))
                }
            }

            return GraphStatsSnapshot(
                total: total,
                perGraph: per,
                dashboardGraphID: pickedGraphID,
                activeMedia: media,
                activeStructure: structure,
                activeTrends: trends
            )
        }.value
    }
}
