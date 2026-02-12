//
//  EntityAttributesSectionView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData

struct EntityAttributesSectionView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var entity: MetaEntity
    @Binding var showAddAttribute: Bool

    var body: some View {
        let sortedAttributes = entity.attributesList.sorted(by: { $0.name < $1.name })

        Section {
            if sortedAttributes.isEmpty {
                Text("Noch keine Attribute.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sortedAttributes) { attr in
                    NavigationLink { AttributeDetailView(attribute: attr) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: attr.iconSymbolName ?? "tag")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 22)
                                .foregroundStyle(.tint)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(attr.name)
                                if let note = attr.notes.isEmpty ? nil : attr.notes {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    deleteAttributes(at: offsets, sorted: sortedAttributes)
                }
            }

            Button { showAddAttribute = true } label: {
                Label("Attribut hinzufügen", systemImage: "plus")
            }
        } header: {
            DetailSectionHeader(
                title: "Attribute",
                systemImage: "tag",
                subtitle: "Attribute gehören zur Entität und können selbst Links/Bilder/Anhänge haben."
            )
        }
    }

    private func deleteAttributes(at offsets: IndexSet, sorted: [MetaAttribute]) {
        for index in offsets {
            guard sorted.indices.contains(index) else { continue }
            let attr = sorted[index]

            AttachmentCleanup.deleteAttachments(ownerKind: .attribute, ownerID: attr.id, in: modelContext)
            LinkCleanup.deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID, in: modelContext)

            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
    }
}
