//
//  NodeLinksSectionView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import SwiftUI
import SwiftData

struct NodeLinksSectionView: View {
    @Environment(\.modelContext) private var modelContext

    let outgoing: [MetaLink]
    let incoming: [MetaLink]

    @Binding var showAddLink: Bool
    @Binding var showBulkLink: Bool

    var body: some View {
        LinksSection(
            titleOutgoing: "Ausgehend",
            titleIncoming: "Eingehend",
            outgoing: outgoing,
            incoming: incoming,
            onDeleteOutgoing: deleteOutgoing,
            onDeleteIncoming: deleteIncoming,
            onAddSingle: { showAddLink = true },
            onAddBulk: { showBulkLink = true }
        )
    }

    private func deleteOutgoing(at offsets: IndexSet) {
        for i in offsets {
            guard outgoing.indices.contains(i) else { continue }
            modelContext.delete(outgoing[i])
        }
    }

    private func deleteIncoming(at offsets: IndexSet) {
        for i in offsets {
            guard incoming.indices.contains(i) else { continue }
            modelContext.delete(incoming[i])
        }
    }
}
