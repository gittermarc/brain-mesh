//
//  DetailsSchemaAddFieldSheet.swift
//  BrainMesh
//

import SwiftUI
import SwiftData

enum DetailsFieldEditResult {
    case added
    case saved
    case pinnedLimitReached
}

struct DetailsAddFieldSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entity: MetaEntity

    let onResult: (DetailsFieldEditResult) -> Void

    @State private var name: String = ""
    @State private var type: DetailFieldType = .singleLineText
    @State private var unit: String = ""
    @State private var isPinned: Bool = false
    @State private var optionsText: String = ""

    @State private var error: String? = nil
    @State private var isSaving: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DetailsQuickPresetsView { preset in
                        name = preset.name
                        type = preset.type
                        unit = preset.unit ?? ""
                        optionsText = preset.options.joined(separator: "\n")
                        isPinned = preset.isPinned
                    }
                } header: {
                    Text("Schnellstart")
                } footer: {
                    Text("Tippe auf eine Idee, um Name & Typ automatisch zu setzen.")
                }

                Section {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Typ", selection: $type) {
                        ForEach(DetailFieldType.allCases) { t in
                            Label(t.title, systemImage: t.systemImage)
                                .tag(t)
                        }
                    }

                    if type.supportsUnit {
                        TextField("Einheit (optional)", text: $unit)
                            .textInputAutocapitalization(.never)
                    }

                    if type.supportsOptions {
                        TextEditor(text: $optionsText)
                            .frame(minHeight: 120)
                            .font(.body)
                            .overlay(alignment: .topLeading) {
                                if optionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Optionen – eine pro Zeile")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                }
                            }
                    }

                    Toggle("Anpinnen (max. 3)", isOn: $isPinned)
                } header: {
                    Text("Feld")
                }

                if let error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Neues Feld")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hinzufügen") {
                        Task { await addField() }
                    }
                    .font(.headline)
                    .disabled(isSaving)
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    @MainActor
    private func addField() async {
        guard !isSaving else { return }
        error = nil

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedName.isEmpty {
            error = "Bitte gib einen Namen an."
            return
        }

        if !DetailsSchemaPinning.allowsPinChange(in: entity, from: false, to: isPinned) {
            isPinned = false
            onResult(.pinnedLimitReached)
            return
        }

        let options = optionsText
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if type == .singleChoice, options.isEmpty {
            error = "Für \"Auswahl\" brauchst du mindestens eine Option."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let sortIndex = (entity.detailFieldsList.map(\.sortIndex).max() ?? -1) + 1
        let cleanedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let field = MetaDetailFieldDefinition(
            owner: entity,
            name: cleanedName,
            type: type,
            sortIndex: sortIndex,
            unit: type.supportsUnit && !cleanedUnit.isEmpty ? cleanedUnit : nil,
            options: type.supportsOptions ? options : [],
            isPinned: isPinned
        )

        do {
            _ = try await DetailsSchemaActions.addField(
                field,
                to: entity,
                modelContext: modelContext
            )
            onResult(.added)
            dismiss()
        } catch is CancellationError {
            modelContext.rollback()
        } catch {
            modelContext.rollback()
            self.error = error.localizedDescription
        }
    }

}
