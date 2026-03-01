//
//  GraphCanvasDataLoader+Neighborhood.swift
//  BrainMesh
//
//  Split from GraphCanvasDataLoader.swift (P0.x): Neighborhood BFS load.
//

import Foundation
import SwiftData

extension GraphCanvasDataLoader {

    static func loadNeighborhood(
        context: ModelContext,
        activeGraphID: UUID?,
        centerID: UUID,
        hops: Int,
        includeAttributes: Bool,
        maxNodes: Int,
        maxLinks: Int
    ) throws -> GraphCanvasSnapshot {
        let kEntity = NodeKind.entity.rawValue
        let gid = activeGraphID

        try Task.checkCancellation()

        // BFS – Entity neighborhood (batch per hop, no per-node fetch)
        var visitedEntities: Set<UUID> = [centerID]
        var frontier: Set<UUID> = [centerID]

        var collectedEntityLinks: [MetaLink] = []
        collectedEntityLinks.reserveCapacity(min(maxLinks, 256))

        var seenEntityLinkIDs: Set<UUID> = []
        seenEntityLinkIDs.reserveCapacity(min(maxLinks, 256))

        if hops > 0 {
            for _ in 1...hops {
                try Task.checkCancellation()

                if visitedEntities.count >= maxNodes { break }
                if frontier.isEmpty { break }
                if collectedEntityLinks.count >= maxLinks { break }
                try Task.checkCancellation()

                let frontierIDs = Array(frontier)
                let remainingLinks = max(0, maxLinks - collectedEntityLinks.count)
                if remainingLinks == 0 { break }

                var hopFD: FetchDescriptor<MetaLink>
                if let gid {
                    hopFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            l.graphID == gid &&
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            (frontierIDs.contains(l.sourceID) || frontierIDs.contains(l.targetID))
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    hopFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            (frontierIDs.contains(l.sourceID) || frontierIDs.contains(l.targetID))
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }

                hopFD.fetchLimit = remainingLinks
                let hopLinks = (try? context.fetch(hopFD)) ?? []
                try Task.checkCancellation()
                if hopLinks.isEmpty { break }

                var next: Set<UUID> = []
                next.reserveCapacity(frontier.count * 2)

                for l in hopLinks {
                    try Task.checkCancellation()

                    if !seenEntityLinkIDs.insert(l.id).inserted { continue }

                    collectedEntityLinks.append(l)

                    if frontier.contains(l.sourceID) { next.insert(l.targetID) }
                    if frontier.contains(l.targetID) { next.insert(l.sourceID) }

                    if collectedEntityLinks.count >= maxLinks { break }
                }

                next.subtract(visitedEntities)
                if next.isEmpty { break }

                let remainingNodeCapacity = max(0, maxNodes - visitedEntities.count)
                if remainingNodeCapacity == 0 { break }
                if next.count > remainingNodeCapacity {
                    next = Set(next.prefix(remainingNodeCapacity))
                }

                visitedEntities.formUnion(next)
                frontier = next
            }
        }

        // Batch fetch entities (instead of fetchEntity(id:) in a loop)
        let entityIDs = Array(visitedEntities.prefix(maxNodes))
        var eFD: FetchDescriptor<MetaEntity>
        if let gid {
            eFD = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    entityIDs.contains(e.id) && e.graphID == gid
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            eFD = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in entityIDs.contains(e.id) },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        }
        eFD.fetchLimit = maxNodes
        let ents = try context.fetch(eFD)
        try Task.checkCancellation()

        // Attributes (optional) – keep behavior, but only within node budget
        var attrs: [MetaAttribute] = []
        if includeAttributes {
            let remaining = max(0, maxNodes - ents.count)
            if remaining > 0 {
                for e in ents {
                    try Task.checkCancellation()

                    let sortedAttrs = e.attributesList.sorted { $0.name < $1.name }
                    for a in sortedAttrs {
                        if let gid, a.graphID != gid { continue }
                        attrs.append(a)
                        if attrs.count >= remaining { break }
                    }
                    if attrs.count >= remaining { break }
                }
            }
        }

