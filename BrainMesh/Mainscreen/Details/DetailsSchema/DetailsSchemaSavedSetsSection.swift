//
//  DetailsSchemaSavedSetsSection.swift
//  BrainMesh
//

import SwiftUI

struct DetailsSchemaSavedSetsSection: View {
    let templates: [MetaDetailsTemplate]
    let onApply: (MetaDetailsTemplate) -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Meine Sets")
                    .font(.headline)

                Text("Deine gespeicherten Feld-Sets für schnelles Setup.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 10, lineSpacing: 10) {
                    ForEach(templates, id: \.id) { template in
                        Button {
                            onApply(template)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bookmark")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(template.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(template.fields.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(.quaternary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Wiederverwenden")
        } footer: {
            Text("Sets werden nur angeboten, solange noch keine Felder existieren.")
        }
    }
}
