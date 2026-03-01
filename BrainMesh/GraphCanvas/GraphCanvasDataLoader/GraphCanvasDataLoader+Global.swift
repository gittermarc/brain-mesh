//
//  GraphCanvasDataLoader+Global.swift
//  BrainMesh
//
//  Split from GraphCanvasDataLoader.swift (P0.x): Global load.
//

import Foundation
import SwiftData

extension GraphCanvasDataLoader {

    static func loadGlobal(
        context: ModelContext,
        activeGraphID: UUID?,
        maxNodes: Int,
        maxLinks: Int
    ) throws -> GraphCanvasSnapshot {
        try Task.checkCancellation()

        var eFD: FetchDescriptor<MetaEntity>
        if let gid = activeGraphID {
            eFD = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in e.graphID == gid },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            eFD = FetchDescriptor(sortBy: [SortDescriptor(\MetaEntity.name)])
        }
        eFD.fetchLimit = maxNodes
        let ents = try context.fetch(eFD)
        try Task.checkCancellation()

        let kEntity = NodeKind.entity.rawValue
        var lFD: FetchDescriptor<MetaLink>
        if let gid = activeGraphID {
            lFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    l.graphID == gid &&
                    l.sourceKindRaw == kEntity && l.targetKindRaw == kEntity
                },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
        } else {
            lFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    l.sourceKindRaw == kEntity && l.targetKindRaw == kEntity
                },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
        }
        lFD.fetchLimit = maxLinks
        let links = try context.fetch(lFD)
        try Task.checkCancellation()

        let nodeIDs = Set(ents.map { $0.id })
        let filteredLinks = links.filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }

        let newNodes: [GraphNode] = ents.map { GraphNode(key: NodeKey(kind: .entity, uuid: $0.id), label: $0.name) }

        var notes: [DirectedEdgeKey: String] = [:]
        let newEdges: [GraphEdge] = filteredLinks.map { l in
            let s = NodeKey(kind: .entity, uuid: l.sourceID)
            let t = NodeKey(kind: .entity, uuid: l.targetID)

            if let n = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                let k = DirectedEdgeKey.make(source: s, target: t, type: .link)
                if notes[k] == nil { notes[k] = n }
            }

            return GraphEdge(a: s, b: t, type: .link)
        }.unique()

        let caches = try GraphCanvasDataLoader.buildRenderCaches(entities: ents, attributes: [])

        return GraphCanvasSnapshot(
            nodes: newNodes,
            edges: newEdges,
            directedEdgeNotes: notes,
            labelCache: caches.labelCache,
            imagePathCache: caches.imagePathCache,
            iconSymbolCache: caches.iconSymbolCache
        )
    }
}
