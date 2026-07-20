import SwiftUI
import SwiftData
import Foundation

extension DetailsValueEditorSheet {
    var resolvedGraphID: UUID? {
        let modelGraphIDs = [
            attribute.graphID,
            attribute.owner?.graphID,
            field.graphID,
            field.owner?.graphID
        ].compactMap { $0 }

        guard Set(modelGraphIDs).count <= 1 else {
            return nil
        }
        return modelGraphIDs.first ?? UUID(uuidString: activeGraphIDString)
    }

    func loadExistingValue() {
        error = nil

        guard let value = existingRecord() else {
            hasExistingValue = false

            // Sensible defaults, but only written on save.
            stringInput = ""
            numberInput = ""
            selectedChoice = nil
            dateInput = Date()
            boolInput = false
            return
        }

        hasExistingValue = true

        switch field.type {
        case .singleLineText, .multiLineText:
            stringInput = value.stringValue ?? ""

        case .numberInt:
            numberInput = value.intValue.map(String.init) ?? ""

        case .numberDouble:
            numberInput = value.doubleValue.map { String($0) } ?? ""

        case .date:
            dateInput = value.dateValue ?? Date()

        case .toggle:
            boolInput = value.boolValue ?? false

        case .singleChoice:
            selectedChoice = value.stringValue
        }
    }

    @MainActor
    func saveValue() async {
        guard !isSaving else { return }
        error = nil

        let preparedInput: PreparedDetailValueInput
        do {
            preparedInput = try prepareInput()
        } catch {
            self.error = error.localizedDescription
            return
        }

        switch preparedInput {
        case .empty:
            await deleteValue()

        case .value(let payload):
            guard let graphID = resolvedGraphID else {
                error = DetailValuePersistenceError.missingGraphScope.localizedDescription
                return
            }

            if let existing = existingRecord() {
                do {
                    try validateGraphScope(of: existing, expectedGraphID: graphID)
                } catch {
                    self.error = error.localizedDescription
                    return
                }
                if payload.matches(existing) {
                    dismiss()
                    return
                }
            }

            isSaving = true
            defer { isSaving = false }

            let record = upsertRecord()
            record.graphID = graphID
            record.attributeID = attribute.id
            record.fieldID = field.id
            payload.apply(to: record)
            let reference = GraphMutationDetailValueReference(
                id: record.id,
                ownerAttributeID: attribute.id,
                fieldID: field.id
            )

            do {
                let batch = try GraphMutationBatchFactory.detailValueChanged(
                    graphID: graphID,
                    value: reference
                )
                try await GraphMutationCommitter().commit(batch, in: modelContext)
                hasExistingValue = true
                dismiss()
            } catch is CancellationError {
                modelContext.rollback()
            } catch {
                modelContext.rollback()
                self.error = error.localizedDescription
            }
        }
    }

    @MainActor
    func deleteValue() async {
        guard !isSaving else { return }
        guard let existing = existingRecord() else {
            dismiss()
            return
        }
        guard let graphID = resolvedGraphID else {
            error = DetailValuePersistenceError.missingGraphScope.localizedDescription
            return
        }

        do {
            try validateGraphScope(of: existing, expectedGraphID: graphID)
        } catch {
            self.error = error.localizedDescription
            return
        }

        isSaving = true
        defer { isSaving = false }

        let reference = GraphMutationDetailValueReference(
            id: existing.id,
            ownerAttributeID: existing.attributeID,
            fieldID: existing.fieldID
        )
        attribute.detailValues?.removeAll(where: { $0.id == existing.id })
        modelContext.delete(existing)

        do {
            let batch = try GraphMutationBatchFactory.detailValueDeleted(
                graphID: graphID,
                value: reference
            )
            try await GraphMutationCommitter().commit(batch, in: modelContext)
            hasExistingValue = false
            dismiss()
        } catch is CancellationError {
            modelContext.rollback()
        } catch {
            modelContext.rollback()
            self.error = error.localizedDescription
        }
    }

    func existingRecord() -> MetaDetailFieldValue? {
        attribute.detailValuesList.first(where: { $0.fieldID == field.id })
    }

