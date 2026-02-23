import SwiftUI
import SwiftData
import Foundation

extension DetailsValueEditorSheet {
    var resolvedGraphID: UUID? {
        if let id = attribute.graphID { return id }
        if let id = attribute.owner?.graphID { return id }
        return UUID(uuidString: activeGraphIDString)
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
    func saveValue() {
        error = nil

        switch field.type {
        case .singleLineText, .multiLineText:
            let cleaned = stringInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                deleteValue()
                return
            }

            let rec = upsertRecord()
            rec.clearTypedValues()
            rec.stringValue = cleaned

        case .numberInt:
            let cleaned = numberInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                deleteValue()
                return
            }

            guard let v = Int(cleaned) else {
                error = "Bitte gib eine gültige Ganzzahl ein."
                return
            }

            let rec = upsertRecord()
            rec.clearTypedValues()
            rec.intValue = v

        case .numberDouble:
            let cleaned = numberInput.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                deleteValue()
                return
            }

            let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
            guard let v = Double(normalized) else {
                error = "Bitte gib eine gültige Zahl ein."
                return
            }

            let rec = upsertRecord()
            rec.clearTypedValues()
            rec.doubleValue = v

        case .date:
            let rec = upsertRecord()
            rec.clearTypedValues()
            rec.dateValue = dateInput

        case .toggle:
            let rec = upsertRecord()
            rec.clearTypedValues()
            rec.boolValue = boolInput

        case .singleChoice:
            guard let selectedChoice, !selectedChoice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                deleteValue()
                return
            }

            let rec = upsertRecord()
            rec.clearTypedValues()
            rec.stringValue = selectedChoice
        }

        try? modelContext.save()
        hasExistingValue = existingRecord() != nil
        dismiss()
    }

    @MainActor
    func deleteValue() {
        guard let existing = existingRecord() else {
            dismiss()
            return
        }

        attribute.detailValues?.removeAll(where: { $0.id == existing.id })
        modelContext.delete(existing)
        try? modelContext.save()
        dismiss()
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
}
