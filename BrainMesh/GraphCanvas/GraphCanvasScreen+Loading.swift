//
//  GraphCanvasScreen+Loading.swift
//  BrainMesh
//

import SwiftUI
import SwiftData
import os

extension GraphCanvasScreen {

    private struct GraphLoadResult {
        let nodes: [GraphNode]
        let edges: [GraphEdge]
        let directedEdgeNotes: [DirectedEdgeKey: String]
        let labelCache: [NodeKey: String]
        let imagePathCache: [NodeKey: String]
        let iconSymbolCache: [NodeKey: String]
    }

    // MARK: - Data loading

    @MainActor
    func ensureActiveGraphAndLoadIfNeeded() async {
        if activeGraphID == nil, let first = graphs.first {
            activeGraphIDString = first.id.uuidString
            BMLog.load.info("auto-selected first graph id=\(first.id.uuidString, privacy: .public)")
            return
        }
        scheduleLoadGraph(resetLayout: true)
    }

    @MainActor
    func loadGraph(resetLayout: Bool = true) async {
        if Task.isCancelled {
            isLoading = false
            return
        }

        let t = BMDuration()
        let mode: String = (focusEntity != nil) ? "neighborhood" : "global"
        let focusID: String = focusEntity?.id.uuidString ?? "-"
        let hopsValue: Int = hops
        let includeAttrs: Bool = showAttributes

        isLoading = true
        loadError = nil

        do {
            let result: GraphLoadResult
            if let focus = focusEntity {
                result = try loadNeighborhood(centerID: focus.id, hops: hops, includeAttributes: showAttributes)
            } else {
                result = try loadGlobal()
            }

            if Task.isCancelled {
                isLoading = false
                return
            }

            let nodeKeys = Set(result.nodes.map(\.key))

            let newPinned = pinned.intersection(nodeKeys)
            var newSelection = selection
            if let sel = newSelection, !nodeKeys.contains(sel) { newSelection = nil }

            let validDirected = Set(result.edges.flatMap {
                [
                    DirectedEdgeKey.make(source: $0.a, target: $0.b, type: $0.type),
                    DirectedEdgeKey.make(source: $0.b, target: $0.a, type: $0.type)
                ]
            })
            let newDirectedNotes = result.directedEdgeNotes.filter { validDirected.contains($0.key) }

            // ✅ Commit the result in one go (prevents cancelled/older loads from partially overriding state)
            nodes = result.nodes
            edges = result.edges
            labelCache = result.labelCache
            imagePathCache = result.imagePathCache
            iconSymbolCache = result.iconSymbolCache
            pinned = newPinned
            selection = newSelection
            directedEdgeNotes = newDirectedNotes

            if Task.isCancelled {
                isLoading = false
                return
            }

            if resetLayout { seedLayout(preservePinned: true) }
            isLoading = false

            BMLog.load.info(
                "loadGraph ok mode=\(mode, privacy: .public) focus=\(focusID, privacy: .public) hops=\(hopsValue, privacy: .public) attrs=\(includeAttrs, privacy: .public) nodes=\(nodes.count, privacy: .public) edges=\(edges.count, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2))"
            )
        } catch {
            isLoading = false
            loadError = error.localizedDescription

            BMLog.load.error(
                "loadGraph failed mode=\(mode, privacy: .public) focus=\(focusID, privacy: .public) hops=\(hopsValue, privacy: .public) attrs=\(includeAttrs, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2)) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    private func loadGlobal() throws -> GraphLoadResult {
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

        // ✅ Render caches (Labels/Bilder) einmalig pro Load – kein SwiftData-Fetch im Render-Pfad
        var newLabelCache: [NodeKey: String] = [:]
        var newImagePathCache: [NodeKey: String] = [:]
        var newIconSymbolCache: [NodeKey: String] = [:]

        for e in ents {
            let k = NodeKey(kind: .entity, uuid: e.id)
            newLabelCache[k] = e.name
            if let p = e.imagePath, !p.isEmpty { newImagePathCache[k] = p }
            if let s = e.iconSymbolName, !s.isEmpty { newIconSymbolCache[k] = s }
        }

        return GraphLoadResult(
            nodes: newNodes,
            edges: newEdges,
            directedEdgeNotes: notes,
            labelCache: newLabelCache,
            imagePathCache: newImagePathCache,
            iconSymbolCache: newIconSymbolCache
        )
    }

    private func loadNeighborhood(centerID: UUID, hops: Int, includeAttributes: Bool) throws -> GraphLoadResult {
        let kEntity = NodeKind.entity.rawValue
        let gid = activeGraphID

        // MARK: BFS – Entity neighborhood (batch per hop, no per-node fetch)

        var visitedEntities: Set<UUID> = [centerID]
        var frontier: Set<UUID> = [centerID]

        var collectedEntityLinks: [MetaLink] = []
        collectedEntityLinks.reserveCapacity(min(maxLinks, 256))

        var seenEntityLinkIDs: Set<UUID> = []
        seenEntityLinkIDs.reserveCapacity(min(maxLinks, 256))

        if hops > 0 {
            for _ in 1...hops {
                if visitedEntities.count >= maxNodes { break }
                if frontier.isEmpty { break }
                if collectedEntityLinks.count >= maxLinks { break }

                let frontierIDs = Array(frontier)
                let remainingLinks = max(0, maxLinks - collectedEntityLinks.count)
                if remainingLinks == 0 { break }

                var hopFD: FetchDescriptor<MetaLink>
                if let gid {
                    hopFD = FetchDescriptor(
                        predicate: #Predicate<MetaLink> { l in
                            (l.graphID == gid || l.graphID == nil) &&
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
                let hopLinks = (try? modelContext.fetch(hopFD)) ?? []
                if hopLinks.isEmpty { break }

                var next: Set<UUID> = []
                next.reserveCapacity(frontier.count * 2)

                for l in hopLinks {
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

        // MARK: Batch fetch entities (instead of fetchEntity(id:) in a loop)

        let entityIDs = Array(visitedEntities.prefix(maxNodes))
        var eFD: FetchDescriptor<MetaEntity>
        if let gid {
            eFD = FetchDescriptor(
                predicate: #Predicate<MetaEntity> { e in
                    entityIDs.contains(e.id) && (e.graphID == gid || e.graphID == nil)
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
        let ents = try modelContext.fetch(eFD)

        // MARK: Attributes (optional) – keep behavior, but only within node budget

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

        // MARK: Nodes

        var newNodes: [GraphNode] = []
        newNodes.reserveCapacity(ents.count + attrs.count)
        for e in ents { newNodes.append(GraphNode(key: NodeKey(kind: .entity, uuid: e.id), label: e.name)) }
        for a in attrs { newNodes.append(GraphNode(key: NodeKey(kind: .attribute, uuid: a.id), label: a.name)) }

        let nodeKeySet = Set(newNodes.map(\.key))

        // MARK: Edges + Notes

        var notes: [DirectedEdgeKey: String] = [:]
        var newEdges: [GraphEdge] = []
        newEdges.reserveCapacity(min(maxLinks, 512))

        // 1) Entity–Entity links from BFS collection
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

        // 2) Containment edges (Entity–Attribute)
        if includeAttributes, newEdges.count < maxLinks {
            var attrOwner: [UUID: UUID] = [:]
            attrOwner.reserveCapacity(attrs.count)
            for a in attrs {
                if let ownerID = a.owner?.id { attrOwner[a.id] = ownerID }
            }

            for a in attrs {
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
                            (l.graphID == gid || l.graphID == nil) &&
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
                let candidateLinks = (try? modelContext.fetch(linkFD)) ?? []

                for l in candidateLinks {
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

        // ✅ Render caches (Labels/Bilder) einmalig pro Load – kein SwiftData-Fetch im Render-Pfad
        var newLabelCache: [NodeKey: String] = [:]
        var newImagePathCache: [NodeKey: String] = [:]
        var newIconSymbolCache: [NodeKey: String] = [:]

        for e in ents {
            let k = NodeKey(kind: .entity, uuid: e.id)
            newLabelCache[k] = e.name
            if let p = e.imagePath, !p.isEmpty { newImagePathCache[k] = p }
            if let s = e.iconSymbolName, !s.isEmpty { newIconSymbolCache[k] = s }
        }

        for a in attrs {
            let k = NodeKey(kind: .attribute, uuid: a.id)
            newLabelCache[k] = a.displayName
            if let p = a.imagePath, !p.isEmpty { newImagePathCache[k] = p }
            if let s = a.iconSymbolName, !s.isEmpty { newIconSymbolCache[k] = s }
        }

        return GraphLoadResult(
            nodes: newNodes,
            edges: uniqueEdges,
            directedEdgeNotes: notes,
            labelCache: newLabelCache,
            imagePathCache: newImagePathCache,
            iconSymbolCache: newIconSymbolCache
        )
    }

}
