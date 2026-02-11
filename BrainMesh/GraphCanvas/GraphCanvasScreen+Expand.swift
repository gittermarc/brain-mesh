//
//  GraphCanvasScreen+Expand.swift
//  BrainMesh
//

import SwiftUI
import SwiftData
import os

extension GraphCanvasScreen {

    // MARK: - Expand (incremental)

    @MainActor
    func expand(from key: NodeKey) async {
        if nodes.isEmpty { return }
        if nodes.count >= maxNodes { return }

        let t = BMDuration()

        isLoading = true
        defer { isLoading = false }

        let existingKeys = Set(nodes.map(\.key))
        var newKeys: [NodeKey] = []
        var newEdges: [GraphEdge] = []
        var newNotes = directedEdgeNotes

        func ensureNode(_ nk: NodeKey) {
            guard !existingKeys.contains(nk) else { return }
            if !newKeys.contains(nk) { newKeys.append(nk) }
        }

        func nodeMeta(for nk: NodeKey) -> (nodeLabel: String, displayLabel: String, imagePath: String?, iconSymbolName: String?)? {
            switch nk.kind {
            case .entity:
                guard let e = fetchEntity(id: nk.uuid) else { return nil }
                return (nodeLabel: e.name, displayLabel: e.name, imagePath: e.imagePath, iconSymbolName: e.iconSymbolName)
            case .attribute:
                guard let a = fetchAttribute(id: nk.uuid) else { return nil }
                return (nodeLabel: a.name, displayLabel: a.displayName, imagePath: a.imagePath, iconSymbolName: a.iconSymbolName)
            }
        }

        let kindRaw = key.kind.rawValue
        let id = key.uuid

        let perExpandCap = min(220, max(40, maxLinks / 6))
        let gid = activeGraphID

        var outFD: FetchDescriptor<MetaLink>
        var inFD: FetchDescriptor<MetaLink>

        if let gid {
            outFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    (l.graphID == gid || l.graphID == nil) &&
                    l.sourceKindRaw == kindRaw && l.sourceID == id
                },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
            inFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in
                    (l.graphID == gid || l.graphID == nil) &&
                    l.targetKindRaw == kindRaw && l.targetID == id
                },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
        } else {
            outFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in l.sourceKindRaw == kindRaw && l.sourceID == id },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
            inFD = FetchDescriptor(
                predicate: #Predicate<MetaLink> { l in l.targetKindRaw == kindRaw && l.targetID == id },
                sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
            )
        }

        outFD.fetchLimit = perExpandCap
        inFD.fetchLimit = perExpandCap

        let outLinks = (try? modelContext.fetch(outFD)) ?? []
        let inLinks = (try? modelContext.fetch(inFD)) ?? []

        for l in outLinks {
            let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
            let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)

            if !existingKeys.contains(b) && (existingKeys.count + newKeys.count) >= maxNodes { break }

            ensureNode(a)
            ensureNode(b)
            newEdges.append(GraphEdge(a: a, b: b, type: .link))

            if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                if newNotes[dk] == nil { newNotes[dk] = note }
            }
            if (edges.count + newEdges.count) >= maxLinks { break }
        }

        if (edges.count + newEdges.count) < maxLinks {
            for l in inLinks {
                let a = NodeKey(kind: NodeKind(rawValue: l.sourceKindRaw) ?? .entity, uuid: l.sourceID)
                let b = NodeKey(kind: NodeKind(rawValue: l.targetKindRaw) ?? .entity, uuid: l.targetID)

                if !existingKeys.contains(a) && (existingKeys.count + newKeys.count) >= maxNodes { break }

                ensureNode(a)
                ensureNode(b)
                newEdges.append(GraphEdge(a: a, b: b, type: .link))

                if let note = l.note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                    let dk = DirectedEdgeKey.make(source: a, target: b, type: .link)
                    if newNotes[dk] == nil { newNotes[dk] = note }
                }
                if (edges.count + newEdges.count) >= maxLinks { break }
            }
        }

        if showAttributes {
            switch key.kind {
            case .entity:
                if let e = fetchEntity(id: key.uuid) {
                    let remaining = max(0, maxNodes - (existingKeys.count + newKeys.count))
                    if remaining > 0 {
                        let sortedAttrs = e.attributesList.sorted { $0.name < $1.name }
                        for a in sortedAttrs.prefix(remaining) {
                            if let gid, !(a.graphID == gid || a.graphID == nil) { continue }
                            let ak = NodeKey(kind: .attribute, uuid: a.id)
                            ensureNode(ak)
                            newEdges.append(GraphEdge(a: key, b: ak, type: .containment))
                            if (edges.count + newEdges.count) >= maxLinks { break }
                        }
                    }
                }
            case .attribute:
                if let a = fetchAttribute(id: key.uuid), let owner = a.owner {
                    let ek = NodeKey(kind: .entity, uuid: owner.id)
                    if !existingKeys.contains(ek), (existingKeys.count + newKeys.count) < maxNodes {
                        ensureNode(ek)
                    }
                    newEdges.append(GraphEdge(a: ek, b: key, type: .containment))
                }
            }
        }

        var appendedNodes: [GraphNode] = []
        appendedNodes.reserveCapacity(newKeys.count)

        var updatedLabelCache = labelCache
        var updatedImagePathCache = imagePathCache
        var updatedIconSymbolCache = iconSymbolCache

        for nk in newKeys {
            guard let meta = nodeMeta(for: nk) else { continue }
            appendedNodes.append(GraphNode(key: nk, label: meta.nodeLabel))

            updatedLabelCache[nk] = meta.displayLabel
            if let p = meta.imagePath, !p.isEmpty { updatedImagePathCache[nk] = p }
            else { updatedImagePathCache.removeValue(forKey: nk) }

            if let s = meta.iconSymbolName, !s.isEmpty { updatedIconSymbolCache[nk] = s }
            else { updatedIconSymbolCache.removeValue(forKey: nk) }
        }

        if appendedNodes.isEmpty && newEdges.isEmpty {
            BMLog.expand.debug(
                "expand noop key=\(key.kind.rawValue, privacy: .public)/\(key.uuid.uuidString, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2))"
            )
            return
        }

        nodes.append(contentsOf: appendedNodes)

        labelCache = updatedLabelCache
        imagePathCache = updatedImagePathCache
        iconSymbolCache = updatedIconSymbolCache

        let mergedEdges = (edges + newEdges).unique()
        edges = Array(mergedEdges.prefix(maxLinks))

        directedEdgeNotes = newNotes

        seedNewNodesNear(key, newNodeKeys: appendedNodes.map(\.key))

        BMLog.expand.info(
            "expand ok key=\(key.kind.rawValue, privacy: .public)/\(key.uuid.uuidString, privacy: .public) addedNodes=\(appendedNodes.count, privacy: .public) addedEdges=\(newEdges.count, privacy: .public) totalNodes=\(nodes.count, privacy: .public) totalEdges=\(edges.count, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2))"
        )
    }

    @MainActor
    private func seedNewNodesNear(_ centerKey: NodeKey, newNodeKeys: [NodeKey]) {
        guard !newNodeKeys.isEmpty else { return }
        guard let cp = positions[centerKey] else {
            for (i, k) in newNodeKeys.enumerated() {
                let angle = (CGFloat(i) / CGFloat(max(1, newNodeKeys.count))) * (.pi * 2)
                let p = CGPoint(x: cos(angle) * 140, y: sin(angle) * 140)
                positions[k] = p
                velocities[k] = .zero
            }
            return
        }

        let rBase: CGFloat = 90
        for (i, k) in newNodeKeys.enumerated() {
            if positions[k] != nil { continue }
            let angle = (CGFloat(i) / CGFloat(max(1, newNodeKeys.count))) * (.pi * 2)
            let r = rBase + CGFloat((i % 4)) * 14
            let p = CGPoint(x: cp.x + cos(angle) * r, y: cp.y + sin(angle) * r)
            positions[k] = p
            velocities[k] = .zero
        }
    }
}
