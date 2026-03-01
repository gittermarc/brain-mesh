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
        try Task.checkCancellation()

        let context = ModelContext(configuredContainer.container)
        context.autosaveEnabled = false

        try Task.checkCancellation()

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
    }

    // MARK: - Core loaders
    // Moved into:
    // - GraphCanvasDataLoader+Global.swift
    // - GraphCanvasDataLoader+Neighborhood.swift
    // - GraphCanvasDataLoader+Caches.swift
}
