//
//  DetailsSchemaFieldsList.swift
//  BrainMesh
//

import SwiftUI

struct DetailsSchemaFieldsList: View {
    @Bindable var entity: MetaEntity

    let onEditField: (MetaDetailFieldDefinition) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        Section {
            if entity.detailFieldsList.isEmpty {
                ContentUnavailableView {
                    Label("Keine Felder", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Lege Felder an, damit du pro Attribut strukturierte Details pflegen kannst.")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(entity.detailFieldsList) { field in
                    Button {
                        onEditField(field)
                    } label: {
                        DetailsFieldRow(field: field)
                    }
                    .buttonStyle(.plain)
                }
                .onMove(perform: onMove)
                .onDelete(perform: onDelete)
            }
        } header: {
            Text("Felder")
        } footer: {
            Text("Tipp: Du kannst bis zu 3 Felder anpinnen. Die erscheinen dann als kleine Pills oben im Attribut.")
        }
    }
}
