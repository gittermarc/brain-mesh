//
//  EntitiesHomeView+Loading.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI

extension EntitiesHomeView {
    var debounceNanos: UInt64 { 250_000_000 }

    var taskToken: String {
        // Triggers reload when either the active graph, the search term or relevant computed-data flags change.
        let includeAttrs = (resolvedEntitiesHomeAppearance.showAttributeCount || sortOption.needsAttributeCounts) ? "1" : "0"
        let includeLinks = (resolvedEntitiesHomeAppearance.showLinkCount || sortOption.needsLinkCounts) ? "1" : "0"
        let includeNotes = (resolvedEntitiesHomeAppearance.showNotesPreview || displaySettings.entitiesHome.metaLine == .notesPreview) ? "1" : "0"
        return "\(activeGraphIDString)|\(searchText)|\(includeAttrs)|\(includeLinks)|\(includeNotes)"
    }

    @MainActor func reload(forFolded folded: String) async {
        do {
            let includeAttributeCounts = (resolvedEntitiesHomeAppearance.showAttributeCount || sortOption.needsAttributeCounts)
            let includeLinkCounts = (resolvedEntitiesHomeAppearance.showLinkCount || sortOption.needsLinkCounts)
            let includeNotesPreview = (resolvedEntitiesHomeAppearance.showNotesPreview || displaySettings.entitiesHome.metaLine == .notesPreview)

            let snapshot = try await EntitiesHomeLoader.shared.loadSnapshot(
                activeGraphID: activeGraphID,
                foldedSearch: folded,
                includeAttributeCounts: includeAttributeCounts,
                includeLinkCounts: includeLinkCounts,
                includeNotesPreview: includeNotesPreview
            )
            rows = sortOption.apply(to: snapshot.rows)
            isLoading = false
            loadError = nil
        } catch is CancellationError {
            // When typing quickly or switching graphs, the previous task gets cancelled.
            // We deliberately don't touch UI state here to avoid flicker or transient error screens.
            return
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }
}
