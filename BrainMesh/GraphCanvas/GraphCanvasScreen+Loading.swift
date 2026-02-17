//
//  GraphCanvasScreen+Loading.swift
//  BrainMesh
//

import SwiftUI
import SwiftData
import os

extension GraphCanvasScreen {

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
            let focusUUID = focusEntity?.id
            let snapshot = try await GraphCanvasDataLoader.shared.loadSnapshot(
                activeGraphID: activeGraphID,
                focusEntityID: focusUUID,
                hops: hops,
                includeAttributes: showAttributes,
                maxNodes: maxNodes,
                maxLinks: maxLinks
            )

            if Task.isCancelled {
                isLoading = false
                return
            }

            let nodeKeys = Set(snapshot.nodes.map(\.key))

            let newPinned = pinned.intersection(nodeKeys)
            var newSelection = selection
            if let sel = newSelection, !nodeKeys.contains(sel) { newSelection = nil }

            let validDirected = Set(snapshot.edges.flatMap {
                [
                    DirectedEdgeKey.make(source: $0.a, target: $0.b, type: $0.type),
                    DirectedEdgeKey.make(source: $0.b, target: $0.a, type: $0.type)
                ]
            })
            let newDirectedNotes = snapshot.directedEdgeNotes.filter { validDirected.contains($0.key) }

            // ✅ Commit the result in one go (prevents cancelled/older loads from partially overriding state)
            nodes = snapshot.nodes
            edges = snapshot.edges
            labelCache = snapshot.labelCache
            imagePathCache = snapshot.imagePathCache
            iconSymbolCache = snapshot.iconSymbolCache
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
}
