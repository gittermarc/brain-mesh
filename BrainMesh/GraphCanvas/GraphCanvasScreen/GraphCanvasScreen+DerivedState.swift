//
//  GraphCanvasScreen+DerivedState.swift
//  BrainMesh
//

import SwiftUI

extension GraphCanvasScreen {
    @MainActor
    func recomputeDerivedState() {
        let newDrawEdges = edgesForDisplay()
    
        // ✅ Auto-Spotlight (erzwingt hideNonRelevant=true, depth=1 sobald selection != nil)
        let autoSpotlight = (selection != nil)
        let effectiveLensEnabled = autoSpotlight ? true : lensEnabled
        let effectiveLensHide = autoSpotlight ? true : lensHideNonRelevant
        let effectiveLensDepth = autoSpotlight ? 1 : lensDepth
    
        let newLens = LensContext.build(
            enabled: effectiveLensEnabled,
            hideNonRelevant: effectiveLensHide,
            depth: effectiveLensDepth,
            selection: selection,
            edges: newDrawEdges
        )
    
        // ✅ Physik-Relevanz: im Spotlight nur auf Selection+Nachbarn simulieren
        let newPhysicsRelevant: Set<NodeKey>? = (autoSpotlight ? newLens.relevant : nil)
    
        if drawEdgesCache != newDrawEdges { drawEdgesCache = newDrawEdges }
        if lensCache != newLens { lensCache = newLens }
        if physicsRelevantCache != newPhysicsRelevant { physicsRelevantCache = newPhysicsRelevant }
    }
}
