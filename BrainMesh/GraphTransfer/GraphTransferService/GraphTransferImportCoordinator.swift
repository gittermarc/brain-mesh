//
//  GraphTransferImportCoordinator.swift
//  BrainMesh
//
//  Coordinator state and phase order for graph imports.
//

import Foundation
import SwiftData

nonisolated final class GraphTransferImportCoordinator {
    let file: GraphExportFileV1
    let context: ModelContext
    let progress: (@Sendable (GraphTransferProgress) -> Void)?

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

    init(
        file: GraphExportFileV1,
        container: AnyModelContainer,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) {
        self.file = file
        self.context = ModelContext(container.container)
        self.context.autosaveEnabled = false
        self.progress = progress
    }

    func runAsNewGraphRemap() async throws -> ImportResult {
        createGraph()
        try await importEntities()
        try await importFieldDefinitions()
        try await importAttributes()
        try await importDetailFieldValues()
        try await importLinks()
        return try finalizeImport()
    }
}