        // Nodes
        var newNodes: [GraphNode] = []
        newNodes.reserveCapacity(ents.count + attrs.count)
        for e in ents {
            try Task.checkCancellation()
            newNodes.append(GraphNode(key: NodeKey(kind: .entity, uuid: e.id), label: e.name))
        }
        for a in attrs {
            try Task.checkCancellation()
            newNodes.append(GraphNode(key: NodeKey(kind: .attribute, uuid: a.id), label: a.name))
        }

        let nodeKeySet = Set(newNodes.map(\.key))

        // Edges + Notes
        var notes: [DirectedEdgeKey: String] = [:]
        var newEdges: [GraphEdge] = []
        newEdges.reserveCapacity(min(maxLinks, 512))

        // 1) Entity–Entity links from BFS collection
        for l in collectedEntityLinks {
            try Task.checkCancellation()

            let a = NodeKey(kind: .entity, uuid: l.sourceID)
            let b = NodeKey(kind: .entity, uuid: l.targetID)
            if nodeKeySet.contains(a) && nodeKeySet.contains(b) {
                newEdges.append(GraphEdge(a: a, b: b, type: .link))

                if let n = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                    let k = DirectedEdgeKey.make(source: a, target: b, type: .link)
                    if notes[k] == nil { notes[k] = n }
                }
            }
            if newEdges.count >= maxLinks { break }
        }

        // 2) Containment edges (Entity–Attribute)
        if includeAttributes, newEdges.count < maxLinks {
            var attrOwner: [UUID: UUID] = [:]
            attrOwner.reserveCapacity(attrs.count)
            for a in attrs {
                if let ownerID = a.owner?.id { attrOwner[a.id] = ownerID }
            }

            for a in attrs {
                try Task.checkCancellation()

                guard let ownerID = attrOwner[a.id] else { continue }

                let ek = NodeKey(kind: .entity, uuid: ownerID)
                let ak = NodeKey(kind: .attribute, uuid: a.id)
                if nodeKeySet.contains(ek) && nodeKeySet.contains(ak) {
                    newEdges.append(GraphEdge(a: ek, b: ak, type: .containment))
                }

                if newEdges.count >= maxLinks { break }
            }
        }

        // 3) Additional links between any loaded nodes (batch instead of per-node N+1)
        if includeAttributes, newEdges.count < maxLinks {
            let remaining = maxLinks - newEdges.count
            if remaining > 0 {
                let visibleIDs = Array(Set(newNodes.map { $0.key.uuid }))

                var linkFD: FetchDescriptor<MetaLink>
                if let gid {
                    linkFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            l.graphID == gid &&
                            (visibleIDs.contains(l.sourceID) || visibleIDs.contains(l.targetID))
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    linkFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            visibleIDs.contains(l.sourceID) || visibleIDs.contains(l.targetID)
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }

                // Oversample a bit because we filter by (kind,id) in-memory.
                linkFD.fetchLimit = min(maxLinks, max(remaining * 4, remaining))
                let candidateLinks = (try? context.fetch(linkFD)) ?? []
                try Task.checkCancellation()

                for l in candidateLinks {
                    try Task.checkCancellation()
                    let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
                    let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)
                    if nodeKeySet.contains(a) && nodeKeySet.contains(b) {
                        newEdges.append(GraphEdge(a: a, b: b, type: .link))

                        if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                            let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                            if notes[dk] == nil { notes[dk] = note }
                        }

                        if newEdges.count >= maxLinks { break }
                    }
                }
            }
        }

        let uniqueEdges = newEdges.unique()
        let caches = try GraphCanvasDataLoader.buildRenderCaches(entities: ents, attributes: attrs)

        return GraphCanvasSnapshot(
            nodes: newNodes,
            edges: uniqueEdges,
            directedEdgeNotes: notes,
            labelCache: caches.labelCache,
            imagePathCache: caches.imagePathCache,
            iconSymbolCache: caches.iconSymbolCache
        )
    }
}
