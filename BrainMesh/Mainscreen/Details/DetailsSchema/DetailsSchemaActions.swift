//
//  DetailsSchemaActions.swift
//  BrainMesh
//

import Foundation
import SwiftData
import SwiftUI

enum DetailsSchemaActions {

    // MARK: - Apply templates

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
        DetailsSchemaPinning.enforcePinnedLimitIfNeeded(on: entity)

        try? modelContext.save()
    }

    static func applyTemplate(_ template: MetaDetailsTemplate, to entity: MetaEntity, modelContext: ModelContext) {
        guard entity.detailFieldsList.isEmpty else { return }

        let definitions = template.fields
        for (idx, def) in definitions.enumerated() {
            let type = DetailFieldType(rawValue: def.typeRaw) ?? .singleLineText
            let field = MetaDetailFieldDefinition(
                owner: entity,
                name: def.name,
                type: type,
                sortIndex: idx,
                unit: def.unit,
                options: def.options,
                isPinned: def.isPinned
            )
            modelContext.insert(field)
            entity.addDetailField(field)
        }

        DetailsSchemaPinning.enforcePinnedLimitIfNeeded(on: entity)

        try? modelContext.save()
    }

    // MARK: - Save template

    static func saveTemplate(from entity: MetaEntity, name rawName: String, modelContext: ModelContext) {
        guard !entity.detailFieldsList.isEmpty else { return }

        let cleaned = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let graphID = entity.graphID
        let finalName = makeUniqueTemplateName(baseName: cleaned, graphID: graphID, modelContext: modelContext)

        let fields: [MetaDetailsTemplate.FieldDef] = entity.detailFieldsList.map { field in
            MetaDetailsTemplate.FieldDef(
                name: field.name,
                typeRaw: field.typeRaw,
                unit: field.unit,
                options: field.options,
                isPinned: field.isPinned
            )
        }

        let template = MetaDetailsTemplate(name: finalName, graphID: graphID, fields: fields)
        modelContext.insert(template)
        try? modelContext.save()
    }

    private static func makeUniqueTemplateName(baseName: String, graphID: UUID?, modelContext: ModelContext) -> String {
        let predicate: Predicate<MetaDetailsTemplate>
        if let graphID {
            predicate = #Predicate { $0.graphID == graphID }
        } else {
            predicate = #Predicate { $0.graphID == nil }
        }

        let descriptor = FetchDescriptor<MetaDetailsTemplate>(predicate: predicate)
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingFolded = Set(existing.map { $0.nameFolded })

        var candidate = baseName
        var counter = 2
        while existingFolded.contains(BMSearch.fold(candidate)) {
            candidate = "\(baseName) (\(counter))"
            counter += 1
        }

        return candidate
    }

    // MARK: - Field operations

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
