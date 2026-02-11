//
//  GraphDeletionService.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import Foundation
import SwiftData

@MainActor
enum GraphDeletionService {

    struct Result {
        let newActiveGraphID: UUID?
    }

    /// Deletes a graph completely, including its content and local cached images.
    ///
    /// - Returns: The new active graph id if the deleted graph was active.
    static func deleteGraphCompletely(
        graphToDelete: MetaGraph,
        currentActiveGraphID: UUID?,
        graphs _: [MetaGraph],
        uniqueGraphs: [MetaGraph],
        modelContext: ModelContext,
        graphLock: GraphLockCoordinator
    ) async throws -> Result {

        let gid = graphToDelete.id

        // IMPORTANT: There can be multiple MetaGraph records with the same `id` (UUID) in the store.
        // We treat them as duplicates of the same user-visible graph and delete them all.
        let graphFD = FetchDescriptor<MetaGraph>(predicate: #Predicate { g in
            g.id == gid
        })
        let graphRecordsToDelete = (try? modelContext.fetch(graphFD)) ?? [graphToDelete]

        // 1) Determine a fallback active graph if we delete the currently active one.
        // Important: do not save early here, to avoid intermediate List updates while deleting.
        let deletingIsActive = (currentActiveGraphID == gid)

        var newActive: UUID? = nil
        if deletingIsActive {
            let remaining = uniqueGraphs
                .filter { $0.id != gid }
                .sorted { $0.createdAt < $1.createdAt }

            if let first = remaining.first {
                newActive = first.id
            } else {
                // Last graph -> create a new default graph so the app is never "without a graph".
                // Persist together with the delete in a single save.
                let fresh = MetaGraph(name: "Default")
                modelContext.insert(fresh)
                newActive = fresh.id
            }
        }

        // Lock state for the graph we are deleting.
        graphLock.lock(graphID: gid)

        // 2) Fetch affected objects.
        let entsFD = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { e in e.graphID == gid }
        )
        let entities = try modelContext.fetch(entsFD)

        let linksFD = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in l.graphID == gid }
        )
        let links = try modelContext.fetch(linksFD)

        let orphansFD = FetchDescriptor<MetaAttribute>(
            predicate: #Predicate { a in a.graphID == gid && a.owner == nil }
        )
        let orphans = try modelContext.fetch(orphansFD)

        // 3) Collect local cached image paths before deleting objects.
        var imagePaths = Set<String>()

        for e in entities {
            if let p = e.imagePath, !p.isEmpty { imagePaths.insert(p) }
            for a in e.attributesList {
                if let p = a.imagePath, !p.isEmpty { imagePaths.insert(p) }
            }
        }

        for a in orphans {
            if let p = a.imagePath, !p.isEmpty { imagePaths.insert(p) }
        }

        // 3b) Cleanup attachments (records + local cache).
        // 1) Normal case: graphID is set.
        AttachmentCleanup.deleteAttachments(graphID: gid, in: modelContext)

        // 2) Defensive: graphID == nil, but owner is being deleted.
        for e in entities {
            AttachmentCleanup.deleteAttachments(ownerKind: .entity, ownerID: e.id, graphID: nil, in: modelContext)
            for a in e.attributesList {
                AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: a.id, graphID: nil, in: modelContext)
            }
        }
        for a in orphans {
            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: a.id, graphID: nil, in: modelContext)
        }

        // 4) Delete (order: Links -> Orphans -> Entities -> Graph(s))
        for l in links { modelContext.delete(l) }
        for a in orphans { modelContext.delete(a) }
        for e in entities { modelContext.delete(e) } // cascade removes owned attributes

        // Delete all duplicate graph records for this UUID.
        for g in graphRecordsToDelete {
            modelContext.delete(g)
        }

        try modelContext.save()

        // 5) Remove local cached files (device only).
        for p in imagePaths {
            ImageStore.delete(path: p)
        }

        return Result(newActiveGraphID: newActive)
    }
}
