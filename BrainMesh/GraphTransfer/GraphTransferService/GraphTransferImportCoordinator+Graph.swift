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
    }

    func finalizeImport(
        importedAttachments: Int = 0,
        skippedAttachments: Int = 0,
        warnings: [String] = []
    ) throws -> ImportResult {
        progress?(GraphTransferImportProgressFactory.saving())
        try saveContext()
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
