//
//  GraphCanvasScreen+Loading.swift
//  BrainMesh
//

import SwiftUI
import SwiftData

extension GraphCanvasScreen {

    // MARK: - Data loading

    @MainActor
    func ensureActiveGraphAndLoadIfNeeded() async {
        if activeGraphID == nil, let first = graphs.first {
            activeGraphIDString = first.id.uuidString
            return
        }
        await loadGraph()
    }

    @MainActor
    func loadGraph(resetLayout: Bool = true) async {
        isLoading = true
        loadError = nil

        do {
            if let focus = focusEntity {
                try loadNeighborhood(centerID: focus.id, hops: hops, includeAttributes: showAttributes)
            } else {
                try loadGlobal()
            }

            let nodeKeys = Set(nodes.map(\.key))
            pinned = pinned.intersection(nodeKeys)
            if let sel = selection, !nodeKeys.contains(sel) { selection = nil }

            let validDirected = Set(edges.flatMap {
                [
                    DirectedEdgeKey.make(source: $0.a, target: $0.b, type: $0.type),
                    DirectedEdgeKey.make(source: $0.b, target: $0.a, type: $0.type)
                ]
            })
            directedEdgeNotes = directedEdgeNotes.filter { validDirected.contains($0.key) }

            if resetLayout { seedLayout(preservePinned: true) }
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func loadGlobal() throws {
        var eFD: FetchDescriptor<MetaEntity>
        if let gid = activeGraphID {
            eFD = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in e.graphID == gid || e.graphID == nil },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            eFD = FetchDescriptor(sortBy: [SortDescriptor(\MetaEntity.name)])
        }
        eFD.fetchLimit = maxNodes
        let ents = try modelContext.fetch(eFD)

        let kEntity = NodeKind.entity.rawValue
        var lFD: FetchDescriptor<MetaLink>
        if let gid = activeGraphID {
            lFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    (l.graphID == gid || l.graphID == nil) &&
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
        let links = try modelContext.fetch(lFD)

        let nodeIDs = Set(ents.map { $0.id })
        let filteredLinks = links.filter { nodeIDs.contains($0.sourceID) && nodeIDs.contains($0.targetID) }

        nodes = ents.map { GraphNode(key: NodeKey(kind: .entity, uuid: $0.id), label: $0.name) }

        var notes: [DirectedEdgeKey: String] = [:]
        edges = filteredLinks.map { l in
            let s = NodeKey(kind: .entity, uuid: l.sourceID)
            let t = NodeKey(kind: .entity, uuid: l.targetID)

            if let n = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty {
                let k = DirectedEdgeKey.make(source: s, target: t, type: .link)
                if notes[k] == nil { notes[k] = n }
            }

            return GraphEdge(a: s, b: t, type: .link)
        }.unique()

        directedEdgeNotes = notes

        // ✅ Render caches (Labels/Bilder) einmalig pro Load – kein SwiftData-Fetch im Render-Pfad
        var newLabelCache: [NodeKey: String] = [:]
        var newImagePathCache: [NodeKey: String] = [:]

        for e in ents {
            let k = NodeKey(kind: .entity, uuid: e.id)
            newLabelCache[k] = e.name
            if let p = e.imagePath, !p.isEmpty { newImagePathCache[k] = p }
        }

        labelCache = newLabelCache
        imagePathCache = newImagePathCache

    }

    private func loadNeighborhood(centerID: UUID, hops: Int, includeAttributes: Bool) throws {
        let kEntity = NodeKind.entity.rawValue
        let gid = activeGraphID

        var visitedEntities: Set<UUID> = [centerID]
        var frontier: Set<UUID> = [centerID]
        var collectedEntityLinks: [MetaLink] = []

        for _ in 1...hops {
            if visitedEntities.count >= maxNodes { break }

            var next: Set<UUID> = []

            for nodeID in frontier {
                if visitedEntities.count >= maxNodes { break }

                let nID = nodeID

                var outFD: FetchDescriptor<MetaLink>
                if let gid {
                    outFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            l.sourceID == nID
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    outFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            l.sourceID == nID
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }
                outFD.fetchLimit = maxLinks
                let outLinks = (try? modelContext.fetch(outFD)) ?? []

                for l in outLinks {
                    collectedEntityLinks.append(l)
                    next.insert(l.targetID)
                    if collectedEntityLinks.count >= maxLinks { break }
                }

                if collectedEntityLinks.count >= maxLinks { break }

                var inFD: FetchDescriptor<MetaLink>
                if let gid {
                    inFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            l.targetID == nID
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    inFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            l.sourceKindRaw == kEntity &&
                            l.targetKindRaw == kEntity &&
                            l.targetID == nID
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }
                inFD.fetchLimit = maxLinks
                let inLinks = (try? modelContext.fetch(inFD)) ?? []

                for l in inLinks {
                    collectedEntityLinks.append(l)
                    next.insert(l.sourceID)
                    if collectedEntityLinks.count >= maxLinks { break }
                }
            }

            next.subtract(visitedEntities)
            visitedEntities.formUnion(next)
            frontier = next
            if frontier.isEmpty { break }
        }

        var ents: [MetaEntity] = []
        ents.reserveCapacity(min(visitedEntities.count, maxNodes))
        for id in visitedEntities.prefix(maxNodes) {
            if let e = fetchEntity(id: id) { ents.append(e) }
        }
        ents.sort { $0.name < $1.name }

        var attrs: [MetaAttribute] = []
        if includeAttributes {
            let remaining = max(0, maxNodes - ents.count)
            if remaining > 0 {
                for e in ents {
                    let sortedAttrs = e.attributesList.sorted { $0.name < $1.name }
                    for a in sortedAttrs {
                        if let gid, !(a.graphID == gid || a.graphID == nil) { continue }
                        attrs.append(a)
                        if attrs.count >= remaining { break }
                    }
                    if attrs.count >= remaining { break }
                }
            }
        }

        var newNodes: [GraphNode] = []
        newNodes.reserveCapacity(ents.count + attrs.count)
        for e in ents { newNodes.append(GraphNode(key: NodeKey(kind: .entity, uuid: e.id), label: e.name)) }
        for a in attrs { newNodes.append(GraphNode(key: NodeKey(kind: .attribute, uuid: a.id), label: a.name)) }

        let nodeKeySet = Set(newNodes.map(\.key))

        var notes: [DirectedEdgeKey: String] = [:]
        var newEdges: [GraphEdge] = []
        newEdges.reserveCapacity(maxLinks)

        for l in collectedEntityLinks {
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

        if includeAttributes {
            var attrOwner: [UUID: UUID] = [:]
            for e in ents { for a in e.attributesList { attrOwner[a.id] = e.id } }

            for a in attrs {
                if let ownerID = attrOwner[a.id] {
                    let ek = NodeKey(kind: .entity, uuid: ownerID)
                    let ak = NodeKey(kind: .attribute, uuid: a.id)
                    if nodeKeySet.contains(ek) && nodeKeySet.contains(ak) {
                        newEdges.append(GraphEdge(a: ek, b: ak, type: .containment))
                    }
                    if newEdges.count >= maxLinks { break }
                }
            }
        }

        if includeAttributes, newEdges.count < maxLinks {
            let remaining = maxLinks - newEdges.count
            let perNodeCap = max(20, remaining / max(1, newNodes.count))

            var linkEdges: [GraphEdge] = []

            for n in newNodes {
                if linkEdges.count >= remaining { break }
                let k = n.key.kind.rawValue
                let id = n.key.uuid

                var outFD: FetchDescriptor<MetaLink>
                if let gid {
                    outFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
                            l.sourceKindRaw == k && l.sourceID == id
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    outFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in l.sourceKindRaw == k && l.sourceID == id },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }
                outFD.fetchLimit = perNodeCap
                let out = (try? modelContext.fetch(outFD)) ?? []

                for l in out {
                    let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
                    let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)
                    if nodeKeySet.contains(a) && nodeKeySet.contains(b) {
                        linkEdges.append(GraphEdge(a: a, b: b, type: .link))

                        if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                            let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                            if notes[dk] == nil { notes[dk] = note }
                        }
                    }
                    if linkEdges.count >= remaining { break }
                }

                if linkEdges.count >= remaining { break }

                var inFD: FetchDescriptor<MetaLink>
                if let gid {
                    inFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
                            l.targetKindRaw == k && l.targetID == id
                        },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                } else {
                    inFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in l.targetKindRaw == k && l.targetID == id },
                        sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
                    )
                }
                inFD.fetchLimit = perNodeCap
                let inc = (try? modelContext.fetch(inFD)) ?? []

