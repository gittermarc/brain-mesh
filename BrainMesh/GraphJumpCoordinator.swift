//
//  GraphJumpCoordinator.swift
//  BrainMesh
//
//  Stores a pending "jump" request into the Graph tab.
//  The actual consumption happens later in GraphCanvasScreen (PR 3).
//

import Combine
import Foundation

/// Payload describing a pending "open graph and select node" request.
struct GraphJump: Identifiable, Hashable, Sendable {
    let id: UUID
    let requestedAt: Date

    let graphID: UUID
    let nodeKey: NodeKey
    let centerOnArrival: Bool

    init(graphID: UUID, nodeKey: NodeKey, centerOnArrival: Bool = true) {
        self.id = UUID()
        self.requestedAt = Date()
        self.graphID = graphID
        self.nodeKey = nodeKey
        self.centerOnArrival = centerOnArrival
    }
}

/// Coordinates cross-screen jumps into `GraphCanvasScreen`.
///
/// The jump is stored until a consumer explicitly calls `consumeJump()`.
///
/// Note: We intentionally do **not** mark the whole type `@MainActor`.
/// In strict concurrency builds this can break `ObservableObject` conformance.
/// Instead, we keep mutations on the main actor via `@MainActor` methods.
final class GraphJumpCoordinator: ObservableObject {
    @Published private(set) var pendingJump: GraphJump? = nil

    @MainActor
    func requestJump(to nodeKey: NodeKey, in graphID: UUID, centerOnArrival: Bool = true) {
        pendingJump = GraphJump(graphID: graphID, nodeKey: nodeKey, centerOnArrival: centerOnArrival)
    }

    @MainActor
    func clear() {
        pendingJump = nil
    }

    /// Returns and clears the currently pending jump.
    @MainActor
    func consumeJump() -> GraphJump? {
        let j = pendingJump
        pendingJump = nil
        return j
    }
}
