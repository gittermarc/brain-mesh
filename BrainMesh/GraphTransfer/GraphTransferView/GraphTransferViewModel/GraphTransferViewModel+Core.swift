//
//  GraphTransferViewModel+Core.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphTransferViewModel {

    func configureIfNeeded(container: AnyModelContainer) {
        guard didConfigure == false else { return }
        didConfigure = true
        Task {
            await GraphTransferService.shared.configure(container: container)
        }
    }

    func refreshActiveGraphName(using modelContext: ModelContext, activeGraphIDString: String) {
        guard let id = UUID(uuidString: activeGraphIDString) else {
            activeGraphName = "—"
            return
        }

        let gid = id
        var fd = FetchDescriptor<MetaGraph>(predicate: #Predicate { graph in
            graph.id == gid
        })
        fd.fetchLimit = 1

        do {
            if let graph = try modelContext.fetch(fd).first {
                let name = graph.name.trimmingCharacters(in: .whitespacesAndNewlines)
                activeGraphName = name.isEmpty ? "Graph" : name
            } else {
                activeGraphName = "—"
            }
        } catch {
            activeGraphName = "—"
        }
    }

    func requestExportConfirm() {
        guard isBusy == false else { return }
        isShowingExportConfirm = true
    }

    func exportConfirmMessage(activeGraphName: String) -> String {
        var parts: [String] = []
        parts.append("Aktiver Graph: \(activeGraphName)")

        var options: [String] = []
        if includeNotes { options.append("Notizen") }
        if includeIcons { options.append("Icons") }
        if includeImages { options.append("Bilder") }

        if options.isEmpty {
            parts.append("Export ohne Zusatzdaten.")
        } else {
            parts.append("Enthält: \(options.joined(separator: ", ")).")
        }

        return parts.joined(separator: "\n")
    }

    func resetExport() {
        exportState = .idle
        exportedFileURL = nil
    }

    func resetImport() {
        importState = .idle
        selectedImportURL = nil
    }

    func fetchUniqueGraphs(using modelContext: ModelContext) -> [MetaGraph] {
        var fd = FetchDescriptor<MetaGraph>()
        fd.sortBy = [SortDescriptor(\MetaGraph.createdAt, order: .forward)]
        do {
            let graphs = try modelContext.fetch(fd)
            var seen = Set<UUID>()
            return graphs.filter { seen.insert($0.id).inserted }
        } catch {
            return []
        }
    }

    func fetchGraphRecord(for id: UUID, using modelContext: ModelContext) throws -> MetaGraph {
        let gid = id
        var fd = FetchDescriptor<MetaGraph>(predicate: #Predicate { graph in
            graph.id == gid
        })
        fd.fetchLimit = 1
        if let graph = try modelContext.fetch(fd).first {
            return graph
        }
        throw GraphTransferError.graphNotFound(graphID: id)
    }
}
