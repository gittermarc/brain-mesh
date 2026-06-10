//
//  GraphTransferViewModel+Core.swift
//  BrainMesh
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

extension GraphTransferViewModel {

    func configureIfNeeded(container: AnyModelContainer) {
        guard didConfigure == false else { return }
        didConfigure = true
        Task {
            await GraphTransferService.shared.configure(container: container)
        }
    }

    func refreshActiveGraphName(using modelContext: ModelContext, activeGraphIDString: String) {
        refreshActiveGraphMetadata(using: modelContext, activeGraphIDString: activeGraphIDString)
    }

    func refreshActiveGraphMetadata(using modelContext: ModelContext, activeGraphIDString: String) {
        guard let id = UUID(uuidString: activeGraphIDString) else {
            activeGraphName = "—"
            activeGraphAttachmentEstimate = .empty
            return
        }

        activeGraphName = fetchActiveGraphName(for: id, using: modelContext)
        activeGraphAttachmentEstimate = fetchAttachmentEstimate(for: id, using: modelContext)
    }

    func requestExportConfirm() {
        guard isBusy == false else { return }
        isShowingExportConfirm = true
    }

    func exportConfirmMessage(activeGraphName: String) -> String {
        GraphTransferExportCopy.confirmMessage(
            kind: exportKind,
            activeGraphName: activeGraphName,
            includeNotes: includeNotes,
            includeIcons: includeIcons,
            includeHeaderImages: includeImages,
            includeAttachments: includeAttachments,
            attachmentEstimate: activeGraphAttachmentEstimate
        )
    }

    func resetExport() {
        exportState = .idle
        exportedFileURL = nil
    }

    func resetImport() {
        importState = .idle
        selectedImportURL = nil
    }

    var exportContentType: UTType {
        guard let url = exportedFileURL else {
            return exportKind.contentType
        }
        if url.pathExtension.lowercased() == GraphBackupFormat.filenameExtension {
            return .brainMeshBackup
        }
        return .brainMeshGraph
    }

    func fetchUniqueGraphs(using modelContext: ModelContext) -> [MetaGraph] {
        var fd = FetchDescriptor<MetaGraph>()
        fd.sortBy = [SortDescriptor(\.createdAt, order: .forward)]
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

private extension GraphTransferViewModel {

    func fetchActiveGraphName(for id: UUID, using modelContext: ModelContext) -> String {
        let gid = id
        var fd = FetchDescriptor<MetaGraph>(predicate: #Predicate { graph in
            graph.id == gid
        })
        fd.fetchLimit = 1

        do {
            if let graph = try modelContext.fetch(fd).first {
                let name = graph.name.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? "Graph" : name
            }
            return "—"
        } catch {
            return "—"
        }
    }

    func fetchAttachmentEstimate(for id: UUID, using modelContext: ModelContext) -> GraphTransferAttachmentEstimate {
        let gid = id
        let fd = FetchDescriptor<MetaAttachment>(predicate: #Predicate { attachment in
            attachment.graphID == gid
        })

        do {
            let attachments = try modelContext.fetch(fd)
            let totalBytes = attachments.reduce(Int64(0)) { partialResult, attachment in
                partialResult + Int64(max(0, attachment.byteCount))
            }
            return GraphTransferAttachmentEstimate(count: attachments.count, byteCount: totalBytes)
        } catch {
            return .empty
        }
    }
}
