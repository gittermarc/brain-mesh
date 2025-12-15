//
//  GraphBootstrap.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import Foundation
import SwiftData

@MainActor
enum GraphBootstrap {

    static func ensureAtLeastOneGraph(using modelContext: ModelContext) -> MetaGraph {
        // ältester Graph = "default"
        let fd = FetchDescriptor<MetaGraph>(sortBy: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
        if let g = try? modelContext.fetch(fd).first {
            return g
        }

        let g = MetaGraph(name: "Default")
        modelContext.insert(g)
        try? modelContext.save()
        return g
    }

    static func migrateLegacyRecordsIfNeeded(defaultGraphID: UUID, using modelContext: ModelContext) {
        var changed = false

        // Entities
        if let ents = try? modelContext.fetch(FetchDescriptor<MetaEntity>()) {
            for e in ents where e.graphID == nil {
                e.graphID = defaultGraphID
                changed = true
            }
        }

        // Attributes
        if let attrs = try? modelContext.fetch(FetchDescriptor<MetaAttribute>()) {
            for a in attrs where a.graphID == nil {
                if let o = a.owner, let og = o.graphID {
                    a.graphID = og
                } else {
                    a.graphID = defaultGraphID
                }
                changed = true
            }
        }

        // Links
        if let links = try? modelContext.fetch(FetchDescriptor<MetaLink>()) {
            for l in links where l.graphID == nil {
                l.graphID = defaultGraphID
                changed = true
            }
        }

        if changed {
            try? modelContext.save()
        }
    }
}
