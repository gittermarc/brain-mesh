//
//  AttributeDetailView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct AttributeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var attribute: MetaAttribute

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @State private var showAddLink = false

    init(attribute: MetaAttribute) {
        self.attribute = attribute
        let id = attribute.id
        let kindRaw = NodeKind.attribute.rawValue
        let gid = attribute.graphID

        _outgoingLinks = Query(
            filter: #Predicate<MetaLink> { l in
                l.sourceKindRaw == kindRaw && l.sourceID == id && (gid == nil || l.graphID == gid)
            },
            sort: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )

        _incomingLinks = Query(
            filter: #Predicate<MetaLink> { l in
                l.targetKindRaw == kindRaw && l.targetID == id && (gid == nil || l.graphID == gid)
            },
            sort: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
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

            Section {
                IconPickerRow(title: "Icon", symbolName: $attribute.iconSymbolName)

                if let owner = attribute.owner {
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

            LinksSection(
                titleOutgoing: "Ausgehend",
                titleIncoming: "Eingehend",
                outgoing: outgoingLinks,
                incoming: incomingLinks,
                onDeleteOutgoing: { offsets in for i in offsets { modelContext.delete(outgoingLinks[i]) } },
                onDeleteIncoming: { offsets in for i in offsets { modelContext.delete(incomingLinks[i]) } },
                onAdd: { showAddLink = true }
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
        .sheet(isPresented: $showAddLink) {
            AddLinkView(
                source: NodeRef(
                    kind: .attribute,
                    id: attribute.id,
                    label: attribute.displayName,
                    iconSymbolName: attribute.iconSymbolName
                ),
                graphID: attribute.graphID
            )
        }
    }
}
