//
//  GraphCanvasJumpActionResolver.swift
//  BrainMesh
//
//  Pure decision model for opening the graph tab and requesting a focused canvas jump.
//

import Foundation

nonisolated struct GraphCanvasJumpActionPlan: Equatable, Sendable {
    let tab: RootTab
    let graphID: UUID
    let nodeKey: NodeKey
    let centerOnArrival: Bool

    init(
        tab: RootTab = .graph,
        graphID: UUID,
        nodeKey: NodeKey,
        centerOnArrival: Bool = true
    ) {
        self.tab = tab
        self.graphID = graphID
        self.nodeKey = nodeKey
        self.centerOnArrival = centerOnArrival
    }
}

nonisolated enum GraphCanvasJumpActionResolver {
    static func resolve(
        graphID: UUID?,
        kind: NodeKind,
        nodeID: UUID?,
        centerOnArrival: Bool = true
    ) -> GraphCanvasJumpActionPlan? {
        guard let graphID, let nodeID else { return nil }
        return GraphCanvasJumpActionPlan(
            graphID: graphID,
            nodeKey: NodeKey(kind: kind, uuid: nodeID),
            centerOnArrival: centerOnArrival
        )
    }

    static func resolve(
        graphID: UUID?,
        nodeKindRaw: Int?,
        nodeID: UUID?,
        centerOnArrival: Bool = true
    ) -> GraphCanvasJumpActionPlan? {
        guard let nodeKindRaw, let kind = NodeKind(rawValue: nodeKindRaw) else { return nil }
        return resolve(
            graphID: graphID,
            kind: kind,
            nodeID: nodeID,
            centerOnArrival: centerOnArrival
        )
    }

    static func resolve(
        graphID: UUID?,
        nodeKey: NodeKey?,
        centerOnArrival: Bool = true
    ) -> GraphCanvasJumpActionPlan? {
        guard let graphID, let nodeKey else { return nil }
        return GraphCanvasJumpActionPlan(
            graphID: graphID,
            nodeKey: nodeKey,
            centerOnArrival: centerOnArrival
        )
    }
}
