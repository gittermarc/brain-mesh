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
    @State private var isSaving: Bool = false

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
                        Task { await deleteField() }
                    } label: {
                        Label("Feld löschen", systemImage: "trash")
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("Feld bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Schließen") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sichern") {
                        Task { await saveChanges() }
                    }
                    .font(.headline)
                    .disabled(isSaving)
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
        .interactiveDismissDisabled(isSaving)
    }

    @MainActor
    private func saveChanges() async {
        guard !isSaving else { return }
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

        let cleanedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalUnit = type.supportsUnit && !cleanedUnit.isEmpty ? cleanedUnit : nil
        let finalOptions = type.supportsOptions ? options : []

        let hasChanges = field.name != cleanedName ||
            field.type != type ||
            field.unit != finalUnit ||
            field.isPinned != isPinned ||
            field.options != finalOptions

        guard hasChanges else {
            onResult(.saved)
            dismiss()
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await DetailsSchemaActions.updateField(
                field,
                in: entity,
                update: DetailsSchemaActions.FieldUpdate(
                    name: cleanedName,
                    type: type,
                    unit: finalUnit,
                    options: finalOptions,
                    isPinned: isPinned
                ),
                modelContext: modelContext
            )
            onResult(.saved)
            dismiss()
        } catch is CancellationError {
            modelContext.rollback()
        } catch {
            modelContext.rollback()
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func deleteField() async {
        guard !isSaving else { return }
        error = nil
        isSaving = true
        defer { isSaving = false }

        do {
            _ = try await DetailsSchemaActions.deleteField(
                field,
                from: entity,
                modelContext: modelContext
            )
            dismiss()
        } catch is CancellationError {
            modelContext.rollback()
        } catch {
            modelContext.rollback()
            self.error = error.localizedDescription
        }
    }

}
