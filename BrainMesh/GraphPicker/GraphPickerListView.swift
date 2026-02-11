//
//  GraphPickerListView.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI

struct GraphPickerListView: View {
    let uniqueGraphs: [MetaGraph]
    let hiddenDuplicateCount: Int
    let activeGraphID: UUID?
    let isDeleting: Bool

    let onSelectGraph: (MetaGraph) -> Void
    let onOpenSecurity: (MetaGraph) -> Void
    let onRename: (MetaGraph) -> Void
    let onDelete: (MetaGraph) -> Void
    let onCleanupDuplicates: () -> Void

    var body: some View {
        List {
            Section {
                if uniqueGraphs.isEmpty {
                    Text("Keine Graphen gefunden (das sollte eigentlich nicht passieren).")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(uniqueGraphs, id: \.persistentModelID) { g in
                        GraphPickerRow(
                            graph: g,
                            isActive: g.id == activeGraphID,
                            isDeleting: isDeleting,
                            onSelect: {
                                onSelectGraph(g)
                            },
                            onOpenSecurity: {
                                onOpenSecurity(g)
                            },
                            onRename: {
                                onRename(g)
                            },
                            onDelete: {
                                onDelete(g)
                            }
                        )
                    }
                }
            }

            if hiddenDuplicateCount > 0 {
                Section("Hinweis") {
                    Text("Ich habe \(hiddenDuplicateCount) doppelte Graph-Einträge ausgeblendet (gleiche ID).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        onCleanupDuplicates()
                    } label: {
                        Label("Duplikate entfernen", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                }
            }

            Section {
                Text("Tipp: Links und Picker sind immer auf den aktiven Graph begrenzt – damit du nicht aus Versehen zwei Welten zusammenklebst.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        // UIKit-List consistency: disable row animations inside this sheet.
        .transaction { t in
            t.disablesAnimations = true
            t.animation = nil
        }
    }
}
