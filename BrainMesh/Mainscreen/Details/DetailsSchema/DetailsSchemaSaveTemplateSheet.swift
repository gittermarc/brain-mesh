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
            }
            .navigationTitle("Als Set speichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        DetailsSchemaActions.saveTemplate(from: entity, name: name, modelContext: modelContext)
                        dismiss()
                    }
                    .disabled(isSaveDisabled)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isNameFocused = true
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty || entity.detailFieldsList.isEmpty
    }
}
