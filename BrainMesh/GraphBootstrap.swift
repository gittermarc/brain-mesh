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

    /// Returns true if there are any legacy records still missing a `graphID`.
    /// Uses `fetchLimit = 1` to keep this check very cheap.
    static func hasLegacyRecords(using modelContext: ModelContext) -> Bool {
        do {
            var eFD = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { e in
                e.graphID == nil
            })
            eFD.fetchLimit = 1
            if try modelContext.fetch(eFD).isEmpty == false { return true }

            var aFD = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { a in
                a.graphID == nil
            })
            aFD.fetchLimit = 1
            if try modelContext.fetch(aFD).isEmpty == false { return true }

            var lFD = FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { l in
                l.graphID == nil
            })
            lFD.fetchLimit = 1
            if try modelContext.fetch(lFD).isEmpty == false { return true }
        } catch {
            return false
        }

        return false
    }

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
        guard hasLegacyRecords(using: modelContext) else { return }

        var changed = false

        // Entities
        do {
            let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate<MetaEntity> { e in
                e.graphID == nil
            })
            let ents = try modelContext.fetch(fd)
            for e in ents {
                e.graphID = defaultGraphID
                changed = true
            }
        } catch {
            // ignore
        }

        // Attributes
        do {
            let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate<MetaAttribute> { a in
                a.graphID == nil
            })
            let attrs = try modelContext.fetch(fd)
            for a in attrs {
                if let o = a.owner, let og = o.graphID {
                    a.graphID = og
                } else {
                    a.graphID = defaultGraphID
                }
                changed = true
            }
        } catch {
            // ignore
        }

        // Links
        do {
            let fd = FetchDescriptor<MetaLink>(predicate: #Predicate<MetaLink> { l in
                l.graphID == nil
            })
            let links = try modelContext.fetch(fd)
            for l in links {
                l.graphID = defaultGraphID
                changed = true
            }
        } catch {
            // ignore
        }

        if changed {
            try? modelContext.save()
        }
    }
}
