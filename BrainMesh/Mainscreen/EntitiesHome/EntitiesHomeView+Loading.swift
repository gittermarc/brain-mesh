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

    @MainActor func loadRecentNodesIfNeeded() async {
        guard shouldShowCockpit else {
            cockpitSnapshot = .empty
            isRecentNodesLoading = false
            recentNodesErrorMessage = nil
            return
        }
        guard let graphID = activeGraphID else {
            cockpitSnapshot = .empty
            isRecentNodesLoading = false
            recentNodesErrorMessage = nil
            return
        }

        prepareCockpitSnapshot(for: graphID)
        let recentItems = recentNodeStore.items
        isRecentNodesLoading = true
        recentNodesErrorMessage = nil

        do {
            let recentNodes = try await EntitiesHomeRecentNodesLoader.shared.load(
                graphID: graphID,
                recentItems: recentItems,
                limit: 8
            )
            guard Task.isCancelled == false,
                  activeGraphID == graphID,
                  shouldShowCockpit,
                  let updatedSnapshot = cockpitSnapshot.replacingRecentNodes(
                    recentNodes,
                    for: graphID
                  )
            else {
                return
            }

            cockpitSnapshot = updatedSnapshot
            isRecentNodesLoading = false
            recentNodesErrorMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard Task.isCancelled == false,
                  activeGraphID == graphID
            else {
                return
            }
            isRecentNodesLoading = false
            recentNodesErrorMessage =
                "Die zuletzt geöffneten Knoten konnten gerade nicht geladen werden."
        }
    }

    @MainActor func loadHealthIfNeeded() async {
        guard shouldShowCockpit else {
            cockpitSnapshot = .empty
            isHealthLoading = false
            healthErrorMessage = nil
            return
        }
        guard let graphID = activeGraphID else {
            cockpitSnapshot = .empty
            isHealthLoading = false
            healthErrorMessage = nil
            return
        }

        prepareCockpitSnapshot(for: graphID)
        isHealthLoading = true
        healthErrorMessage = nil

        do {
            let health =
                try await EntitiesHomeHealthSummaryProvider.shared.summary(
                    for: graphID
                )
            guard Task.isCancelled == false,
                  activeGraphID == graphID,
                  shouldShowCockpit,
                  let updatedSnapshot =
                    cockpitSnapshot.replacingHealth(health)
            else {
                return
            }

            cockpitSnapshot = updatedSnapshot
            isHealthLoading = false
            healthErrorMessage = nil
        } catch is CancellationError {
            guard Task.isCancelled == false,
                  activeGraphID == graphID,
                  shouldShowCockpit
            else {
                return
            }
            healthReloadRevision &+= 1
            return
        } catch {
            guard Task.isCancelled == false,
                  activeGraphID == graphID
            else {
                return
            }
            isHealthLoading = false
            healthErrorMessage =
                "Die Graph-Hinweise konnten gerade nicht geladen werden. Die Entitätenliste bleibt nutzbar."
        }
    }

    @MainActor func observeHealthInvalidationsIfNeeded() async {
        guard shouldShowCockpit, let graphID = activeGraphID else {
            return
        }

        async let healthObservation: Void =
            observeHealthProviderInvalidations(for: graphID)
        async let recentObservation: Void =
            observeRecentNodePresentationInvalidations(for: graphID)
        _ = await (healthObservation, recentObservation)
    }

    @MainActor private func observeHealthProviderInvalidations(
        for graphID: UUID
    ) async {
        let stream =
            await EntitiesHomeHealthSummaryProvider.shared.invalidations()
        for await invalidatedGraphID in stream {
            guard Task.isCancelled == false else {
                return
            }
            guard invalidatedGraphID == graphID,
                  activeGraphID == graphID
            else {
                continue
            }
            healthReloadRevision &+= 1
        }
    }

    @MainActor private func observeRecentNodePresentationInvalidations(
        for graphID: UUID
    ) async {
        let stream = await GraphMutationEventBus.shared.mutationBatches(
            bufferingPolicy: .unbounded
        )
        for await delivery in stream {
            guard Task.isCancelled == false else {
                return
            }
            let batch = delivery.batch
            guard batch.graphID == graphID,
                  Self.mutationCanChangeRecentNodePresentation(batch)
            else {
                continue
            }

            guard activeGraphID == graphID else {
                return
            }
            recentNodesReloadRevision &+= 1
        }
    }

    @MainActor private func prepareCockpitSnapshot(for graphID: UUID) {
        if cockpitSnapshot.graphID != graphID {
            cockpitSnapshot = .empty(graphID: graphID)
            recentNodesErrorMessage = nil
            healthErrorMessage = nil
        }
    }

    nonisolated private static func mutationCanChangeRecentNodePresentation(
        _ batch: GraphMutationBatch
    ) -> Bool {
        batch.events.contains { event in
            switch event.kind {
            case .entityUpdated, .entityDeleted,
                 .attributeUpdated, .attributeDeleted,
                 .graphImported, .graphReplaced, .graphDeleted,
                 .graphRequiresFullRebuild:
                return true
            case .entityCreated, .attributeCreated,
                 .linkCreated, .linkUpdated, .linkDeleted,
                 .detailSchemaChanged,
                 .detailValueChanged, .detailValueDeleted,
                 .detailTemplateCreated,
                 .attachmentCreated, .attachmentUpdated, .attachmentDeleted,
                 .graphCreated, .graphUpdated:
                return false
            }
        }
    }
}
