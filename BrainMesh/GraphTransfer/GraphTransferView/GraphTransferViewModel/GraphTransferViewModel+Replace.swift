//
//  GraphTransferViewModel+Replace.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphTransferViewModel {

    func presentReplacePicker(using modelContext: ModelContext) {
        isShowingImportLimitAlert = false
        isShowingProPaywall = false

        let uniqueGraphs = fetchUniqueGraphs(using: modelContext)
        replaceCandidates = uniqueGraphs
            .sorted { $0.createdAt < $1.createdAt }
            .map { graph in
                let name = graph.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return ReplaceCandidate(id: graph.id, name: name.isEmpty ? "Graph" : name, createdAt: graph.createdAt)
            }

        isShowingReplaceSheet = true
    }

    func presentProPaywall() {
        isShowingImportLimitAlert = false
        isShowingReplaceSheet = false
        isShowingProPaywall = true
    }

    func replaceAndImport(
        candidate: ReplaceCandidate,
        modelContext: ModelContext,
        graphLock: GraphLockCoordinator,
        currentActiveGraphIDString: String,
        setActiveGraphIDString: @MainActor @escaping (String) -> Void
    ) async {
        guard isBusy == false else { return }
        guard selectedImportURL != nil else { return }
        guard selectedPreviewAllowsImport else {
            showSelectedPreviewCannotImport()
            return
        }

        do {
            let activeID = UUID(uuidString: currentActiveGraphIDString)
            let uniqueGraphs = fetchUniqueGraphs(using: modelContext)
            let graphRecord = try fetchGraphRecord(for: candidate.id, using: modelContext)

            let deleteResult = try await GraphDeletionService.deleteGraphCompletely(
                graphToDelete: graphRecord,
                currentActiveGraphID: activeID,
                graphs: uniqueGraphs,
                uniqueGraphs: uniqueGraphs,
                modelContext: modelContext,
                graphLock: graphLock
            )

            if let newActive = deleteResult.newActiveGraphID {
                await MainActor.run {
                    setActiveGraphIDString(newActive.uuidString)
                }
            }

            await performImport()
        } catch {
            alertState = AlertState(title: "Graph ersetzen", message: "Löschen fehlgeschlagen.")
        }
    }
}
