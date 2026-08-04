//
//  GraphTransferImportCoordinator+Graph.swift
//  BrainMesh
//
//  Graph creation and import finalization.
//

import Foundation
import SwiftData

nonisolated extension GraphTransferImportCoordinator {

    func createGraph() {
        progress?(GraphTransferImportProgressFactory.creatingGraph())

        let graph = MetaGraph(name: file.graph.name)
        graph.id = newGraphID
        graph.createdAt = file.graph.createdAt
        context.insert(graph)
        importedGraph = graph
    }

    func finalizeImport(
        importedAttachments: Int = 0,
        skippedAttachments: Int = 0,
        warnings: [String] = []
    ) async throws -> ImportResult {
        let batch: GraphMutationBatch
        switch completionKind {
        case .imported:
            batch = try GraphMutationBatchFactory.graphImported(graphID: newGraphID)
        case .replaced:
            batch = try GraphMutationBatchFactory.graphReplaced(graphID: newGraphID)
        }

        progress?(GraphTransferImportProgressFactory.saving())
        let committer = GraphMutationCommitter(publisher: mutationPublisher)
        _ = try await committer.commitCallerIsolated(
            batch,
            prepare: {
                importedGraph?.searchSourceRevision = batch.id
            },
            save: {
                try saveContext()
            },
            rollback: {
                context.rollback()
            }
        )

        preparedAttachmentCachePaths.removeAll(keepingCapacity: false)
        progress?(GraphTransferImportProgressFactory.done())

        return ImportResult(
            newGraphID: newGraphID,
            insertedCounts: coreInsertedCounts,
            skippedLinks: skippedLinks,
            importedAttachments: importedAttachments,
            skippedAttachments: skippedAttachments,
            warnings: warnings
        )
    }
}
