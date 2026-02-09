//
//  LinksSection.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
//

import SwiftUI

struct LinksSection: View {
    let titleOutgoing: String
    let titleIncoming: String

    let outgoing: [MetaLink]
    let incoming: [MetaLink]

    let onDeleteOutgoing: (IndexSet) -> Void
    let onDeleteIncoming: (IndexSet) -> Void
    let onAdd: () -> Void

    var body: some View {
        Section(titleOutgoing) {
            if outgoing.isEmpty {
                Text("Keine ausgehenden Links.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(outgoing) { link in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("→ \(link.targetLabel)")
                        if let note = link.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: onDeleteOutgoing)
            }

            Button(action: onAdd) {
                Label("Link hinzufügen", systemImage: "link.badge.plus")
            }
        }

        Section(titleIncoming) {
            if incoming.isEmpty {
                Text("Keine eingehenden Links.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(incoming) { link in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("← \(link.sourceLabel)")
                        if let note = link.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: onDeleteIncoming)
            }
        }
    }
}
