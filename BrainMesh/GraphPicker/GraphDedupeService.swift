//
//  GraphDedupeService.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import Foundation
import SwiftData

/// Repairs a SwiftData edge case: multiple `MetaGraph` records with the same `id` (UUID)
/// can exist in the store (e.g. due to merge/sync glitches).
///
/// We treat `MetaGraph.id` as the user-visible graph identifier and keep the oldest record per UUID.
@MainActor
enum GraphDedupeService {

    struct Report: Equatable {
        let removedGraphs: Int
        let affectedGraphIDs: [UUID]
    }

    /// Removes duplicate `MetaGraph` records with identical `MetaGraph.id` values.
    /// Keeps the oldest record (by `createdAt`) and deletes the rest.
    @discardableResult
    static func removeDuplicateGraphs(
        using modelContext: ModelContext,
        committer: GraphMutationCommitter = GraphMutationCommitter()
    ) async throws -> Report {
        let descriptor = FetchDescriptor<MetaGraph>(
            sortBy: [SortDescriptor(\MetaGraph.createdAt, order: .forward)]
        )
        let all = try modelContext.fetch(descriptor)

        var seen = Set<UUID>()
        var duplicates: [MetaGraph] = []
        var affectedGraphIDs = Set<UUID>()

        for graph in all {
            if seen.insert(graph.id).inserted {
                continue
            }
            duplicates.append(graph)
            affectedGraphIDs.insert(graph.id)
        }

        guard duplicates.isEmpty == false else {
            return Report(removedGraphs: 0, affectedGraphIDs: [])
        }

        let orderedGraphIDs = affectedGraphIDs.sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
        let batches = try orderedGraphIDs.map { graphID in
            try GraphMutationBatchFactory.graphIntegrityRepair(graphID: graphID)
        }

        for duplicate in duplicates {
            modelContext.delete(duplicate)
        }

        _ = try await committer.commit(batches, in: modelContext)
        return Report(
            removedGraphs: duplicates.count,
            affectedGraphIDs: orderedGraphIDs
        )
    }
}
