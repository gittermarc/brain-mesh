//
//  EntityDetailView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI
import SwiftData

struct EntityDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var entity: MetaEntity

    @Query private var outgoingLinks: [MetaLink]
    @Query private var incomingLinks: [MetaLink]

    @State private var showAddAttribute = false
    @State private var showAddLink = false

    init(entity: MetaEntity) {
        self.entity = entity
        let id = entity.id
        let kindRaw = NodeKind.entity.rawValue
        let gid = entity.graphID

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
        Form {
            Section("Entität") {
                TextField("Name", text: $entity.name)
                IconPickerRow(title: "Icon", symbolName: $entity.iconSymbolName)
            }
            NotesAndPhotoSection(
                notes: $entity.notes,
                imageData: $entity.imageData,
                imagePath: $entity.imagePath,
                stableID: entity.id
            )

            Section("Attribute") {
                if entity.attributesList.isEmpty {
                    Text("Noch keine Attribute.").foregroundStyle(.secondary)
                } else {
                    ForEach(entity.attributesList.sorted(by: { $0.name < $1.name })) { attr in
                        NavigationLink { AttributeDetailView(attribute: attr) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: attr.iconSymbolName ?? "tag")
                                    .font(.system(size: 16, weight: .semibold))
                                    .frame(width: 22)
                                    .foregroundStyle(.tint)
                                Text(attr.name)
                            }
                        }
                    }
                    .onDelete(perform: deleteAttributes)
                }

                Button { showAddAttribute = true } label: {
                    Label("Attribut hinzufügen", systemImage: "plus")
                }
            }

            LinksSection(
                titleOutgoing: "Links (ausgehend)",
                titleIncoming: "Links (eingehend)",
                outgoing: outgoingLinks,
                incoming: incomingLinks,
                onDeleteOutgoing: { offsets in for i in offsets { modelContext.delete(outgoingLinks[i]) } },
                onDeleteIncoming: { offsets in for i in offsets { modelContext.delete(incomingLinks[i]) } },
                onAdd: { showAddLink = true }
            )
        }
        .navigationTitle(entity.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddAttribute) {
            AddAttributeView(entity: entity)
        }
        .sheet(isPresented: $showAddLink) {
            AddLinkView(
                source: NodeRef(kind: .entity, id: entity.id, label: entity.name, iconSymbolName: entity.iconSymbolName),
                graphID: entity.graphID
            )
        }
    }

    private func deleteAttributes(at offsets: IndexSet) {
        let sorted = entity.attributesList.sorted(by: { $0.name < $1.name })
        for index in offsets {
            let attr = sorted[index]
            deleteLinks(referencing: .attribute, id: attr.id, graphID: entity.graphID)
            entity.removeAttribute(attr)
            modelContext.delete(attr)
        }
        try? modelContext.save()
    }

    private func deleteLinks(referencing kind: NodeKind, id: UUID, graphID: UUID?) {
        let k = kind.rawValue
        let nodeID = id
        let gid = graphID

        let fdSource = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.sourceKindRaw == k && l.sourceID == nodeID && (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdSource) {
            for l in links { modelContext.delete(l) }
        }

        let fdTarget = FetchDescriptor<MetaLink>(
            predicate: #Predicate { l in
                l.targetKindRaw == k && l.targetID == nodeID && (gid == nil || l.graphID == gid)
            }
        )
        if let links = try? modelContext.fetch(fdTarget) {
            for l in links { modelContext.delete(l) }
        }
    }
}
