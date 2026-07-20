//
//  EntityDetailView+Actions.swift
//  BrainMesh
//
//  Split: entity-scoped rename and delete actions
//

import SwiftUI
import SwiftData

extension EntityDetailView {

    @MainActor
    func renameEntity(to newName: String) async throws {
        _ = try await NodeRenameService.renameEntity(
            entity,
            to: newName,
            in: modelContext
        )
    }

    func deleteEntity() {
        Task { @MainActor in
            do {
                try await GraphNodeDeletionService.deleteEntity(
                    entity,
                    in: modelContext
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
