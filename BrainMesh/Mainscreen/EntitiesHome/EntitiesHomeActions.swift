//
//  EntitiesHomeActions.swift
//  BrainMesh
//
//  Created by Marc Fechner on 20.02.26.
//

import SwiftUI
import SwiftData

extension EntitiesHomeView {
    func deleteEntities(at offsets: IndexSet) {
        let idsToDelete: [UUID] = offsets.compactMap { idx in
            guard rows.indices.contains(idx) else { return nil }
            return rows[idx].id
        }
        deleteEntityIDs(idsToDelete)
    }

    func deleteEntityIDs(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }

        let entitiesToDelete: [MetaEntity] = ids.compactMap { fetchEntity(by: $0) }
        if entitiesToDelete.isEmpty { return }

        for entity in entitiesToDelete {
            // Attachments are not part of the graph rendering; they live only on detail level.
            // They also do not cascade automatically, so we explicitly clean them up.
            AttachmentCleanup.deleteAttachments(ownerKind: .entity, ownerID: entity.id, in: modelContext)
            for attr in entity.attributesList {
                AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            }

            LinkCleanup.deleteLinks(referencing: .entity, id: entity.id, graphID: entity.graphID ?? activeGraphID, in: modelContext)
            modelContext.delete(entity)
        }

        // Update local list immediately and then re-fetch to stay in sync with SwiftData.
        rows.removeAll { r in ids.contains(r.id) }
        Task {
            await EntitiesHomeLoader.shared.invalidateCache(for: activeGraphID)
            await reload(forFolded: BMSearch.fold(searchText))
        }
    }

    private func fetchEntity(by id: UUID) -> MetaEntity? {
        var fd = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { e in
                e.id == id
            }
        )
        fd.fetchLimit = 1
        return try? modelContext.fetch(fd).first
    }
}
