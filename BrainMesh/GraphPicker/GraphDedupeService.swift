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

    struct Report {
        let removedGraphs: Int
    }

    /// Removes duplicate `MetaGraph` records with identical `MetaGraph.id` values.
    /// Keeps the oldest record (by `createdAt`) and deletes the rest.
    @discardableResult
    static func removeDuplicateGraphs(using modelContext: ModelContext) -> Report {
        let fd = FetchDescriptor<MetaGraph>(sortBy: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
        let all = (try? modelContext.fetch(fd)) ?? []

        var seen = Set<UUID>()
        var removed = 0

        for g in all {
            if seen.insert(g.id).inserted {
                continue
            }
            modelContext.delete(g)
            removed += 1
        }

        if removed > 0 {
            try? modelContext.save()
        }

        return Report(removedGraphs: removed)
    }
}
