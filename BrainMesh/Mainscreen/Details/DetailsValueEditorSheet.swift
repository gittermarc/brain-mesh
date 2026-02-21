//
//  DetailsValueEditorSheet.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import SwiftUI
import SwiftData
import Foundation

struct DetailsValueEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""

    @Bindable var attribute: MetaAttribute
    let field: MetaDetailFieldDefinition

    @State private var stringInput: String = ""
    @State private var numberInput: String = ""
    @State private var dateInput: Date = Date()
    @State private var boolInput: Bool = false
    @State private var selectedChoice: String? = nil

    @State private var hasExistingValue: Bool = false
    @State private var error: String? = nil

    // MARK: - Completion (singleLineText only)

    @FocusState private var isSingleLineTextFocused: Bool
    @State private var didWarmUpCompletionIndex: Bool = false
    @State private var topCompletion: DetailsCompletionSuggestion? = nil
    @State private var completionTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    editorBody
                } header: {
                    Text(field.name.isEmpty ? "Feld" : field.name)
                } footer: {
                    if let unit = field.unit, field.type.supportsUnit {
                        Text(unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "Einheit: \(unit)")
                    }
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                if hasExistingValue {
                    Section {
                        Button(role: .destructive) {
                            deleteValue()
                        } label: {
                            Label("Wert löschen", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") {
                        saveValue()
                    }
                    .font(.headline)
                }

                if field.type == .singleLineText {
                    DetailsCompletionKeyboardToolbar(isEnabled: isSingleLineTextFocused && topCompletion != nil) {
                        acceptTopCompletionIfPossible()
                    }
                }
            }
            .onAppear {
                loadExistingValue()
                warmUpCompletionIndexIfNeeded()
            }
            .onDisappear {
                completionTask?.cancel()
                completionTask = nil
                topCompletion = nil
            }
            .onChange(of: isSingleLineTextFocused) { _, newValue in
                if newValue {
                    warmUpCompletionIndexIfNeeded()
                    refreshTopCompletionIfPossible()
                } else {
                    // Hide ghost and disable toolbar when leaving the field.
                    completionTask?.cancel()
                    completionTask = nil
                    topCompletion = nil
                }
            }
        }
    }

    @ViewBuilder
    private var editorBody: some View {
        switch field.type {
        case .singleLineText:
            TextField("Text", text: $stringInput)
                .textInputAutocapitalization(.sentences)
                .focused($isSingleLineTextFocused)
                .detailsCompletionGhost(
                    currentText: stringInput,
                    suggestionText: isSingleLineTextFocused ? topCompletion?.text : nil,
                    inset: .init(top: 0, leading: 4, bottom: 0, trailing: 0)
                )
                .onChange(of: stringInput) { _, _ in
                    refreshTopCompletionIfPossible()
                }

        case .multiLineText:
            TextEditor(text: $stringInput)
                .frame(minHeight: 160)
                .font(.body)
                .overlay(alignment: .topLeading) {
                    if stringInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Text")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                }

        case .numberInt:
            TextField("Zahl", text: $numberInput)
                .keyboardType(.numberPad)

        case .numberDouble:
            TextField("Zahl", text: $numberInput)
                .keyboardType(.decimalPad)

        case .date:
            DatePicker("Datum", selection: $dateInput, displayedComponents: [.date])

        case .toggle:
            Toggle("Ja / Nein", isOn: $boolInput)

        case .singleChoice:
            if field.options.isEmpty {
                Text("Keine Optionen definiert.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Auswahl", selection: Binding(
                    get: { selectedChoice ?? "" },
                    set: { selectedChoice = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Nicht gesetzt").tag("")
                    ForEach(field.options, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
            }
        }
    }

    private var resolvedGraphID: UUID? {
        if let id = attribute.graphID { return id }
        if let id = attribute.owner?.graphID { return id }
        return UUID(uuidString: activeGraphIDString)
    }

    @MainActor
    private func warmUpCompletionIndexIfNeeded() {
        guard field.type == .singleLineText else { return }
        guard didWarmUpCompletionIndex == false else { return }
        guard let gid = resolvedGraphID else { return }

        didWarmUpCompletionIndex = true

        Task { @MainActor in
            await DetailsCompletionIndex.shared.ensureLoaded(graphID: gid, fieldID: field.id, in: modelContext)
            refreshTopCompletionIfPossible()
        }
    }

    @MainActor
    private func refreshTopCompletionIfPossible() {
        guard field.type == .singleLineText else {
            topCompletion = nil
            return
        }

        // Only show completions while actively editing the field.
        guard isSingleLineTextFocused else {
            topCompletion = nil
            return
        }

        guard let gid = resolvedGraphID else {
            topCompletion = nil
            return
        }

        // If the user typed a trailing whitespace, stop suggesting.
        if let last = stringInput.last, last.isWhitespace {
            topCompletion = nil
            return
        }

        let current = stringInput

        completionTask?.cancel()
        completionTask = Task {
            let suggestion = await DetailsCompletionIndex.shared.topSuggestion(graphID: gid, fieldID: field.id, prefix: current)
            if Task.isCancelled { return }
            await MainActor.run {
                self.topCompletion = suggestion
            }
        }
    }

    @MainActor
    private func acceptTopCompletionIfPossible() {
        guard field.type == .singleLineText else { return }
        guard isSingleLineTextFocused else { return }
        guard let suggestion = topCompletion else { return }

        // Workaround for occasional SwiftUI TextField state races while editing:
        // apply on the next runloop tick so the active editing session doesn't overwrite us.
        let accepted = suggestion.text

        completionTask?.cancel()
        completionTask = nil
        topCompletion = nil

        DispatchQueue.main.async {
            self.stringInput = accepted
            self.isSingleLineTextFocused = true
            self.refreshTopCompletionIfPossible()
        }
    }

    private func loadExistingValue() {
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
    private func saveValue() {
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
    private func deleteValue() {
        guard let existing = existingRecord() else {
            dismiss()
            return
        }

        attribute.detailValues?.removeAll(where: { $0.id == existing.id })
        modelContext.delete(existing)
        try? modelContext.save()
        dismiss()
    }

    private func existingRecord() -> MetaDetailFieldValue? {
        attribute.detailValuesList.first(where: { $0.fieldID == field.id })
    }

    @MainActor
    private func upsertRecord() -> MetaDetailFieldValue {
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
