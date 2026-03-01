//
//  NodeDetailsValuesCard.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import SwiftUI

struct NodeDetailsValuesCard: View {
    let attribute: MetaAttribute
    let owner: MetaEntity

    var layout: AttributeDetailDetailsLayout = .list
    var hideEmpty: Bool = false

    let onConfigureSchema: () -> Void
    let onEditValue: (MetaDetailFieldDefinition) -> Void

    @State private var showEmptyFields: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Details", systemImage: "info.circle")

            if fields.isEmpty {
                let ownerDisplayName = owner.name.isEmpty ? "Entität" : owner.name
                NodeEmptyStateRow(
                    text: "Noch keine Felder definiert.",
                    ctaTitle: "Felder für \"\(ownerDisplayName)\" anlegen",
                    ctaSystemImage: "slider.horizontal.3",
                    ctaAction: onConfigureSchema
                )
            } else {
                NodeDetailsValuesContent(
                    rows: visibleRows,
                    emptyRows: emptyRows,
                    layout: layout,
                    hideEmpty: hideEmpty,
                    showEmptyFields: $showEmptyFields,
                    onEditValue: onEditValue
                )
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
        .onAppear {
            if hideEmpty, visibleRows.isEmpty, !emptyRows.isEmpty {
                showEmptyFields = true
            }
        }
        .onChange(of: hideEmpty) { _, newValue in
            if newValue, visibleRows.isEmpty, !emptyRows.isEmpty {
                showEmptyFields = true
            }
            if !newValue {
                showEmptyFields = false
            }
        }
    }
}
