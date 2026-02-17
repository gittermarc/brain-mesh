//
//  GraphCanvasDataLoader.swift
//  BrainMesh
//
//  P0.1: Load GraphCanvas data off the UI thread.
//  Goal: Avoid blocking the main thread with SwiftData fetches when opening/switching graphs.
//

import Foundation
import SwiftData
import os

/// Snapshot DTO returned to the UI.
///
/// NOTE: This is intentionally a value-only container so the UI can commit state in one go.
/// We mark it as `@unchecked Sendable` to keep the patch minimal (Graph types are value types).
struct GraphCanvasSnapshot: @unchecked Sendable {
    let nodes: [GraphNode]
    let edges: [GraphEdge]
    let directedEdgeNotes: [DirectedEdgeKey: String]
    let labelCache: [NodeKey: String]
    let imagePathCache: [NodeKey: String]
    let iconSymbolCache: [NodeKey: String]
}

actor GraphCanvasDataLoader {

    static let shared = GraphCanvasDataLoader()

    private var container: AnyModelContainer? = nil
    private let log = Logger(subsystem: "BrainMesh", category: "GraphCanvasDataLoader")

    func configure(container: AnyModelContainer) {
        self.container = container
        #if DEBUG
        log.debug("✅ configured")
        #endif
    }

    func loadSnapshot(
        activeGraphID: UUID?,
        focusEntityID: UUID?,
        hops: Int,
        includeAttributes: Bool,
        maxNodes: Int,
        maxLinks: Int
    ) async throws -> GraphCanvasSnapshot {
        let configuredContainer = self.container
        guard let configuredContainer else {
            throw NSError(
                domain: "BrainMesh.GraphCanvasDataLoader",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "GraphCanvasDataLoader not configured"]
            )
        }

        // Run SwiftData fetches and relationship traversal off the UI thread.
        return try await Task.detached(priority: .utility) { [configuredContainer] in
            let context = ModelContext(configuredContainer.container)
            context.autosaveEnabled = false

            if let focusEntityID {
                return try GraphCanvasDataLoader.loadNeighborhood(
                    context: context,
                    activeGraphID: activeGraphID,
                    centerID: focusEntityID,
                    hops: hops,
                    includeAttributes: includeAttributes,
                    maxNodes: maxNodes,
                    maxLinks: maxLinks
                )
            } else {
                return try GraphCanvasDataLoader.loadGlobal(
                    context: context,
                    activeGraphID: activeGraphID,
                    maxNodes: maxNodes,
                    maxLinks: maxLinks
                )
            }
        }.value
    }

    // MARK: - Core loaders

    private static func loadGlobal(
        context: ModelContext,
        activeGraphID: UUID?,
        maxNodes: Int,
        maxLinks: Int
    ) throws -> GraphCanvasSnapshot {
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
        let ents = try context.fetch(eFD)

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
        let links = try context.fetch(lFD)

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

        // Render caches once per load.
        var newLabelCache: [NodeKey: String] = [:]
        var newImagePathCache: [NodeKey: String] = [:]
        var newIconSymbolCache: [NodeKey: String] = [:]

        for e in ents {
            let k = NodeKey(kind: .entity, uuid: e.id)
            newLabelCache[k] = e.name
            if let p = e.imagePath, !p.isEmpty { newImagePathCache[k] = p }
            if let s = e.iconSymbolName, !s.isEmpty { newIconSymbolCache[k] = s }
        }

        return GraphCanvasSnapshot(
            nodes: newNodes,
            edges: newEdges,
            directedEdgeNotes: notes,
            labelCache: newLabelCache,
            imagePathCache: newImagePathCache,
            iconSymbolCache: newIconSymbolCache
        )
    }

    private static func loadNeighborhood(
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

        // BFS – Entity neighborhood (batch per hop, no per-node fetch)
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
                if Task.isCancelled { break }

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
                let hopLinks = (try? context.fetch(hopFD)) ?? []
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

        // Batch fetch entities (instead of fetchEntity(id:) in a loop)
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
        let ents = try context.fetch(eFD)

        // Attributes (optional) – keep behavior, but only within node budget
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

        // Nodes
        var newNodes: [GraphNode] = []
        newNodes.reserveCapacity(ents.count + attrs.count)
        for e in ents { newNodes.append(GraphNode(key: NodeKey(kind: .entity, uuid: e.id), label: e.name)) }
        for a in attrs { newNodes.append(GraphNode(key: NodeKey(kind: .attribute, uuid: a.id), label: a.name)) }

        let nodeKeySet = Set(newNodes.map(\.key))

        // Edges + Notes
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
                let candidateLinks = (try? context.fetch(linkFD)) ?? []

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

        // Render caches once per load.
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

        return GraphCanvasSnapshot(
            nodes: newNodes,
            edges: uniqueEdges,
            directedEdgeNotes: notes,
            labelCache: newLabelCache,
            imagePathCache: newImagePathCache,
            iconSymbolCache: newIconSymbolCache
        )
    }
}