                for l in inc {
                    let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
                    let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)
                    if nodeKeySet.contains(a) && nodeKeySet.contains(b) {
                        linkEdges.append(GraphEdge(a: a, b: b, type: .link))

                        if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                            let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                            if notes[dk] == nil { notes[dk] = note }
                        }
                    }
                    if linkEdges.count >= remaining { break }
                }
            }

            newEdges.append(contentsOf: linkEdges.unique().prefix(remaining))
        }

        nodes = newNodes
        edges = newEdges.unique()
        directedEdgeNotes = notes

        // ✅ Render caches (Labels/Bilder) einmalig pro Load – kein SwiftData-Fetch im Render-Pfad
        var newLabelCache: [NodeKey: String] = [:]
        var newImagePathCache: [NodeKey: String] = [:]

        for e in ents {
            let k = NodeKey(kind: .entity, uuid: e.id)
            newLabelCache[k] = e.name
            if let p = e.imagePath, !p.isEmpty { newImagePathCache[k] = p }
        }

        for a in attrs {
            let k = NodeKey(kind: .attribute, uuid: a.id)
            // DisplayName (Owner · Attr) ist fürs Sorting/Chip schöner als nur der Attributname
            newLabelCache[k] = a.displayName
            if let p = a.imagePath, !p.isEmpty { newImagePathCache[k] = p }
        }

        labelCache = newLabelCache
        imagePathCache = newImagePathCache

    }


}
