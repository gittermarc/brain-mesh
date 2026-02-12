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
    let onAddSingle: () -> Void
    let onAddBulk: () -> Void

    var body: some View {
        Section {
            if outgoing.isEmpty {
                Text("Keine ausgehenden Links.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(outgoing) { link in
                    LinkRow(directionSymbol: "arrow.up.right", title: link.targetLabel, note: link.note)
                }
                .onDelete(perform: onDeleteOutgoing)
            }

            Menu {
                Button(action: onAddSingle) {
                    Label("Link hinzufügen", systemImage: "link.badge.plus")
                }
                Button(action: onAddBulk) {
                    Label("Mehrere Links hinzufügen…", systemImage: "link.badge.plus")
                }
            } label: {
                Label("Link hinzufügen", systemImage: "link.badge.plus")
            }
        } header: {
            DetailSectionHeader(
                title: titleOutgoing,
                systemImage: "arrow.up.right",
                subtitle: "Verbindungen von diesem Node zu anderen Nodes."
            )
        }

        Section {
            if incoming.isEmpty {
                Text("Keine eingehenden Links.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(incoming) { link in
                    LinkRow(directionSymbol: "arrow.down.left", title: link.sourceLabel, note: link.note)
                }
                .onDelete(perform: onDeleteIncoming)
            }
        } header: {
            DetailSectionHeader(
                title: titleIncoming,
                systemImage: "arrow.down.left",
                subtitle: "Verbindungen anderer Nodes zu diesem Node."
            )
        }
    }
}

private struct LinkRow: View {
    let directionSymbol: String
    let title: String
    let note: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: directionSymbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 22)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
