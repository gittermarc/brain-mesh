//
//  GraphTransferImportCoordinator+Cleanup.swift
//  BrainMesh
//
//  Removes a checkpointed partial import after cancellation or failure.
//

import Foundation
import SwiftData

nonisolated extension GraphTransferImportCoordinator {

    func cleanupAfterFailedImportPreserving(originalError: Error) throws -> Never {
        context.rollback()

        do {
            try deletePersistedImportRecords()
            try context.save()
        } catch {
            context.rollback()
            throw GraphTransferError.importCleanupFailed
        }

        for localPath in preparedAttachmentCachePaths.sorted() {
            AttachmentStore.delete(localPath: localPath)
        }
        preparedAttachmentCachePaths.removeAll(keepingCapacity: false)

        throw originalError
    }
}

private nonisolated extension GraphTransferImportCoordinator {

    func deletePersistedImportRecords() throws {
        let graphID = newGraphID

        let attachments = try context.fetch(
            FetchDescriptor<MetaAttachment>(
                predicate: #Predicate { attachment in
                    attachment.graphID == graphID
                }
            )
        )
        let detailValues = try context.fetch(
            FetchDescriptor<MetaDetailFieldValue>(
                predicate: #Predicate { value in
                    value.graphID == graphID
                }
            )
        )
        let detailDefinitions = try context.fetch(
            FetchDescriptor<MetaDetailFieldDefinition>(
                predicate: #Predicate { definition in
                    definition.graphID == graphID
                }
            )
        )
        let links = try context.fetch(
            FetchDescriptor<MetaLink>(
                predicate: #Predicate { link in
                    link.graphID == graphID
                }
            )
        )
        let attributes = try context.fetch(
            FetchDescriptor<MetaAttribute>(
                predicate: #Predicate { attribute in
                    attribute.graphID == graphID
                }
            )
        )
        let entities = try context.fetch(
            FetchDescriptor<MetaEntity>(
                predicate: #Predicate { entity in
                    entity.graphID == graphID
                }
            )
        )
        let graphs = try context.fetch(
            FetchDescriptor<MetaGraph>(
                predicate: #Predicate { graph in
                    graph.id == graphID
                }
            )
        )

        for attachment in attachments {
            context.delete(attachment)
        }
        for detailValue in detailValues {
            context.delete(detailValue)
        }
        for detailDefinition in detailDefinitions {
            context.delete(detailDefinition)
        }
        for link in links {
            context.delete(link)
        }
        for attribute in attributes {
            context.delete(attribute)
        }
        for entity in entities {
            context.delete(entity)
        }
        for graph in graphs {
            context.delete(graph)
        }
    }
}
