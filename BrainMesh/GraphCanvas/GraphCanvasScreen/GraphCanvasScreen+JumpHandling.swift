//
//  GraphCanvasScreen+JumpHandling.swift
//  BrainMesh
//

import SwiftUI
import SwiftData

extension GraphCanvasScreen {
    // MARK: - Graph Jump Handling (PR 3)
    
    @MainActor
    func handlePendingJumpIfNeeded() {
        guard let jump = graphJump.pendingJump else { return }
    
        // Fast path: already in the right graph and node is present + positioned.
        if activeGraphID == jump.graphID,
           nodes.contains(where: { $0.key == jump.nodeKey }),
           positions[jump.nodeKey] != nil {
            applyJumpImmediately(jump)
            _ = graphJump.consumeJump()
            clearStagedGraphJump()
            return
        }
    
        // Stage the jump so the next load can select + center after layout.
        stageGraphJump(jump)
    
        // Ensure we are on the right graph. The `.onChange(of: activeGraphIDString)` hook will kick off a reload.
        if activeGraphIDString != jump.graphID.uuidString {
            activeGraphIDString = jump.graphID.uuidString
            return
        }
    
        // Safe path: prepare neighborhood state so the node is guaranteed to be in the snapshot.
        prepareGraphStateForJump(jump)
        scheduleLoadGraph(resetLayout: true)
    }
    
    @MainActor
    private func applyJumpImmediately(_ jump: GraphJump) {
        selection = jump.nodeKey
        if jump.centerOnArrival {
            cameraCommand = CameraCommand(kind: .center(jump.nodeKey))
        }
    }
    
    @MainActor
    func prepareGraphStateForJump(_ jump: GraphJump) {
        switch jump.nodeKey.kind {
        case .entity:
            if let e = fetchEntity(id: jump.nodeKey.uuid) {
                if focusEntity?.id != e.id {
                    focusEntity = e
                    hops = 1
                }
            }
    
        case .attribute:
            // For attributes we load the neighborhood of the owning entity and ensure attributes are included.
            showAttributes = true
    
            if let a = fetchAttribute(id: jump.nodeKey.uuid), let owner = a.owner {
                if focusEntity?.id != owner.id {
                    focusEntity = owner
                    hops = 1
                }
            }
        }
    }
}
