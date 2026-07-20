//
//  DetailsSchemaActions.swift
//  BrainMesh
//

import Foundation
import SwiftData
import SwiftUI

@MainActor
enum DetailsSchemaActions {
    enum ActionError: LocalizedError {
        case missingGraphScope
        case fieldNotFound

        var errorDescription: String? {
            switch self {
            case .missingGraphScope:
                return "Für diese Details ist kein Graph zugeordnet."
            case .fieldNotFound:
                return "Das Detailfeld wurde nicht gefunden."
            }
        }
    }

    private struct NewFieldSpec {
        let name: String
        let type: DetailFieldType
        let unit: String?
        let options: [String]
        let isPinned: Bool
    }

    // MARK: - Apply templates

    @discardableResult
    static func applyTemplate(
        _ template: DetailsTemplate,
        to entity: MetaEntity,
        modelContext: ModelContext
    ) async throws -> Bool {
        let specs = template.fields.map { definition in
            NewFieldSpec(
                name: definition.name,
                type: definition.type,
                unit: definition.unit,
                options: definition.options,
                isPinned: definition.isPinned
            )
        }
        return try await applyFieldSpecs(
            specs,
            to: entity,
            modelContext: modelContext
        )
    }

    @discardableResult
    static func applyTemplate(
        _ template: MetaDetailsTemplate,
        to entity: MetaEntity,
        modelContext: ModelContext
    ) async throws -> Bool {
        let specs = template.fields.map { definition in
            NewFieldSpec(
                name: definition.name,
                type: DetailFieldType(rawValue: definition.typeRaw) ?? .singleLineText,
                unit: definition.unit,
                options: definition.options,
                isPinned: definition.isPinned
            )
        }
        return try await applyFieldSpecs(
            specs,
            to: entity,
            modelContext: modelContext
        )
    }

    // MARK: - Save template

    /// Saves a reusable template record. This does not change an entity's active detail schema and
    /// therefore intentionally does not publish a graph mutation event.
    @discardableResult
    static func saveTemplate(
        from entity: MetaEntity,
        name rawName: String,
        modelContext: ModelContext
    ) throws -> Bool {
        guard !entity.detailFieldsList.isEmpty else { return false }

        let cleaned = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }

        try Task.checkCancellation()

        let graphID = entity.graphID
        let finalName = try makeUniqueTemplateName(
            baseName: cleaned,
            graphID: graphID,
            modelContext: modelContext
        )

        let fields: [MetaDetailsTemplate.FieldDef] = entity.detailFieldsList.map { field in
            MetaDetailsTemplate.FieldDef(
                name: field.name,
                typeRaw: field.typeRaw,
                unit: field.unit,
                options: field.options,
                isPinned: field.isPinned
            )
        }

        let template = MetaDetailsTemplate(
            name: finalName,
            graphID: graphID,
            fields: fields
        )
        modelContext.insert(template)

        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: - Field operations

