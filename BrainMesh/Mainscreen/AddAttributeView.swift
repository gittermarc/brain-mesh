//
//  AddAttributeView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI
import SwiftData

struct AddAttributeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity

    @State private var name: String = ""
    @State private var iconSymbolName: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Attribut") {
                    TextField("Name (z.B. 2023)", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Icon") {
                    IconPickerRow(title: "Icon auswählen", symbolName: $iconSymbolName)
                }

                Section {
                    Text("Attribute sind frei benennbar.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Neues Attribut")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") { add() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func add() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        let attr = MetaAttribute(name: cleaned, owner: nil, graphID: entity.graphID, iconSymbolName: iconSymbolName)
        modelContext.insert(attr)
        entity.addAttribute(attr)

        try? modelContext.save()
        dismiss()
    }
}
