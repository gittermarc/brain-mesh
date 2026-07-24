//
//  EntityDetailView+Loading.swift
//  BrainMesh
//
//  Split: reload keys + lightweight preview refresh orchestration
//

import SwiftUI

extension EntityDetailView {

    var linksPreviewLoadIdentity: NodeConnectionsPreviewLoadIdentity {
        NodeConnectionsPreviewLoadIdentity(
            ownerKind: .entity,
            ownerID: entity.id,
            graphID: entity.graphID
        )
    }

    func handleLinkSheetPresentationChanged(_ isPresented: Bool) {
        guard linksPreviewLoadTriggerPolicy
            .registerAddLinkPresentation(isPresented)
        else {
            return
        }
        Task { @MainActor in
            await reloadLinksPreview()
        }
    }

    func handleBulkLinkSheetPresentationChanged(_ isPresented: Bool) {
        guard linksPreviewLoadTriggerPolicy
            .registerBulkLinkPresentation(isPresented)
        else {
            return
        }
        Task { @MainActor in
            await reloadLinksPreview()
        }
    }

    @MainActor
    func reloadLinksPreview() async {
        let identity = linksPreviewLoadIdentity
        let token = linksPreviewLoadTriggerPolicy.beginLoad(for: identity)

        guard let graphID = identity.graphID else {
            if linksPreviewLoadTriggerPolicy.accepts(
                token,
                currentIdentity: linksPreviewLoadIdentity
            ) {
                linksPreview = .empty
            }
            return
        }

        do {
            let snapshot =
                try await BMNodeConnectionsPreviewLoadInstrumentation
                .measure(
                    ownerKind: .entity,
                    counts: { snapshot in
                        (
                            outgoing: snapshot.outgoingCount,
                            incoming: snapshot.incomingCount
                        )
                    },
                    operation: {
                        try await NodeConnectionsLoader.shared
                            .loadPreviewSnapshot(
                                ownerKind: .entity,
                                ownerID: identity.ownerID,
                                graphID: graphID,
                                previewLimit: 12
                            )
                    }
                )

            guard linksPreviewLoadTriggerPolicy.accepts(
                token,
                currentIdentity: linksPreviewLoadIdentity
            ) else {
                return
            }
            linksPreview = snapshot
        } catch is CancellationError {
            // Task replacement and navigation cancellation are expected.
        } catch {
            // Keep the last known value-only state. Preview failures are not user-facing.
        }
    }
}
