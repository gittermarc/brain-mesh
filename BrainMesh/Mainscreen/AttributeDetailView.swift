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
        Form {
            Section("Attribut") {
                TextField("Name", text: $attribute.name)
                if let e = attribute.owner {
                    Text("Entität: \(e.name)").foregroundStyle(.secondary)
                }
            }
            NotesAndPhotoSection(
                notes: $attribute.notes,
                imageData: $attribute.imageData,
                imagePath: $attribute.imagePath,
                stableID: attribute.id
            )

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
        .navigationTitle(attribute.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddLink) {
            AddLinkView(
                source: NodeRef(kind: .attribute, id: attribute.id, label: attribute.displayName),
                graphID: attribute.graphID
            )
        }
    }
}
