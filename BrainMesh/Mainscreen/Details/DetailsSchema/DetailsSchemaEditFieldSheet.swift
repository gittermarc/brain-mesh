//
//  DetailsSchemaEditFieldSheet.swift
//  BrainMesh
//

import SwiftUI
import SwiftData

struct DetailsEditFieldSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entity: MetaEntity
    @Bindable var field: MetaDetailFieldDefinition

    let onResult: (DetailsFieldEditResult) -> Void

    @State private var name: String = ""
    @State private var type: DetailFieldType = .singleLineText
    @State private var unit: String = ""
    @State private var isPinned: Bool = false
    @State private var optionsText: String = ""

    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Button(role: .destructive) {
                        deleteField()
                    } label: {
                        Label("Feld löschen", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Feld bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") {
                        saveChanges()
                    }
                    .font(.headline)
                }
            }
            .onAppear {
                name = field.name
                type = field.type
                unit = field.unit ?? ""
                isPinned = field.isPinned
                optionsText = field.options.joined(separator: "\n")
            }
        }
    }

    private func saveChanges() {
        error = nil

        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedName.isEmpty {
            error = "Bitte gib einen Namen an."
            return
        }

        if !DetailsSchemaPinning.allowsPinChange(in: entity, from: field.isPinned, to: isPinned) {
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

        field.name = cleanedName
        field.type = type
        field.unit = (type.supportsUnit && !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? unit : nil
        field.isPinned = isPinned

        if type.supportsOptions {
            field.setOptions(options)
        } else {
            field.optionsJSON = nil
        }

        try? modelContext.save()
        onResult(.saved)
        dismiss()
    }

    private func deleteField() {
        DetailsSchemaActions.deleteAllValues(modelContext: modelContext, forFieldID: field.id)
        entity.removeDetailField(field)
        modelContext.delete(field)

        // Reindex remaining
        let remaining = entity.detailFieldsList
            .filter { $0.id != field.id }
            .sorted(by: { $0.sortIndex < $1.sortIndex })
        for (idx, f) in remaining.enumerated() {
            f.sortIndex = idx
        }

        try? modelContext.save()
        dismiss()
    }
}
