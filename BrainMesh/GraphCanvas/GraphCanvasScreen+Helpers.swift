//
//  GraphCanvasScreen+Helpers.swift
//  BrainMesh
//

import SwiftUI
import SwiftData
import UIKit

extension GraphCanvasScreen {

    // MARK: - Spotlight edges (Nodes-only default + Degree cap)

    func edgesForDisplay() -> [GraphEdge] {
        // ✅ Default: nodes-only (keine Linien)
        guard let sel = selection else { return [] }

        // ✅ Nur direkte Kanten des selektierten Nodes
        let incident = edges.filter { $0.a == sel || $0.b == sel }

        let containment = incident.filter { $0.type == .containment }
        var links = incident.filter { $0.type == .link }

        // stabilere Reihenfolge
        links.sort { displayLabel(for: otherEnd(of: $0, sel: sel)) < displayLabel(for: otherEnd(of: $1, sel: sel)) }

        if !showAllLinksForSelection {
            links = Array(links.prefix(degreeCap))
        }

        return (containment + links).unique()
    }

    private func otherEnd(of e: GraphEdge, sel: NodeKey) -> NodeKey {
        (e.a == sel) ? e.b : e.a
    }

    private func displayLabel(for key: NodeKey) -> String {
        if let cached = labelCache[key] { return cached }
        return nodes.first(where: { $0.key == key })?.label ?? ""
    }

    func hiddenLinkCountForSelection() -> Int {
        guard let sel = selection else { return 0 }
        if showAllLinksForSelection { return 0 }
        let incidentLinkCount = edges.filter { $0.type == .link && ($0.a == sel || $0.b == sel) }.count
        return max(0, incidentLinkCount - degreeCap)
    }


    // MARK: - Helpers

    func nodeForKey(_ key: NodeKey) -> GraphNode? {
        nodes.first(where: { $0.key == key })
    }

    func fetchEntity(id: UUID) -> MetaEntity? {
        let nodeID = id
        let fd = FetchDescriptor<MetaEntity>(predicate: #Predicate { e in e.id == nodeID })
        guard let e = try? modelContext.fetch(fd).first else { return nil }
        if let gid = activeGraphID {
            return (e.graphID == gid || e.graphID == nil) ? e : nil
        }
        return e
    }

    func fetchAttribute(id: UUID) -> MetaAttribute? {
        let nodeID = id
        let fd = FetchDescriptor<MetaAttribute>(predicate: #Predicate { a in a.id == nodeID })
        guard let a = try? modelContext.fetch(fd).first else { return nil }
        if let gid = activeGraphID {
            return (a.graphID == gid || a.graphID == nil) ? a : nil
        }
        return a
    }

    func selectedImagePath() -> String? {
        guard let sel = selection else { return nil }
        return imagePathCache[sel]
    }


    var selectedImagePathValue: String? { selectedImagePath() }

    func prefetchSelectedFullImage() {
        let path = selectedImagePathValue
        guard path != cachedFullImagePath else { return }

        cachedFullImagePath = path
        cachedFullImage = nil

        guard let path, !path.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let img = ImageStore.loadUIImage(path: path)
            DispatchQueue.main.async {
                if cachedFullImagePath == path {
                    cachedFullImage = img
                }
            }
        }
    }


}
