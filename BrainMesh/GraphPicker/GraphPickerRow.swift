//
//  GraphPickerRow.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI

struct GraphPickerRow: View {
    let graph: MetaGraph
    let isActive: Bool
    let isDeleting: Bool

    let onSelect: () -> Void
    let onOpenSecurity: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject private var graphLock: GraphLockCoordinator

    var body: some View {
        HStack(spacing: 12) {
            Text(graph.name)
                .lineLimit(1)

            Spacer(minLength: 0)

            if graph.isProtected {
                Image(systemName: graphLock.isUnlocked(graphID: graph.id) ? "lock.open" : "lock.fill")
                    .foregroundStyle(.secondary)
            }

            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }

            Menu {
                Button {
                    onOpenSecurity()
                } label: {
                    Label("Schutz", systemImage: "lock")
                }

                Button {
                    onRename()
                } label: {
                    Label("Umbenennen", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isDeleting else { return }
            onSelect()
        }
        .allowsHitTesting(!isDeleting)
    }
}
