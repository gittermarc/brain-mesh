//
//  GraphCanvasScreen+LoadScheduling.swift
//  BrainMesh
//

import SwiftUI

nonisolated enum GraphCanvasVisibilityPolicy {
    static func simulationIsAllowed(
        isScreenVisible: Bool,
        selectedTab: RootTab,
        isSceneActive: Bool,
        isCoveredBySheet: Bool,
        isLoadingGraph: Bool = false
    ) -> Bool {
        isScreenVisible
            && selectedTab == .graph
            && isSceneActive
            && !isCoveredBySheet
            && !isLoadingGraph
    }
}

extension GraphCanvasScreen {
    var isAnySheetPresented: Bool {
        showGraphPicker || showFocusPicker || showInspector ||
        selectedEntity != nil || selectedAttribute != nil ||
        detailsValueEditRequest != nil || detailsFocusEditorRequest != nil
    }

    var simulationAllowed: Bool {
        GraphCanvasVisibilityPolicy.simulationIsAllowed(
            isScreenVisible: isScreenVisible,
            selectedTab: tabRouter.selection,
            isSceneActive: scenePhase == .active,
            isCoveredBySheet: isAnySheetPresented,
            isLoadingGraph: isLoading
        )
    }

    func handleCanvasTabSelection(_ selection: RootTab) {
        guard selection == .graph else {
            suspendCanvasOwnedWork()
            return
        }

        guard scenePhase == .active else { return }

        if (graphLoadPending || nodes.isEmpty),
           activeGraphID != nil {
            scheduleLoadGraph(resetLayout: true)
        } else if !nodes.isEmpty {
            scheduleDerivedStateUpdate(
                input: derivedStateInputSnapshot,
                reason: .initial
            )
            publishCopilotCanvasContext()
        }
    }

    func suspendCanvasOwnedWork() {
        if loadTask != nil {
            graphLoadPending = true
        }
        loadTask?.cancel()
        loadTask = nil
        miniMapPulseTask?.cancel()
        miniMapPulseTask = nil
        derivedStateScheduler.cancel()
        graphCopilotWorkspaceCoordinator.setCanvasVisible(
            false,
            graphScope: activeGraphID.map {
                GraphScope(graphID: $0)
            }
        )
    }

    // MARK: - Cancellable loading

    @MainActor
    func scheduleLoadGraph(resetLayout: Bool) {
        guard tabRouter.selection == .graph,
              scenePhase == .active else {
            graphLoadPending = true
            return
        }

        loadTask?.cancel()
        let token = UUID()
        currentLoadToken = token
        graphLoadPending = false
        isLoading = true

        loadTask = Task(priority: .utility) {
            await loadGraph(
                loadToken: token,
                resetLayout: resetLayout
            )
            if currentLoadToken == token {
                loadTask = nil
            }
        }
    }
}
