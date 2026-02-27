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
    func loadGraph(loadToken: UUID, resetLayout: Bool = true) async {
        // ✅ Stale-result guard: only the latest scheduled load is allowed to touch UI state.
        guard currentLoadToken == loadToken else { return }

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

            // If another load was scheduled while we were fetching, ignore this result.
            guard currentLoadToken == loadToken else { return }

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

            // If another load was scheduled while we were applying the result, ignore any further work.
            guard currentLoadToken == loadToken else { return }

            if Task.isCancelled {
                isLoading = false
                return
            }

            if resetLayout { seedLayout(preservePinned: true) }

            // ✅ Jump handling: after nodes + layout are committed, select + center if a staged jump is waiting.
            applyStagedJumpAfterLoadIfNeeded(availableKeys: nodeKeys)
            isLoading = false

            BMLog.load.info(
                "loadGraph ok mode=\(mode, privacy: .public) focus=\(focusID, privacy: .public) hops=\(hopsValue, privacy: .public) attrs=\(includeAttrs, privacy: .public) nodes=\(nodes.count, privacy: .public) edges=\(edges.count, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2))"
            )
        } catch is CancellationError {
            // Cancellation is expected when switching graphs / focus / settings quickly.
            // We intentionally do not surface this as an error.
            if currentLoadToken == loadToken {
                isLoading = false
            }
        } catch {
            // Ignore stale errors from older loads.
            guard currentLoadToken == loadToken else { return }

            isLoading = false
            loadError = error.localizedDescription

            BMLog.load.error(
                "loadGraph failed mode=\(mode, privacy: .public) focus=\(focusID, privacy: .public) hops=\(hopsValue, privacy: .public) attrs=\(includeAttrs, privacy: .public) ms=\(t.millisecondsElapsed, format: .fixed(precision: 2)) error=\(String(describing: error), privacy: .public)"
            )
        }
    }
}
