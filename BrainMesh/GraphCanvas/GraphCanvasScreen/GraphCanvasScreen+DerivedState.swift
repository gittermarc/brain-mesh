//
//  GraphCanvasScreen+DerivedState.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {
    var derivedStateInputSnapshot: GraphCanvasDerivedStateInputSnapshot {
        GraphCanvasDerivedStateInputSnapshot(
            selection: selection,
            edges: edges,
            showAllLinksForSelection: showAllLinksForSelection,
            degreeCap: degreeCap,
            lensEnabled: lensEnabled,
            lensHideNonRelevant: lensHideNonRelevant,
            lensDepth: lensDepth,
            detailsFocusState: detailsFocusState,
            detailsFocusPreparedState: detailsFocusPreparedState,
            labelLookup: GraphCanvasDerivedStateInputSnapshot.makeLabelLookup(
                nodes: nodes,
                labelCache: labelCache
            )
        )
    }

    @MainActor
    func scheduleDerivedStateUpdate(
        input: GraphCanvasDerivedStateInputSnapshot,
        reason: GraphCanvasDerivedStateTriggerReason
    ) {
        guard tabRouter.selection == .graph,
              scenePhase == .active else {
            return
        }
        derivedStateScheduler.schedule(
            input: input,
            graphID: activeGraphID,
            reason: reason,
            commit: { derivedState in
                commitDerivedState(derivedState)
            }
        )
    }

    @MainActor
    func resumeDerivedStateAfterGraphLoad() {
        guard tabRouter.selection == .graph,
              scenePhase == .active else {
            return
        }
        derivedStateScheduler.resumeAfterGraphTransition(
            input: derivedStateInputSnapshot,
            graphID: activeGraphID,
            reason: .graphLoad,
            commit: { derivedState in
                commitDerivedState(derivedState)
            }
        )
    }

    @MainActor
    private func commitDerivedState(
        _ derivedState: GraphCanvasDerivedStateSnapshot
    ) {
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
