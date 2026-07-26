//
//  DetailsSchemaFieldsList.swift
//  BrainMesh
//

import SwiftUI

struct DetailsSchemaFieldsList: View {
    @Bindable var entity: MetaEntity

    let onEditField: (MetaDetailFieldDefinition) -> Void
    let onChatWithField: (MetaDetailFieldDefinition) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        Section {
            if entity.authoritativeDetailFieldsList.isEmpty {
                ContentUnavailableView {
                    Label("Keine Felder", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Lege Felder an, damit du pro Attribut strukturierte Details pflegen kannst.")
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(entity.authoritativeDetailFieldsList) { field in
                    Button {
                        onEditField(field)
                    } label: {
                        DetailsFieldRow(field: field)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            onChatWithField(field)
                        } label: {
                            Label(
                                GraphChatResponseLanguageSelector.systemFallback() == .german
                                    ? "Mit Feld chatten"
                                    : "Chat with field",
                                systemImage: "bubble.left.and.text.bubble.right"
                            )
                        }
                        .accessibilityLabel(
                            GraphChatResponseLanguageSelector.systemFallback() == .german
                                ? "Mit dem Detailfeld \(field.name) chatten"
                                : "Chat with the \(field.name) detail field"
                        )
                    }
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
