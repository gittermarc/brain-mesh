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
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return }

        let current = entity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == current { return }

        entity.name = cleaned
        try modelContext.save()

        await NodeRenameService.shared.relabelLinksAfterEntityRename(
            entityID: entity.id,
            graphID: entity.graphID
        )
    }

    func deleteEntity() {
        AttachmentCleanup.deleteAttachments(ownerKind: .entity, ownerID: entity.id, in: modelContext)
        for attr in entity.attributesList {
            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
        }

        LinkCleanup.deleteLinks(referencing: .entity, id: entity.id, graphID: entity.graphID, in: modelContext)

        modelContext.delete(entity)
        try? modelContext.save()
    }
}
