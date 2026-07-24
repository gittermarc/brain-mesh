//
//  GraphCanvasDerivedStateInputSnapshot.swift
//  BrainMesh
//

import Foundation

/// Value-only input boundary for `GraphCanvasDerivedStateBuilder`.
///
/// Physics positions, velocities, camera state, MiniMap state, and frame-rendering
/// values deliberately do not belong here because the derived-state builder never
/// reads them.
struct GraphCanvasDerivedStateInputSnapshot: Equatable, Sendable {
    let selection: NodeKey?
    let edges: [GraphEdge]
    let showAllLinksForSelection: Bool
    let degreeCap: Int
    let lensEnabled: Bool
    let lensHideNonRelevant: Bool
    let lensDepth: Int
    let detailsFocusState: GraphDetailsFocusState?
    let detailsFocusPreparedState: GraphDetailsPreparedState
    let labelLookup: [NodeKey: String]

    init(
        selection: NodeKey?,
        edges: [GraphEdge],
        showAllLinksForSelection: Bool,
        degreeCap: Int,
        lensEnabled: Bool,
        lensHideNonRelevant: Bool,
        lensDepth: Int,
        detailsFocusState: GraphDetailsFocusState? = nil,
        detailsFocusPreparedState: GraphDetailsPreparedState = .empty,
        labelLookup: [NodeKey: String]
    ) {
        self.selection = selection
        self.edges = edges
        self.showAllLinksForSelection = showAllLinksForSelection
        self.degreeCap = degreeCap
        self.lensEnabled = lensEnabled
        self.lensHideNonRelevant = lensHideNonRelevant
        self.lensDepth = lensDepth
        self.detailsFocusState = detailsFocusState
        self.detailsFocusPreparedState = detailsFocusPreparedState
        self.labelLookup = labelLookup
    }

    /// Builds the value-only label lookup used by the builder's stable edge sort.
    ///
    /// The render cache is complete on normal loader and expansion paths. The node
    /// labels are retained only as the same defensive fallback used by the former
    /// direct path; the full `GraphNode` list is never stored in this snapshot.
    static func makeLabelLookup(
        nodes: [GraphNode],
        labelCache: [NodeKey: String]
    ) -> [NodeKey: String] {
        guard labelCache.count < nodes.count else {
            return labelCache
        }

        var lookup = labelCache
        lookup.reserveCapacity(nodes.count)
        for node in nodes where lookup[node.key] == nil {
            lookup[node.key] = node.label
        }
        return lookup
    }

    func buildDerivedState() -> GraphCanvasDerivedStateSnapshot {
        GraphCanvasDerivedStateBuilder.build(
            selection: selection,
            edges: edges,
            showAllLinksForSelection: showAllLinksForSelection,
            degreeCap: degreeCap,
            lensEnabled: lensEnabled,
            lensHideNonRelevant: lensHideNonRelevant,
            lensDepth: lensDepth,
            detailsFocusState: detailsFocusState,
            detailsFocusPreparedState: detailsFocusPreparedState,
            labelForKey: { key in
                labelLookup[key, default: ""]
            }
        )
    }
}
