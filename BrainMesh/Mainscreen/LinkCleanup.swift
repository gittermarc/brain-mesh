//
//  LinkCleanup.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import SwiftData

/// Shared cleanup helpers for MetaLink records.
enum LinkCleanup {

    /// Deletes all links referencing the given node (as source OR target), scoped to a graph if provided.
    @MainActor
    static func deleteLinks(
        referencing kind: NodeKind,
        id: UUID,
        graphID: UUID?,
        in modelContext: ModelContext
    ) {
        let k = kind.rawValue
        let nodeID = id
        let gid = graphID

        let fdSource = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.sourceKindRaw == k && l.sourceID == nodeID && (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdSource) {
            for l in links { modelContext.delete(l) }
        }

        let fdTarget = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.targetKindRaw == k && l.targetID == nodeID && (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdTarget) {
            for l in links { modelContext.delete(l) }
        }
    }
}
