//
//  GraphCanvasScreen+StaticRenderSnapshot.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {
    @MainActor
    func refreshStaticRenderSnapshot(
        nodes: [GraphNode],
        directedEdgeNotes: [DirectedEdgeKey: String]
    ) {
        let input = GraphCanvasStaticRenderInput(
            nodes: nodes,
            directedEdgeNotes: directedEdgeNotes
        )
        let resolution = staticRenderSnapshotCache.request(input: input)

        if resolution.didRebuild {
            staticRenderSnapshot = resolution.snapshot
        }
    }
}
