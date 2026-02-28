//
//  GraphReplacePickerSheet.swift
//  BrainMesh
//
//  Minimal picker to choose a graph that will be deleted before importing.
//

import SwiftUI

struct GraphReplacePickerSheet: View {

    let candidates: [GraphTransferViewModel.ReplaceCandidate]
    let onCancel: () -> Void
    let onConfirmReplace: (GraphTransferViewModel.ReplaceCandidate) -> Void

    @State private var confirmCandidate: GraphTransferViewModel.ReplaceCandidate?

    var body: some View {
        List {
            if candidates.isEmpty {
                ContentUnavailableView(
                    "Keine Graphen",
                    systemImage: "circle.slash",
                    description: Text("Es gibt aktuell keine Graphen, die ersetzt werden können.")
                )
            } else {
                Section {
                    ForEach(candidates) { c in
                        Button {
                            confirmCandidate = c
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name)
                                    .font(.headline)
                                Text(c.createdAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Graph auswählen")
                } footer: {
                    Text("Der gewählte Graph wird gelöscht und kann nicht wiederhergestellt werden.")
                }
            }
        }
        .navigationTitle("Graph ersetzen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") { onCancel() }
            }
        }
        .alert(
            "Graph wirklich ersetzen?",
            isPresented: Binding(
                get: { confirmCandidate != nil },
                set: { if !$0 { confirmCandidate = nil } }
            ),
            actions: {
                Button("Abbrechen", role: .cancel) {
                    confirmCandidate = nil
                }
                Button("Ersetzen & Importieren", role: .destructive) {
                    if let c = confirmCandidate {
                        confirmCandidate = nil
                        onConfirmReplace(c)
                    }
                }
            },
            message: {
                if let c = confirmCandidate {
                    Text("Graph \"\(c.name)\" wird gelöscht und kann nicht wiederhergestellt werden.")
                } else {
                    Text("Der Graph wird gelöscht und kann nicht wiederhergestellt werden.")
                }
            }
        )
    }
}

#Preview {
    NavigationStack {
        GraphReplacePickerSheet(
            candidates: [
                .init(id: UUID(), name: "Projekt", createdAt: Date()),
                .init(id: UUID(), name: "Privat", createdAt: Date().addingTimeInterval(-86400 * 12))
            ],
            onCancel: {},
            onConfirmReplace: { _ in }
        )
    }
}
