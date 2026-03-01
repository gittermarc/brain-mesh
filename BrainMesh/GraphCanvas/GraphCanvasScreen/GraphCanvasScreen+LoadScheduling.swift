//
//  GraphCanvasScreen+LoadScheduling.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {
    var isAnySheetPresented: Bool {
        showGraphPicker || showFocusPicker || showInspector ||
        selectedEntity != nil || selectedAttribute != nil ||
        detailsValueEditRequest != nil
    }

    var simulationAllowed: Bool {
        // We only want the 30 FPS timer while the canvas is actually on-screen and the app is active.
        // Also pause while any sheet covers the canvas.
        isScreenVisible && scenePhase == .active && !isAnySheetPresented
    }

    // MARK: - Cancellable loading
    
    func scheduleLoadGraph(resetLayout: Bool) {
        Task { @MainActor in
            loadTask?.cancel()
    
            let token = UUID()
            currentLoadToken = token
    
            loadTask = Task(priority: .utility) {
                await loadGraph(loadToken: token, resetLayout: resetLayout)
            }
        }
    }
}
