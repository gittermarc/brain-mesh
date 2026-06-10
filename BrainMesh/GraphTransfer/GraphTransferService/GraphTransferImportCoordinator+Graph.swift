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

    func finalizeImport() throws -> ImportResult {
        progress?(GraphTransferImportProgressFactory.saving())
        try saveContext()
        progress?(GraphTransferImportProgressFactory.done())

        return ImportResult(
            newGraphID: newGraphID,
            insertedCounts: CountsDTO(
                graphs: 1,
                entities: entitiesByNewID.count,
                attributes: attributesByNewID.count,
                detailFieldDefinitions: fieldIDMap.count,
                detailFieldValues: importedValues,
                links: importedLinks
            ),
            skippedLinks: skippedLinks
        )
    }
}
