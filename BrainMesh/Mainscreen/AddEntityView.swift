//
//  AddEntityView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct AddEntityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("BMActiveGraphID") private var activeGraphIDString: String = ""
    private var activeGraphID: UUID? { UUID(uuidString: activeGraphIDString) }

    @State private var name = ""
    @State private var iconSymbolName: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)

                Section("Icon") {
                    IconPickerRow(title: "Icon auswählen", symbolName: $iconSymbolName)
                }
            }
            .navigationTitle("Neue Entität")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let e = MetaEntity(name: cleaned, graphID: activeGraphID, iconSymbolName: iconSymbolName)
                        modelContext.insert(e)
                        try? modelContext.save()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
