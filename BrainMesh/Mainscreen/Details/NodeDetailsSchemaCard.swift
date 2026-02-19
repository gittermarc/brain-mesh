//
//  NodeDetailsSchemaCard.swift
//  BrainMesh
//
//  Phase 1: Details (frei konfigurierbare Felder)
//

import SwiftUI

struct NodeDetailsSchemaCard: View {
    @Bindable var entity: MetaEntity

    private var fieldCount: Int {
        entity.detailFieldsList.count
    }

    private var pinnedCount: Int {
        entity.detailFieldsList.filter { $0.isPinned }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Details", systemImage: "list.bullet.rectangle")

            Text("Definiere zusätzliche Felder, die jedes Attribut dieser Entität hat.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if fieldCount > 0 {
                Text("\(fieldCount) Feld\(fieldCount == 1 ? "" : "er") · \(pinnedCount) angepinnt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                DetailsSchemaBuilderView(entity: entity)
            } label: {
                Label("Felder konfigurieren", systemImage: "slider.horizontal.3")
                    .font(.callout.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .padding(.top, 2)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}
