//
//  GraphStatsJumpActionResolver.swift
//  BrainMesh
//
//  Stats-specific adapters for direct jumps into the graph canvas.
//

import Foundation

nonisolated enum GraphStatsJumpActionResolver {
    static func action(graphID: UUID?, hub: GraphHubItem) -> GraphCanvasJumpActionPlan? {
        GraphCanvasJumpActionResolver.resolve(
            graphID: graphID,
            kind: hub.kind,
            nodeID: hub.id
        )
    }

    static func action(graphID: UUID?, mediaNode: GraphMediaNodeItem) -> GraphCanvasJumpActionPlan? {
        GraphCanvasJumpActionResolver.resolve(
            graphID: graphID,
            kind: mediaNode.kind,
            nodeID: mediaNode.id
        )
    }
}
