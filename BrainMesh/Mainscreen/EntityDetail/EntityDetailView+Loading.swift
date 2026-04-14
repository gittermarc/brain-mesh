//
//  EntityDetailView+Loading.swift
//  BrainMesh
//
//  Split: reload keys + lightweight preview refresh orchestration
//

import SwiftUI
import SwiftData

extension EntityDetailView {

    var linksTaskKey: String {
        entity.id.uuidString + "|" + (entity.graphID?.uuidString ?? "nil")
    }

    func handleLinkSheetPresentationChanged(_ isPresented: Bool) {
        if !isPresented {
            Task { @MainActor in
                await reloadLinksPreview()
            }
        }
    }

    func handleBulkLinkSheetPresentationChanged(_ isPresented: Bool) {
        if !isPresented {
            Task { @MainActor in
                await reloadLinksPreview()
            }
        }
    }

    @MainActor
    func reloadLinksPreview() async {
        do {
            let snapshot = try NodeLinksQueryBuilder.load(
                context: modelContext,
                kind: .entity,
                id: entity.id,
                graphID: entity.graphID,
                previewLimit: 12
            )

            outgoingLinksPreview = snapshot.outgoingPreview
            incomingLinksPreview = snapshot.incomingPreview
            outgoingLinksCount = snapshot.outgoingCount
            incomingLinksCount = snapshot.incomingCount
        } catch {
            // Keep the last known state. No user-facing alert for preview failures.
        }
    }
}
