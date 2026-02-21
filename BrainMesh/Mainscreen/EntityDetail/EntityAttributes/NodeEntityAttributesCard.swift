//
//  NodeEntityAttributesCard.swift
//  BrainMesh
//
//  P0.4: Extracted from EntityDetailView+AttributesSection.swift
//

import Foundation
import SwiftUI
import SwiftData

struct NodeEntityAttributesCard: View {
    let entity: MetaEntity

    private var preview: [MetaAttribute] {
        Array(entity.attributesList.sorted(by: { $0.nameFolded < $1.nameFolded }).prefix(12))
    }

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NodeCardHeader(title: "Attribute", systemImage: "tag")

            if entity.attributesList.isEmpty {
                NodeEmptyStateRow(
                    text: "Noch keine Attribute.",
                    ctaTitle: "Attribute ansehen",
                    ctaSystemImage: "tag",
                    ctaAction: {}
                )
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(preview) { attr in
                        NavigationLink {
                            AttributeDetailView(attribute: attr)
                        } label: {
                            Label(attr.name.isEmpty ? "Attribut" : attr.name, systemImage: attr.iconSymbolName ?? "tag")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                NavigationLink {
                    EntityAttributesAllView(entity: entity)
                } label: {
                    Label("Alle", systemImage: "chevron.right")
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}
