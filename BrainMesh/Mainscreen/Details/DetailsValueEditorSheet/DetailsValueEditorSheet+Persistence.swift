import SwiftUI
import SwiftData
import Foundation

extension DetailsValueEditorSheet {
    var resolvedGraphID: UUID? {
        try? DetailDataWriteValidator.validate(
            field: field,
            attribute: attribute
        )
    }

    func loadExistingValue() {
        error = nil

        let authority: (
            resolution: DetailValueAuthorityResolution,
            records: [MetaDetailFieldValue]
        )
        do {
            authority = try DetailValueMutationService.authority(
                attribute: attribute,
                field: field,
                modelContext: modelContext
            )
        } catch {
            hasExistingValue = false
            resetInputs()
            self.error = error.localizedDescription
            return
        }

        switch authority.resolution {
        case .missing:
            hasExistingValue = false
            resetInputs()
            return
        case .conflict, .invalid:
            hasExistingValue = true
            resetInputs()
            error = "Für dieses Feld sind mehrere oder ungültige Werte gespeichert. Sichern fasst sie atomar zu deinem gewählten Wert zusammen."
        case .authoritative(let recordID, _, _):
            guard let value = authority.records.first(where: { $0.id == recordID }) else {
                hasExistingValue = false
                resetInputs()
                return
            }
            hasExistingValue = true
            loadInputs(from: value)
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
            isSaving = true
            defer { isSaving = false }

            do {
                _ = try await DetailValueMutationService.save(
                    payload,
                    attribute: attribute,
                    field: field,
                    modelContext: modelContext
                )
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

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await DetailValueMutationService.delete(
                attribute: attribute,
                field: field,
                modelContext: modelContext
            )
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
        guard let authority = try? DetailValueMutationService.authority(
            attribute: attribute,
            field: field,
            modelContext: modelContext
        ),
        let recordID = authority.resolution.authoritativeRecordID else {
            return nil
        }
        return authority.records.first { $0.id == recordID }
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

    private func resetInputs() {
        stringInput = ""
        numberInput = ""
        selectedChoice = nil
        dateInput = Date()
        boolInput = false
    }

    private func loadInputs(from value: MetaDetailFieldValue) {
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
}

private enum PreparedDetailValueInput {
    case empty
    case value(DetailValueWritePayload)
}

private enum DetailValuePersistenceError: LocalizedError {
    case invalidInteger
    case invalidDouble

    var errorDescription: String? {
        switch self {
        case .invalidInteger:
            return "Bitte gib eine gültige Ganzzahl ein."
        case .invalidDouble:
            return "Bitte gib eine gültige Zahl ein."
        }
    }
}
