//
//  AttributeDetailView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct AttributeDetailView: View {
    @Bindable var attribute: MetaAttribute

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @State private var showAddLink = false

    init(attribute: MetaAttribute) {
        self.attribute = attribute

        _outgoingLinks = NodeLinksQueryBuilder.outgoingLinksQuery(
            kind: .attribute,
            id: attribute.id,
            graphID: attribute.graphID
        )

        _incomingLinks = NodeLinksQueryBuilder.incomingLinksQuery(
            kind: .attribute,
            id: attribute.id,
            graphID: attribute.graphID
        )
    }

    var body: some View {
        List {
            Section {
                NodeDetailHeaderCard(
                    kindTitle: "Attribut",
                    placeholder: "Name",
                    name: $attribute.name,
                    iconSymbolName: attribute.iconSymbolName,
                    imageData: attribute.imageData,
                    imagePath: attribute.imagePath,
                    subtitle: attribute.owner?.name,
                    chips: [
                        NodeHeaderChip(title: "\(outgoingLinks.count)", systemImage: "arrow.up.right"),
                        NodeHeaderChip(title: "\(incomingLinks.count)", systemImage: "arrow.down.left")
                    ]
                )
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            NodeAppearanceSection(iconSymbolName: $attribute.iconSymbolName, ownerEntity: attribute.owner)

            NotesAndPhotoSection(
                notes: $attribute.notes,
                imageData: $attribute.imageData,
                imagePath: $attribute.imagePath,
                stableID: attribute.id
            )

            AttachmentsSection(
                ownerKind: .attribute,
                ownerID: attribute.id,
                graphID: attribute.graphID
            )
            .id("attachments-attribute-\(attribute.id.uuidString)")

            NodeLinksSectionView(
                outgoing: outgoingLinks,
                incoming: incomingLinks,
                showAddLink: $showAddLink
            )
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(12)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(attribute.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddLink = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .accessibilityLabel("Link hinzufügen")
            }
        }
        .addLinkSheet(isPresented: $showAddLink, source: attribute.nodeRef, graphID: attribute.graphID)
    }
}
