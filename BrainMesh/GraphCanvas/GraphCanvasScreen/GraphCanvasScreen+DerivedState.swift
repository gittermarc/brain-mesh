//
//  GraphCanvasScreen+DerivedState.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {
    @MainActor
    func recomputeDerivedState() {
        let derivedState = GraphCanvasDerivedStateBuilder.build(
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
                displayLabel(for: key)
            }
        )

        let cacheMutation = GraphCanvasDerivedStateCacheMutation.diff(
            cachedDrawEdges: drawEdgesCache,
            cachedLens: lensCache,
            cachedPhysicsRelevant: physicsRelevantCache,
            cachedDetailsFocusSummary: detailsFocusSummaryCache,
            cachedDetailsFocusRenderPlan: detailsFocusRenderPlanCache,
            derived: derivedState
        )

        if cacheMutation.drawEdgesChanged {
            drawEdgesCache = derivedState.drawEdges
        }
        if cacheMutation.lensChanged {
            lensCache = derivedState.lens
        }
        if cacheMutation.physicsRelevantChanged {
            physicsRelevantCache = derivedState.physicsRelevant
        }
        if cacheMutation.detailsFocusSummaryChanged {
            detailsFocusSummaryCache = derivedState.detailsFocusSummary
        }
        if cacheMutation.detailsFocusRenderPlanChanged {
            detailsFocusRenderPlanCache = derivedState.detailsFocusRenderPlan
        }
    }
}