    @MainActor
    func upsertRecord() -> MetaDetailFieldValue {
        if let existing = existingRecord() {
            return existing
        }

        let newValue = MetaDetailFieldValue(attribute: attribute, fieldID: field.id)
        modelContext.insert(newValue)

        if attribute.detailValues == nil {
            attribute.detailValues = []
        }
        if attribute.detailValues?.contains(where: { $0.id == newValue.id }) != true {
            attribute.detailValues?.append(newValue)
        }

        return newValue
    }

    private func prepareInput() throws -> PreparedDetailValueInput {
        switch field.type {
        case .singleLineText, .multiLineText:
            let cleaned = stringInput.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? .empty : .value(.string(cleaned))

        case .numberInt:
            let cleaned = numberInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return .empty }
            guard let value = Int(cleaned) else {
                throw DetailValuePersistenceError.invalidInteger
            }
            return .value(.integer(value))

        case .numberDouble:
            let cleaned = numberInput.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return .empty }
            let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
            guard let value = Double(normalized) else {
                throw DetailValuePersistenceError.invalidDouble
            }
            return .value(.double(value))

        case .date:
            return .value(.date(dateInput))

        case .toggle:
            return .value(.boolean(boolInput))

        case .singleChoice:
            guard let selectedChoice else { return .empty }
            let cleaned = selectedChoice.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? .empty : .value(.string(cleaned))
        }
    }

    private func validateGraphScope(
        of value: MetaDetailFieldValue,
        expectedGraphID: UUID
    ) throws {
        if let valueGraphID = value.graphID,
           valueGraphID != expectedGraphID
        {
            throw DetailValuePersistenceError.inconsistentGraphScope
        }
        if let ownerGraphID = value.attribute?.graphID,
           ownerGraphID != expectedGraphID
        {
            throw DetailValuePersistenceError.inconsistentGraphScope
        }
    }
}

private enum PreparedDetailValueInput {
    case empty
    case value(DetailValuePayload)
}

private enum DetailValuePayload: Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case date(Date)
    case boolean(Bool)

    func matches(_ record: MetaDetailFieldValue) -> Bool {
        switch self {
        case .string(let value):
            return record.stringValue == value &&
                record.intValue == nil &&
                record.doubleValue == nil &&
                record.dateValue == nil &&
                record.boolValue == nil
        case .integer(let value):
            return record.stringValue == nil &&
                record.intValue == value &&
                record.doubleValue == nil &&
                record.dateValue == nil &&
                record.boolValue == nil
        case .double(let value):
            return record.stringValue == nil &&
                record.intValue == nil &&
                record.doubleValue == value &&
                record.dateValue == nil &&
                record.boolValue == nil
        case .date(let value):
            return record.stringValue == nil &&
                record.intValue == nil &&
                record.doubleValue == nil &&
                record.dateValue == value &&
                record.boolValue == nil
        case .boolean(let value):
            return record.stringValue == nil &&
                record.intValue == nil &&
                record.doubleValue == nil &&
                record.dateValue == nil &&
                record.boolValue == value
        }
    }

    func apply(to record: MetaDetailFieldValue) {
        record.clearTypedValues()
        switch self {
        case .string(let value):
            record.stringValue = value
        case .integer(let value):
            record.intValue = value
        case .double(let value):
            record.doubleValue = value
        case .date(let value):
            record.dateValue = value
        case .boolean(let value):
            record.boolValue = value
        }
    }
}

private enum DetailValuePersistenceError: LocalizedError {
    case missingGraphScope
    case inconsistentGraphScope
    case invalidInteger
    case invalidDouble

    var errorDescription: String? {
        switch self {
        case .missingGraphScope:
            return "Für dieses Detail ist kein Graph zugeordnet."
        case .inconsistentGraphScope:
            return "Das Detail gehört nicht eindeutig zu diesem Graphen."
        case .invalidInteger:
            return "Bitte gib eine gültige Ganzzahl ein."
        case .invalidDouble:
            return "Bitte gib eine gültige Zahl ein."
        }
    }
}
