//
//  GraphPickerSheet.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import SwiftUI
import SwiftData

/// Sheet to switch between graphs and manage them (rename, delete, security).
///
/// This file is intentionally kept small: state + routing.
/// The heavy UI parts live in `GraphPicker/*`.
struct GraphPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var graphLock: GraphLockCoordinator

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var showAdd = false
    @State private var newName = ""

    // Item-driven sheet to avoid SwiftUI "blank sheet" races.
    @State private var securityGraph: MetaGraph?

    @State private var renameGraph: MetaGraph?
    @State private var renameText: String = ""

    @State private var deleteGraph: MetaGraph?
    @State private var isDeleting = false
    @State private var deleteError: String?

    // Frozen snapshot for the List (prevents UITableView inconsistency crashes during deletes).
    @State private var displayedGraphs: [MetaGraph] = []
    @State private var displayedHiddenDuplicateCount: Int = 0

    @State private var didInitialDedupe = false

    private var activeID: UUID? { UUID(uuidString: activeGraphIDString) }

    // Equatable signature so we can react to Query changes without needing graphs to be Equatable.
    private var graphsSignature: [UUID] { graphs.map(\MetaGraph.id) }

    var body: some View {
        NavigationStack {
            GraphPickerListView(
                uniqueGraphs: displayedGraphs,
                hiddenDuplicateCount: displayedHiddenDuplicateCount,
                activeGraphID: activeID,
                isDeleting: isDeleting,
                onSelectGraph: { g in
                    selectGraph(g)
                },
                onOpenSecurity: { g in
                    securityGraph = g
                },
                onRename: { g in
                    renameGraph = g
                    renameText = g.name
                },
                onDelete: { g in
                    deleteGraph = g
                },
                onCleanupDuplicates: {
                    cleanupDuplicateGraphs()
                }
            )
            .navigationTitle("Graphen")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                        .disabled(isDeleting)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isDeleting)
                }
            }

            // MARK: Add graph
            .alert("Neuer Graph", isPresented: $showAdd) {
                TextField("Name", text: $newName)
                Button("Abbrechen", role: .cancel) { newName = "" }
                Button("Erstellen") {
                    let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let g = MetaGraph(name: cleaned.isEmpty ? "Neuer Graph" : cleaned)
                    modelContext.insert(g)
                    try? modelContext.save()
                    activeGraphIDString = g.id.uuidString
                    dismiss()
                }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } message: {
                Text("Jeder Graph ist eine eigene Wissensdatenbank.")
            }

            // MARK: Rename
            .graphPickerRenameSheet(renameGraph: $renameGraph, renameText: $renameText)

            // MARK: Delete
            .graphPickerDeleteFlow(
                graphs: graphs,
                uniqueGraphs: displayedGraphs,
                activeGraphID: activeID,
                activeGraphIDString: $activeGraphIDString,
                deleteGraph: $deleteGraph,
                isDeleting: $isDeleting,
                deleteError: $deleteError,
                onWillDelete: { g in
                    optimisticallyRemoveFromDisplayed(g)
                }
            )
        }
        .task {
            if !didInitialDedupe {
                didInitialDedupe = true
                _ = GraphDedupeService.removeDuplicateGraphs(using: modelContext)
            }
            rebuildDisplayed()
        }
        .onChange(of: graphsSignature) { _, _ in
            if !isDeleting {
                rebuildDisplayed()
            }
        }
        .onChange(of: isDeleting) { _, deleting in
            if !deleting {
                rebuildDisplayed()
            }
        }
        .sheet(item: $securityGraph) { g in
            GraphSecuritySheet(graph: g)
        }
        .presentationDetents([.medium, .large])
    }

    private func rebuildDisplayed() {
        var seen = Set<UUID>()
        let unique = graphs.filter { seen.insert($0.id).inserted }
        displayedGraphs = unique
        displayedHiddenDuplicateCount = max(0, graphs.count - unique.count)
    }

    private func optimisticallyRemoveFromDisplayed(_ g: MetaGraph) {
        var tx = Transaction()
        tx.animation = nil
        withTransaction(tx) {
            displayedGraphs.removeAll { $0.id == g.id }
            // Intentionally keep displayedHiddenDuplicateCount stable during delete.
        }
    }

    private func selectGraph(_ g: MetaGraph) {
        if g.isProtected && !graphLock.isUnlocked(graphID: g.id) {
            graphLock.requestUnlock(
                for: g,
                purpose: .switchGraph,
                onSuccess: {
                    activeGraphIDString = g.id.uuidString
                    dismiss()
                },
                onCancel: {
                }
            )
        } else {
            activeGraphIDString = g.id.uuidString
            dismiss()
        }
    }

    // ✅ Löscht nur überzählige Duplikate mit identischer UUID (behält den ältesten)
    private func cleanupDuplicateGraphs() {
        var byID: [UUID: [MetaGraph]] = [:]
        for g in graphs {
            byID[g.id, default: []].append(g)
        }

        for (_, list) in byID where list.count > 1 {
            let sorted = list.sorted { $0.createdAt < $1.createdAt }
            for dup in sorted.dropFirst() {
                modelContext.delete(dup)
            }
        }

        try? modelContext.save()
        if !isDeleting {
            rebuildDisplayed()
        }
    }
}
