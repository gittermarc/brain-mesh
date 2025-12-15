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

    /// Deterministischer Default-Graph (gleich auf allen Devices → keine Duplikate)
    static let defaultGraphID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func bootstrap(using modelContext: ModelContext) {
        var changed = false

        // 1) Default Graph sicherstellen
        if ensureDefaultGraph(using: modelContext) { changed = true }

        // 2) Backfill: Entities / Attributes / Links ohne graphID → Default / Owner ableiten
        if backfillGraphIDs(using: modelContext) { changed = true }

        // 3) Speichern (nur wenn nötig)
        if changed {
            try? modelContext.save()
        }

        // Session setzen (später UI)
        GraphSession.shared.activeGraphID = defaultGraphID
    }

    private static func ensureDefaultGraph(using modelContext: ModelContext) -> Bool {
        let gid = defaultGraphID

        let fd = FetchDescriptor<MetaGraph>(predicate: #Predicate { g in g.id == gid })
        let existing = (try? modelContext.fetch(fd))?.first

        if existing != nil { return false }

        let g = MetaGraph(id: gid, name: "Default", isDefault: true)
        modelContext.insert(g)
        return true
    }

    private static func backfillGraphIDs(using modelContext: ModelContext) -> Bool {
        var changed = false
        let gid = defaultGraphID

        // Entities
        do {
            let ents = try modelContext.fetch(FetchDescriptor<MetaEntity>())
            for e in ents where e.graphID == nil {
                e.graphID = gid
                changed = true
            }
        } catch {
            // ignore
        }

        // Attributes
        do {
            let attrs = try modelContext.fetch(FetchDescriptor<MetaAttribute>())
            for a in attrs where a.graphID == nil {
                // Owner bevorzugen
                if let og = a.owner?.graphID {
                    a.graphID = og
                } else {
                    a.graphID = gid
                }
                changed = true
            }
        } catch {
            // ignore
        }

        // Links
        do {
            let links = try modelContext.fetch(FetchDescriptor<MetaLink>())
            for l in links where l.graphID == nil {
                // Graph aus Source/Target ableiten, wenn möglich
                let sg = resolveGraphID(of: l.sourceKind, id: l.sourceID, using: modelContext)
                let tg = resolveGraphID(of: l.targetKind, id: l.targetID, using: modelContext)

                if let sg, let tg, sg == tg {
                    l.graphID = sg
                } else if let sg {
                    l.graphID = sg
                } else if let tg {
                    l.graphID = tg
                } else {
                    l.graphID = gid
                }
                changed = true
            }
        } catch {
            // ignore
        }

        return changed
    }

    private static func resolveGraphID(of kind: NodeKind, id: UUID, using modelContext: ModelContext) -> UUID? {
        let nodeID = id

        switch kind {
        case .entity:
            let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate { e in e.id == nodeID })
            return (try? modelContext.fetch(fd))?.first?.graphID

        case .attribute:
            let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in a.id == nodeID })
            if let a = (try? modelContext.fetch(fd))?.first {
                return a.graphID ?? a.owner?.graphID
            }
            return nil
        }
    }
}
