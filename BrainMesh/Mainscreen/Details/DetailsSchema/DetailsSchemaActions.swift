//
//  DetailsSchemaActions.swift
//  BrainMesh
//

import Foundation
import SwiftData
import SwiftUI

enum DetailsSchemaActions {
    static func applyTemplate(_ template: DetailsTemplate, to entity: MetaEntity, modelContext: ModelContext) {
        guard entity.detailFieldsList.isEmpty else { return }

        let definitions = template.fields
        for (idx, def) in definitions.enumerated() {
            let field = MetaDetailFieldDefinition(
                owner: entity,
                name: def.name,
                type: def.type,
                sortIndex: idx,
                unit: def.unit,
                options: def.options,
                isPinned: def.isPinned
            )
            modelContext.insert(field)
            entity.addDetailField(field)
        }

        // Templates sollten das bereits einhalten, aber wir bleiben defensiv.
        DetailsSchemaValidation.enforcePinnedLimitIfNeeded(on: entity)

        try? modelContext.save()
    }

    static func moveFields(in entity: MetaEntity, modelContext: ModelContext, from source: IndexSet, to destination: Int) {
        var working = entity.detailFieldsList
        working.move(fromOffsets: source, toOffset: destination)

        for (idx, field) in working.enumerated() {
            field.sortIndex = idx
        }

        try? modelContext.save()
    }

    static func deleteFields(in entity: MetaEntity, modelContext: ModelContext, at offsets: IndexSet) {
        var working = entity.detailFieldsList
        let toDelete = offsets.compactMap { idx in
            working.indices.contains(idx) ? working[idx] : nil
        }

        for field in toDelete {
            deleteAllValues(modelContext: modelContext, forFieldID: field.id)
            entity.removeDetailField(field)
            modelContext.delete(field)
        }

        working.remove(atOffsets: offsets)

        // Reindex
        for (idx, field) in working.enumerated() {
            field.sortIndex = idx
        }

        try? modelContext.save()
    }

    static func deleteAllValues(modelContext: ModelContext, forFieldID fieldID: UUID) {
        let descriptor = FetchDescriptor<MetaDetailFieldValue>(predicate: #Predicate { $0.fieldID == fieldID })
        if let values = try? modelContext.fetch(descriptor) {
            for v in values {
                modelContext.delete(v)
            }
        }
    }
}
