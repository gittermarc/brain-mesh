//
//  GraphCanvasScreen+Helpers.swift
//  BrainMesh
//

import SwiftUI
import SwiftData

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


    // MARK: - On-demand image hydration (Fix A)

    /// Ensures that the selected node's main image is available as a local cached JPEG file.
    ///
    /// Why: The graph overlay loads thumbnails from the local file cache for performance.
    /// If a record was synced to this device, `imagePath` may exist while the local file does not yet.
    /// This method writes the deterministic file on-demand (only for the current selection) and updates the render cache.
    @MainActor
    func ensureLocalMainImageCacheForSelectionIfNeeded(_ key: NodeKey) async {
        switch key.kind {
        case .entity:
            guard let e = fetchEntity(id: key.uuid) else { return }
            guard let d = e.imageData, !d.isEmpty else { return }

            let expected = "\(e.id.uuidString).jpg"
            let currentPath = (e.imagePath?.isEmpty == false) ? e.imagePath! : expected
            let hasFile = ImageStore.fileExists(path: currentPath)

            // Force a `selectedImagePath` change (nil -> filename) so GraphCanvasView refreshes its thumbnail cache.
            if !hasFile, selection == key {
                imagePathCache.removeValue(forKey: key)
            }

            guard let ensured = await ImageHydrator.ensureCachedJPEGExists(stableID: e.id, jpegData: d) else { return }

            var didModelChange = false
            if e.imagePath != ensured {
                e.imagePath = ensured
                didModelChange = true
            }
            if didModelChange { try? modelContext.save() }

            imagePathCache[key] = ensured

        case .attribute:
            guard let a = fetchAttribute(id: key.uuid) else { return }
            guard let d = a.imageData, !d.isEmpty else { return }

            let expected = "\(a.id.uuidString).jpg"
            let currentPath = (a.imagePath?.isEmpty == false) ? a.imagePath! : expected
            let hasFile = ImageStore.fileExists(path: currentPath)

            if !hasFile, selection == key {
                imagePathCache.removeValue(forKey: key)
            }

            guard let ensured = await ImageHydrator.ensureCachedJPEGExists(stableID: a.id, jpegData: d) else { return }

            var didModelChange = false
            if a.imagePath != ensured {
                a.imagePath = ensured
                didModelChange = true
            }
            if didModelChange { try? modelContext.save() }

            imagePathCache[key] = ensured
        }
    }

    // MARK: - Cache refresh (after editing in detail sheets)

    @MainActor
    func refreshNodeCaches(for key: NodeKey) {
        switch key.kind {
        case .entity:
            guard let e = fetchEntity(id: key.uuid) else { return }

            if let idx = nodes.firstIndex(where: { $0.key == key }) {
                nodes[idx] = GraphNode(key: key, label: e.name)
            }

            labelCache[key] = e.name
            if let p = e.imagePath, !p.isEmpty { imagePathCache[key] = p }
            else { imagePathCache.removeValue(forKey: key) }

            if let s = e.iconSymbolName, !s.isEmpty { iconSymbolCache[key] = s }
            else { iconSymbolCache.removeValue(forKey: key) }

        case .attribute:
            guard let a = fetchAttribute(id: key.uuid) else { return }

            if let idx = nodes.firstIndex(where: { $0.key == key }) {
                nodes[idx] = GraphNode(key: key, label: a.name)
            }

            // DisplayName ist fürs Sorting/Chip besser als nur der Attributname
            labelCache[key] = a.displayName
            if let p = a.imagePath, !p.isEmpty { imagePathCache[key] = p }
            else { imagePathCache.removeValue(forKey: key) }

            if let s = a.iconSymbolName, !s.isEmpty { iconSymbolCache[key] = s }
            else { iconSymbolCache.removeValue(forKey: key) }
        }
    }


}
