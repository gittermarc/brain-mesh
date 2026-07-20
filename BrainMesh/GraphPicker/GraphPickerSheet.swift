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
/// This file stays focused on state + routing.
/// The presentation lives in `GraphPicker/*`.
struct GraphPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var graphLock: GraphLockCoordinator
    @EnvironmentObject private var proStore: ProEntitlementStore

    @AppStorage(BMAppStorageKeys.activeGraphID) private var activeGraphIDString: String = ""

    @Query(sort: [SortDescriptor(\MetaGraph.createdAt, order: .forward)])
    private var graphs: [MetaGraph]

    @State private var showProPaywall = false
    @State private var paywallFeature: ProFeature = .moreGraphs

    // Item-driven sheet to avoid SwiftUI "blank sheet" races.
    @State private var securityGraph: MetaGraph?
    @State private var nameEditorMode: GraphPickerNameEditorMode?

    @State private var deleteGraph: MetaGraph?
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var managementError: String?

    // Stable snapshot for presentation while delete transitions run.
    @State private var displayedGraphs: [MetaGraph] = []
    @State private var displayedHiddenDuplicateCount: Int = 0

    @State private var didInitialDedupe = false

    private var activeID: UUID? { UUID(uuidString: activeGraphIDString) }

    // Equatable signature so we can react to Query changes without needing graphs to be Equatable.
    private var graphsSignature: [UUID] { graphs.map(\.id) }

    var body: some View {
        NavigationStack {
            GraphPickerListView(
                uniqueGraphs: displayedGraphs,
                hiddenDuplicateCount: displayedHiddenDuplicateCount,
                activeGraphID: activeID,
                isDeleting: isDeleting,
                isProActive: proStore.isProActive,
                freeGraphLimit: ProLimits.freeGraphLimit,
                onAddGraph: {
                    beginCreateGraph()
                },
                onSelectGraph: { graph in
                    selectGraph(graph)
                },
                onOpenSecurity: { graph in
                    securityGraph = graph
                },
                onRename: { graph in
                    beginRenameGraph(graph)
                },
                onDelete: { graph in
                    deleteGraph = graph
                },
                onCleanupDuplicates: {
                    cleanupDuplicateGraphs()
                }
            )
            .navigationTitle("Graphen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                        .disabled(isDeleting)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        beginCreateGraph()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(isDeleting)
                }
            }
            .graphPickerDeleteFlow(
                graphs: graphs,
                uniqueGraphs: displayedGraphs,
                activeGraphID: activeID,
                activeGraphIDString: $activeGraphIDString,
                deleteGraph: $deleteGraph,
                isDeleting: $isDeleting,
                deleteError: $deleteError,
                onWillDelete: { graph in
                    optimisticallyRemoveFromDisplayed(graph)
                }
            )
        }
        .task {
            if !didInitialDedupe {
                didInitialDedupe = true
                do {
                    _ = try await GraphDedupeService.removeDuplicateGraphs(
                        using: modelContext
                    )
                } catch is CancellationError {
                    return
                } catch {
                    managementError = error.localizedDescription
                }
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
        .sheet(item: $nameEditorMode) { mode in
            GraphPickerNameEditorSheet(
                title: mode.title,
                message: mode.message,
                confirmTitle: mode.confirmTitle,
                initialText: mode.initialText,
                placeholder: "Name"
            ) { cleanedName in
                try await commitNameEditor(mode: mode, cleanedName: cleanedName)
            }
        }
        .sheet(item: $securityGraph) { graph in
            GraphSecuritySheet(graph: graph)
        }
        .sheet(isPresented: $showProPaywall) {
            ProPaywallView(feature: paywallFeature)
        }
        .alert("Graphen konnten nicht aktualisiert werden", isPresented: Binding(
            get: { managementError != nil },
            set: { if $0 == false { managementError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(managementError ?? "")
        }
        .presentationDetents([.medium, .large])
    }

    private func rebuildDisplayed() {
        var seen = Set<UUID>()
        let unique = graphs.filter { seen.insert($0.id).inserted }
        displayedGraphs = unique
        displayedHiddenDuplicateCount = max(0, graphs.count - unique.count)
    }

    private func optimisticallyRemoveFromDisplayed(_ graph: MetaGraph) {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            displayedGraphs.removeAll { $0.id == graph.id }
            // Intentionally keep displayedHiddenDuplicateCount stable during delete.
        }
    }

    private func beginCreateGraph() {
        guard !isDeleting else { return }

        if !proStore.isProActive && displayedGraphs.count >= ProLimits.freeGraphLimit {
            paywallFeature = .moreGraphs
            showProPaywall = true
            return
        }

        nameEditorMode = .create
    }

    private func beginRenameGraph(_ graph: MetaGraph) {
        guard !isDeleting else { return }
        nameEditorMode = .rename(graph)
    }

    @MainActor
    private func commitNameEditor(
        mode: GraphPickerNameEditorMode,
        cleanedName: String
    ) async throws {
        switch mode {
        case .create:
            let graph = MetaGraph(name: cleanedName)
            let batch = try GraphMutationBatchFactory.graphCreated(graphID: graph.id)
            modelContext.insert(graph)
            _ = try await GraphMutationCommitter().commit(batch, in: modelContext)
            activeGraphIDString = graph.id.uuidString
            dismiss()

        case .rename(let graph):
            guard graph.name != cleanedName else { return }
            let batch = try GraphMutationBatchFactory.graphUpdated(graphID: graph.id)
            graph.name = cleanedName
            _ = try await GraphMutationCommitter().commit(batch, in: modelContext)
        }
    }

    private func selectGraph(_ graph: MetaGraph) {
        if graph.isProtected && !graphLock.isUnlocked(graphID: graph.id) {
            graphLock.requestUnlock(
                for: graph,
                purpose: .switchGraph,
                onSuccess: {
                    activeGraphIDString = graph.id.uuidString
                    dismiss()
                },
                onCancel: {
                }
            )
        } else {
            activeGraphIDString = graph.id.uuidString
            dismiss()
        }
    }

    // Deletes only surplus duplicates with identical UUID while keeping the oldest one.
    private func cleanupDuplicateGraphs() {
        Task { @MainActor in
            do {
                _ = try await GraphDedupeService.removeDuplicateGraphs(
                    using: modelContext
                )
                if !isDeleting {
                    rebuildDisplayed()
                }
            } catch is CancellationError {
                return
            } catch {
                managementError = error.localizedDescription
            }
        }
    }

}

private enum GraphPickerNameEditorMode: Identifiable {
    case create
    case rename(MetaGraph)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .rename(let graph):
            return "rename-\(graph.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .create:
            return "Neuer Graph"
        case .rename:
            return "Graph umbenennen"
        }
    }

    var confirmTitle: String {
        switch self {
        case .create:
            return "Erstellen"
        case .rename:
            return "Speichern"
        }
    }

    var message: String {
        switch self {
        case .create:
            return "Jeder Graph ist eine eigene Wissensdatenbank."
        case .rename:
            return "Der neue Name wird überall in der App übernommen."
        }
    }

    var initialText: String {
        switch self {
        case .create:
            return ""
        case .rename(let graph):
            return graph.name
        }
    }
}
