//
//  EntityDetailView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct EntityDetailView: View {
    @Bindable var entity: MetaEntity

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @State private var showAddAttribute = false
    @State private var showAddLink = false

    init(entity: MetaEntity) {
        self.entity = entity

        _outgoingLinks = NodeLinksQueryBuilder.outgoingLinksQuery(
            kind: .entity,
            id: entity.id,
            graphID: entity.graphID
        )

        _incomingLinks = NodeLinksQueryBuilder.incomingLinksQuery(
            kind: .entity,
            id: entity.id,
            graphID: entity.graphID
        )
    }

    var body: some View {
        List {
            Section {
                NodeDetailHeaderCard(
                    kindTitle: "Entität",
                    placeholder: "Name",
                    name: $entity.name,
                    iconSymbolName: entity.iconSymbolName,
                    imageData: entity.imageData,
                    imagePath: entity.imagePath,
                    subtitle: nil,
                    chips: [
                        NodeHeaderChip(title: "\(entity.attributesList.count)", systemImage: "tag"),
                        NodeHeaderChip(title: "\(outgoingLinks.count)", systemImage: "arrow.up.right"),
                        NodeHeaderChip(title: "\(incomingLinks.count)", systemImage: "arrow.down.left")
                    ]
                )
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            NodeAppearanceSection(iconSymbolName: $entity.iconSymbolName)

            NotesAndPhotoSection(
                notes: $entity.notes,
                imageData: $entity.imageData,
                imagePath: $entity.imagePath,
                stableID: entity.id
            )

            AttachmentsSection(
                ownerKind: .entity,
                ownerID: entity.id,
                graphID: entity.graphID
            )
            .id("attachments-entity-\(entity.id.uuidString)")

            EntityAttributesSectionView(entity: entity, showAddAttribute: $showAddAttribute)

            NodeLinksSectionView(
                outgoing: outgoingLinks,
                incoming: incomingLinks,
                showAddLink: $showAddLink
            )
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(entity.name.isEmpty ? "Entität" : entity.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAddAttribute = true
                    } label: {
                        Label("Attribut hinzufügen", systemImage: "tag.badge.plus")
                    }

                    Button {
                        showAddLink = true
                    } label: {
                        Label("Link hinzufügen", systemImage: "link.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Aktionen")
            }
        }
        .sheet(isPresented: $showAddAttribute) {
            AddAttributeView(entity: entity)
        }
        .addLinkSheet(isPresented: $showAddLink, source: entity.nodeRef, graphID: entity.graphID)
    }
}
