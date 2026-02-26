//
//  GraphCanvasScreen+ExpandAttributesOnly.swift
//  BrainMesh
//
//  PR A3: Entity selection shortcut “Attribute ansehen”
//  Expands only containment (Entity -> Attributes). No link fetch.
//

import SwiftUI
import SwiftData
import os

extension GraphCanvasScreen {

    // MARK: - Expand Attributes (containment-only)

    @MainActor
    func expandAttributesOnly(from key: NodeKey) async {
        guard key.kind == .entity else { return }
        if nodes.isEmpty { return }
        if edges.count >= maxLinks { return }

        let t = BMDuration()

        isLoading = true
        defer { isLoading = false }

        let existingKeys = Set(nodes.map(\.key))
        var newKeys: [NodeKey] = []
        var newEdges: [GraphEdge] = []

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

        guard let entity = fetchEntity(id: key.uuid) else {
            BMLog.expand.debug(
                "expandAttributesOnly missing entity id=\(key.uuid.uuidString, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2))"
            )
            return
        }

        let gid = activeGraphID

        let sortedAttrs = entity.attributesList.sorted { $0.name < $1.name }

        for a in sortedAttrs {
            if let gid, a.graphID != gid { continue }

            let ak = NodeKey(kind: .attribute, uuid: a.id)

            if !existingKeys.contains(ak) {
                if (existingKeys.count + newKeys.count) >= maxNodes { break }
                ensureNode(ak)
            }

            newEdges.append(GraphEdge(a: key, b: ak, type: .containment))

            if (edges.count + newEdges.count) >= maxLinks { break }
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
                "expandAttributesOnly noop entity=\(key.uuid.uuidString, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2))"
            )
            return
        }

        if !appendedNodes.isEmpty {
            nodes.append(contentsOf: appendedNodes)

            labelCache = updatedLabelCache
            imagePathCache = updatedImagePathCache
            iconSymbolCache = updatedIconSymbolCache
        }

        let mergedEdges = (edges + newEdges).unique()
        edges = Array(mergedEdges.prefix(maxLinks))

        seedNewNodesNearForAttributes(key, newNodeKeys: appendedNodes.map(\.key))

        BMLog.expand.info(
            "expandAttributesOnly ok entity=\(key.uuid.uuidString, privacy: .public) addedNodes=\(appendedNodes.count, privacy: .public) addedEdges=\(newEdges.count, privacy: .public) totalNodes=\(nodes.count, privacy: .public) totalEdges=\(edges.count, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2))"
        )
    }

    @MainActor
    private func seedNewNodesNearForAttributes(_ centerKey: NodeKey, newNodeKeys: [NodeKey]) {
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
