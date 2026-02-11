//
//  GraphPickerDeleteFlow.swift
//  BrainMesh
//
//  Created by Marc Fechner on 11.02.26.
//

import SwiftUI
import SwiftData

struct GraphPickerDeleteFlow: ViewModifier {
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var graphLock: GraphLockCoordinator

    let graphs: [MetaGraph]
    let uniqueGraphs: [MetaGraph]
    let activeGraphID: UUID?

    @Binding var activeGraphIDString: String

    @Binding var deleteGraph: MetaGraph?
    @Binding var isDeleting: Bool
    @Binding var deleteError: String?

    let onWillDelete: (MetaGraph) -> Void

    func body(content: Content) -> some View {
        content
            .overlay {
                if isDeleting {
                    ZStack {
                        Color.black.opacity(0.08).ignoresSafeArea()
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Lösche…").foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }

            // MARK: Delete confirm
            .alert("Graph löschen?", isPresented: Binding(
                get: { deleteGraph != nil },
                set: { if !$0 { deleteGraph = nil } }
            )) {
                Button("Abbrechen", role: .cancel) { deleteGraph = nil }

                Button("Löschen", role: .destructive) {
                    guard let g = deleteGraph else { return }

                    // Close the alert first to avoid UITableView update inconsistencies.
                    deleteGraph = nil

                    // Optimistically remove the row from the List's frozen snapshot.
                    onWillDelete(g)

                    Task { await performDelete(graph: g) }
                }
            } message: {
                if let g = deleteGraph {
                    deleteMessage(for: g)
                } else {
                    Text("")
                }
            }

            // MARK: Delete error
            .alert("Löschen fehlgeschlagen", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "")
            }
    }

    private func deleteMessage(for graph: MetaGraph) -> Text {
        let isActive = (graph.id == activeGraphID)
        let isLast = (uniqueGraphs.count <= 1)

        if isLast {
            return Text("Dieser Graph ist der letzte. Wenn du ihn löschst, wird automatisch ein neuer leerer „Default“-Graph angelegt.")
        }

        if isActive {
            return Text("Dieser Graph ist aktuell aktiv. Nach dem Löschen wird automatisch auf einen anderen Graph umgeschaltet.")
        }

        return Text("Das löscht den Graph inkl. Entitäten, Attributen, Links, Notizen und Bildern. Diese Aktion kann nicht rückgängig gemacht werden.")
    }

    @MainActor
    private func performDelete(graph: MetaGraph) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        // Let the UI settle for one runloop tick (prevents some UIKit list update edge cases).
        await Task.yield()

        do {
            let currentActive = UUID(uuidString: activeGraphIDString)

            let result = try await GraphDeletionService.deleteGraphCompletely(
                graphToDelete: graph,
                currentActiveGraphID: currentActive,
                graphs: graphs,
                uniqueGraphs: uniqueGraphs,
                modelContext: modelContext,
                graphLock: graphLock
            )

            if let newActive = result.newActiveGraphID {
                activeGraphIDString = newActive.uuidString
            }
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

extension View {
    func graphPickerDeleteFlow(
        graphs: [MetaGraph],
        uniqueGraphs: [MetaGraph],
        activeGraphID: UUID?,
        activeGraphIDString: Binding<String>,
        deleteGraph: Binding<MetaGraph?>,
        isDeleting: Binding<Bool>,
        deleteError: Binding<String?>,
        onWillDelete: @escaping (MetaGraph) -> Void
    ) -> some View {
        modifier(
            GraphPickerDeleteFlow(
                graphs: graphs,
                uniqueGraphs: uniqueGraphs,
                activeGraphID: activeGraphID,
                activeGraphIDString: activeGraphIDString,
                deleteGraph: deleteGraph,
                isDeleting: isDeleting,
                deleteError: deleteError,
                onWillDelete: onWillDelete
            )
        )
    }
}
