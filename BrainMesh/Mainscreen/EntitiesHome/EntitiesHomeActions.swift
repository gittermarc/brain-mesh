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
        deleteEntities(at: offsets, from: rows)
    }

    func deleteEntities(at offsets: IndexSet, from sourceRows: [EntitiesHomeRow]) {
        let idsToDelete: [UUID] = offsets.compactMap { index in
            guard sourceRows.indices.contains(index) else { return nil }
            return sourceRows[index].id
        }
        deleteEntityIDs(idsToDelete)
    }

    func deleteEntityIDs(_ ids: [UUID]) {
        let requestedIDs = Set(ids)
        guard !requestedIDs.isEmpty else { return }
        guard let graphID = activeGraphID else {
            deletionErrorMessage = GraphNodeDeletionService.DeletionError.missingGraphScope.localizedDescription
            return
        }

        do {
            let gid = graphID
            let descriptor = FetchDescriptor<MetaEntity>(
                predicate: #Predicate { entity in
                    entity.graphID == gid
                }
            )
            let entitiesToDelete = try modelContext.fetch(descriptor).filter { entity in
                requestedIDs.contains(entity.id)
            }

            guard !entitiesToDelete.isEmpty else {
                refreshAfterDeletion()
                return
            }

            try GraphNodeDeletionService.deleteEntities(
                entitiesToDelete,
                in: modelContext
            )

            rows.removeAll { requestedIDs.contains($0.id) }
            refreshAfterDeletion()
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }

    private func refreshAfterDeletion() {
        Task {
            await EntitiesHomeLoader.shared.invalidateCache(for: activeGraphID)
            await reload(forFolded: BMSearch.fold(searchText))
            await loadCockpitIfNeeded()
        }
    }
}