    @discardableResult
    static func addField(
        _ field: MetaDetailFieldDefinition,
        to entity: MetaEntity,
        modelContext: ModelContext
    ) async throws -> Bool {
        guard let graphID = entity.graphID else {
            throw ActionError.missingGraphScope
        }

        modelContext.insert(field)
        entity.addDetailField(field)

        do {
            let batch = try GraphMutationBatchFactory.detailSchemaChanged(
                graphID: graphID,
                ownerEntityID: entity.id,
                definitionIDs: [field.id]
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    static func commitFieldUpdate(
        _ field: MetaDetailFieldDefinition,
        in entity: MetaEntity,
        modelContext: ModelContext
    ) async throws -> Bool {
        guard let graphID = entity.graphID else {
            throw ActionError.missingGraphScope
        }

        do {
            let batch = try GraphMutationBatchFactory.detailSchemaChanged(
                graphID: graphID,
                ownerEntityID: entity.id,
                definitionIDs: [field.id]
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    static func moveFields(
        in entity: MetaEntity,
        modelContext: ModelContext,
        from source: IndexSet,
        to destination: Int
    ) async throws -> Bool {
        let original = entity.detailFieldsList
        guard !source.isEmpty else { return false }
        guard source.allSatisfy({ original.indices.contains($0) }) else { return false }
        guard destination >= 0, destination <= original.count else { return false }
        guard let graphID = entity.graphID else {
            throw ActionError.missingGraphScope
        }

        var working = original
        working.move(fromOffsets: source, toOffset: destination)
        guard working.map(\.id) != original.map(\.id) else { return false }

        let originalIndices = Dictionary(
            uniqueKeysWithValues: original.enumerated().map { index, field in
                (field.id, index)
            }
        )
        var affectedIDs: [UUID] = []
        for (index, field) in working.enumerated() {
            if originalIndices[field.id] != index {
                affectedIDs.append(field.id)
                field.sortIndex = index
            }
        }
        guard !affectedIDs.isEmpty else { return false }

        do {
            let batch = try GraphMutationBatchFactory.detailSchemaChanged(
                graphID: graphID,
                ownerEntityID: entity.id,
                definitionIDs: affectedIDs
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    @discardableResult
    static func deleteFields(
        in entity: MetaEntity,
        modelContext: ModelContext,
        at offsets: IndexSet
    ) async throws -> Bool {
        let original = entity.detailFieldsList
        let fieldsToDelete = offsets.compactMap { index in
            original.indices.contains(index) ? original[index] : nil
        }
        return try await deleteFields(
            fieldsToDelete,
            from: entity,
            modelContext: modelContext
        )
    }

    @discardableResult
    static func deleteField(
        _ field: MetaDetailFieldDefinition,
        from entity: MetaEntity,
        modelContext: ModelContext
    ) async throws -> Bool {
        guard entity.detailFieldsList.contains(where: { $0.id == field.id }) else {
            throw ActionError.fieldNotFound
        }
        return try await deleteFields(
            [field],
            from: entity,
            modelContext: modelContext
        )
    }

    private static func applyFieldSpecs(
        _ specs: [NewFieldSpec],
        to entity: MetaEntity,
        modelContext: ModelContext
    ) async throws -> Bool {
        guard entity.detailFieldsList.isEmpty else { return false }
        guard !specs.isEmpty else { return false }
        guard let graphID = entity.graphID else {
            throw ActionError.missingGraphScope
        }

        try Task.checkCancellation()

        var fields: [MetaDetailFieldDefinition] = []
        fields.reserveCapacity(specs.count)
        for (index, spec) in specs.enumerated() {
            let field = MetaDetailFieldDefinition(
                owner: entity,
                name: spec.name,
                type: spec.type,
                sortIndex: index,
                unit: spec.unit,
                options: spec.options,
                isPinned: spec.isPinned
            )
            modelContext.insert(field)
            entity.addDetailField(field)
            fields.append(field)
        }

        DetailsSchemaPinning.enforcePinnedLimitIfNeeded(on: entity)

        do {
            let batch = try GraphMutationBatchFactory.detailSchemaChanged(
                graphID: graphID,
                ownerEntityID: entity.id,
                definitionIDs: fields.map(\.id)
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func deleteFields(
        _ requestedFields: [MetaDetailFieldDefinition],
        from entity: MetaEntity,
        modelContext: ModelContext
    ) async throws -> Bool {
        let uniqueRequestedIDs = Set(requestedFields.map(\.id))
        guard !uniqueRequestedIDs.isEmpty else { return false }
        guard let graphID = entity.graphID else {
            throw ActionError.missingGraphScope
        }

        let original = entity.detailFieldsList
        let fieldsToDelete = original.filter { uniqueRequestedIDs.contains($0.id) }
        guard !fieldsToDelete.isEmpty else { return false }

        try Task.checkCancellation()

        let values = try fetchValues(
            graphID: graphID,
            fieldIDs: Set(fieldsToDelete.map(\.id)),
            modelContext: modelContext
        )
        let deletedValueReferences = values.map { value in
            GraphMutationDetailValueReference(
                id: value.id,
                ownerAttributeID: value.attributeID,
                fieldID: value.fieldID
            )
        }

        for value in values {
            value.attribute?.detailValues?.removeAll { $0.id == value.id }
            modelContext.delete(value)
        }

        for field in fieldsToDelete {
            entity.removeDetailField(field)
            modelContext.delete(field)
        }

        let remaining = original.filter { !uniqueRequestedIDs.contains($0.id) }
        var reindexedIDs: [UUID] = []
        for (index, field) in remaining.enumerated() {
            if field.sortIndex != index {
                field.sortIndex = index
                reindexedIDs.append(field.id)
            }
        }

        let affectedDefinitionIDs = fieldsToDelete.map(\.id) + reindexedIDs

        do {
            let batch = try GraphMutationBatchFactory.detailFieldsDeleted(
                graphID: graphID,
                ownerEntityID: entity.id,
                affectedDefinitionIDs: affectedDefinitionIDs,
                deletedValues: deletedValueReferences
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)
            return true
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func fetchValues(
        graphID: UUID,
        fieldIDs: Set<UUID>,
        modelContext: ModelContext
    ) throws -> [MetaDetailFieldValue] {
        var valuesByID: [UUID: MetaDetailFieldValue] = [:]
        let orderedFieldIDs = fieldIDs.sorted { $0.uuidString < $1.uuidString }

        for fieldID in orderedFieldIDs {
            let requestedFieldID = fieldID
            let descriptor = FetchDescriptor<MetaDetailFieldValue>(
                predicate: #Predicate { value in
                    value.fieldID == requestedFieldID
                }
            )
            for value in try modelContext.fetch(descriptor) {
                if let valueGraphID = value.graphID,
                   valueGraphID != graphID
                {
                    continue
                }
                if let ownerGraphID = value.attribute?.graphID,
                   ownerGraphID != graphID
                {
                    continue
                }
                valuesByID[value.id] = value
            }
        }

        return Array(valuesByID.values)
    }

    private static func makeUniqueTemplateName(
        baseName: String,
        graphID: UUID?,
        modelContext: ModelContext
    ) throws -> String {
        let predicate: Predicate<MetaDetailsTemplate>
        if let graphID {
            predicate = #Predicate { $0.graphID == graphID }
        } else {
            predicate = #Predicate { $0.graphID == nil }
        }

        let descriptor = FetchDescriptor<MetaDetailsTemplate>(predicate: predicate)
        let existing = try modelContext.fetch(descriptor)
        let existingFolded = Set(existing.map(\.nameFolded))

        var candidate = baseName
        var counter = 2
        while existingFolded.contains(BMSearch.fold(candidate)) {
            candidate = "\(baseName) (\(counter))"
            counter += 1
        }

        return candidate
    }
}
