//
//  DetailsSchemaSaveTemplateSheet.swift
//  BrainMesh
//

import SwiftUI
import SwiftData

struct DetailsSchemaSaveTemplateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var entity: MetaEntity

    @State private var name: String
    @State private var errorMessage: String? = nil
    @State private var isSaving: Bool = false
    @FocusState private var isNameFocused: Bool

    init(entity: MetaEntity) {
        self._entity = Bindable(wrappedValue: entity)
        let suggested = entity.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self._name = State(initialValue: suggested.isEmpty ? "Mein Set" : suggested)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($isNameFocused)
                } header: {
                    Text("Name")
                }

                Section {
                    let total = entity.detailFieldsList.count
                    let pinned = entity.detailFieldsList.filter { $0.isPinned }.count
                    LabeledContent("Felder", value: "\(total)")
                    LabeledContent("Pins", value: "\(pinned)")
                } header: {
                    Text("Inhalt")
                }

                Section {
                    Text("Speichert das aktuelle Feld-Set, damit du es bei anderen Entitäten schnell übernehmen kannst.")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Als Set speichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        Task { await saveTemplate() }
                    }
                    .disabled(isSaveDisabled || isSaving)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isNameFocused = true
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    @MainActor
    private func saveTemplate() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let didSave = try DetailsSchemaActions.saveTemplate(
                from: entity,
                name: name,
                modelContext: modelContext
            )
            if didSave {
                dismiss()
            }
        } catch is CancellationError {
            modelContext.rollback()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private var isSaveDisabled: Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || entity.detailFieldsList.isEmpty
    }
}
