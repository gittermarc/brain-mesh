//
//  GraphTransferImportCoordinator.swift
//  BrainMesh
//
//  Coordinator state and phase order for graph imports.
//

import Foundation
import SwiftData

typealias GraphTransferImportSaveOperation = @Sendable (ModelContext) throws -> Void

nonisolated final class GraphTransferImportCoordinator {
    let file: GraphExportFileV1
    let container: AnyModelContainer
    let context: ModelContext
    let progress: (@Sendable (GraphTransferProgress) -> Void)?
    let mutationPublisher: any GraphMutationPublishing
    let completionKind: GraphTransferImportCompletionKind
    let saveOperation: GraphTransferImportSaveOperation

    let newGraphID = UUID()

    var entityIDMap: [UUID: UUID] = [:]
    var attributeIDMap: [UUID: UUID] = [:]
    var fieldIDMap: [UUID: UUID] = [:]

    var entitiesByNewID: [UUID: MetaEntity] = [:]
    var attributesByNewID: [UUID: MetaAttribute] = [:]

    var importedValues = 0
    var importedLinks = 0
    var skippedLinks = 0
    var insertedSinceLastSave = 0
    var preparedAttachmentCachePaths = Set<String>()

    init(
        file: GraphExportFileV1,
        container: AnyModelContainer,
        progress: (@Sendable (GraphTransferProgress) -> Void)?,
        mutationPublisher: any GraphMutationPublishing,
        completionKind: GraphTransferImportCompletionKind,
        saveOperation: @escaping GraphTransferImportSaveOperation
    ) {
        self.file = file
        self.container = container
        self.context = ModelContext(container.container)
        self.context.autosaveEnabled = false
        self.progress = progress
        self.mutationPublisher = mutationPublisher
        self.completionKind = completionKind
        self.saveOperation = saveOperation
    }

    func runAsNewGraphRemap() async throws -> ImportResult {
        do {
            _ = try await runCoreAsNewGraphRemap()
            return try await finalizeImport()
        } catch {
            try cleanupAfterFailedImportPreserving(originalError: error)
        }
    }

    func runFullBackupAsNewGraphRemap(
        manifest: GraphBackupManifestV2,
        packageURL: URL
    ) async throws -> ImportResult {
        do {
            _ = try await runCoreAsNewGraphRemap()
            let attachmentSummary = try await importBackupAttachments(
                manifest: manifest,
                packageURL: packageURL
            )
            return try await finalizeImport(
                importedAttachments: attachmentSummary.importedAttachments,
                skippedAttachments: attachmentSummary.skippedAttachments,
                warnings: attachmentSummary.warnings
            )
        } catch {
            try cleanupAfterFailedImportPreserving(originalError: error)
        }
    }

    func runCoreAsNewGraphRemap() async throws -> GraphTransferCoreImportResult {
        createGraph()
        try await importEntities()
        try await importFieldDefinitions()
        try await importAttributes()
        try await importDetailFieldValues()
        try await importLinks()

        return GraphTransferCoreImportResult(
            newGraphID: newGraphID,
            entityIDMap: entityIDMap,
            attributeIDMap: attributeIDMap,
            insertedCounts: coreInsertedCounts,
            skippedLinks: skippedLinks
        )
    }

    var coreInsertedCounts: CountsDTO {
        CountsDTO(
            graphs: 1,
            entities: entitiesByNewID.count,
            attributes: attributesByNewID.count,
            detailFieldDefinitions: fieldIDMap.count,
            detailFieldValues: importedValues,
            links: importedLinks
        )
    }
}
