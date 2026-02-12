//
//  NodeAppearanceSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI

struct NodeAppearanceSection: View {
    @Binding var iconSymbolName: String?
    let ownerEntity: MetaEntity?

    init(iconSymbolName: Binding<String?>, ownerEntity: MetaEntity? = nil) {
        self._iconSymbolName = iconSymbolName
        self.ownerEntity = ownerEntity
    }

    var body: some View {
        Section {
            IconPickerRow(title: "Icon", symbolName: $iconSymbolName)

            if let owner = ownerEntity {
                NavigationLink { EntityDetailView(entity: owner) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: owner.iconSymbolName ?? "cube")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 22)
                            .foregroundStyle(.tint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Entität")
                            Text(owner.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            DetailSectionHeader(
                title: "Darstellung",
                systemImage: "paintbrush",
                subtitle: "Icon wird im Canvas und in Listen angezeigt."
            )
        }
    }
}
