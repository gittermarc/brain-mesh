//
//  GraphTransferService+Import.swift
//  BrainMesh
//
//  Import implementation (inspect + import modes + remap).
//

import Foundation
import SwiftData

extension GraphTransferService {

    func inspectFileImpl(url: URL) async throws -> ImportPreview {
        guard container != nil else { throw GraphTransferError.notConfigured }

        let file = try Self.decodeValidatedImportFile(url: url)
        return ImportPreview(
            graphName: file.graph.name,
            exportedAt: file.exportedAt,
            version: file.version,
            counts: file.counts
        )
    }

    func importGraphImpl(
        from url: URL,
        mode: ImportMode,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) async throws -> ImportResult {
        guard let container else { throw GraphTransferError.notConfigured }

        progress?(GraphTransferImportProgressFactory.inspecting())
        let file = try Self.decodeValidatedImportFile(url: url)

        switch mode {
        case .asNewGraphRemap:
            let coordinator = GraphTransferImportCoordinator(
                file: file,
                container: container,
                progress: progress
            )
            return try await coordinator.runAsNewGraphRemap()
        }
    }
}

// MARK: - Import (Remap)

private extension GraphTransferService {

    enum ImportTuning {
        static let saveBatchSize: Int = 500
        static let cancellationStride: Int = 50
        static let yieldStride: Int = 200
        static let cancellationStrideValuesAndLinks: Int = 100
        static let yieldStrideValuesAndLinks: Int = 300
    }

    static func decodeValidatedImportFile(url: URL) throws -> GraphExportFileV1 {
        let data = try GraphTransferFileIO.readFileData(url: url)
        let file = try GraphTransferCodec.decode(data)
        try GraphTransferValidator.validate(exportFile: file)
        return file
    }
}

private nonisolated final class GraphTransferImportCoordinator {
    private let file: GraphExportFileV1
    private let context: ModelContext
    private let progress: (@Sendable (GraphTransferProgress) -> Void)?

    private let newGraphID = UUID()

    private var entityIDMap: [UUID: UUID] = [:]
    private var attributeIDMap: [UUID: UUID] = [:]
    private var fieldIDMap: [UUID: UUID] = [:]

    private var entitiesByNewID: [UUID: MetaEntity] = [:]
    private var attributesByNewID: [UUID: MetaAttribute] = [:]

    private var importedValues = 0
    private var importedLinks = 0
    private var skippedLinks = 0
    private var insertedSinceLastSave = 0

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

private nonisolated extension GraphTransferImportCoordinator {

    func createGraph() {
        progress?(GraphTransferImportProgressFactory.creatingGraph())

        let graph = MetaGraph(name: file.graph.name)
        graph.id = newGraphID
        graph.createdAt = file.graph.createdAt
        context.insert(graph)
    }

    func importEntities() async throws {
        let totalEntities = file.entities.count
        progress?(GraphTransferImportProgressFactory.phaseStart(
            .entities,
            total: totalEntities,
            label: "Entitäten werden importiert…"
        ))

        for (idx, dto) in file.entities.enumerated() {
            try await performCheckpoint(
                index: idx,
                cancellationStride: GraphTransferService.ImportTuning.cancellationStride,
                yieldStride: GraphTransferService.ImportTuning.yieldStride
            )

            let newID = UUID()
            entityIDMap[dto.id] = newID

            let entity = MetaEntity(name: dto.name, graphID: newGraphID, iconSymbolName: dto.iconSymbolName)
            entity.id = newID
            entity.createdAt = dto.createdAt
            entity.notes = dto.notes
            entity.imageData = dto.imageData
            entity.imagePath = nil

            context.insert(entity)
            entitiesByNewID[newID] = entity

            try recordInsertion()
            reportPhaseStepIfNeeded(
                phase: .entities,
                noun: "Entitäten",
                index: idx,
                total: totalEntities,
                stride: GraphTransferService.ImportTuning.cancellationStride
            )
        }
    }

    func importFieldDefinitions() async throws {
        let totalFields = file.detailFieldDefinitions.count
        progress?(GraphTransferImportProgressFactory.phaseStart(
            .fields,
            total: totalFields,
            label: "Details-Felder werden importiert…"
        ))

        for (idx, dto) in file.detailFieldDefinitions.enumerated() {
            try await performCheckpoint(
                index: idx,
                cancellationStride: GraphTransferService.ImportTuning.cancellationStride,
                yieldStride: GraphTransferService.ImportTuning.yieldStride
            )

            guard let newOwnerEntityID = entityIDMap[dto.entityID],
                  let owner = entitiesByNewID[newOwnerEntityID]
            else {
                continue
            }

            let newID = UUID()
            fieldIDMap[dto.id] = newID

            let type = DetailFieldType(rawValue: dto.typeRaw) ?? .singleLineText
            let definition = MetaDetailFieldDefinition(
                owner: owner,
                name: dto.name,
                type: type,
                sortIndex: dto.sortIndex,
                unit: dto.unit,
                options: dto.options,
                isPinned: dto.isPinned
            )
            definition.id = newID
            definition.graphID = newGraphID
            owner.addDetailField(definition)

            context.insert(definition)
            try recordInsertion()
            reportPhaseStepIfNeeded(
                phase: .fields,
                noun: "Felder",
                index: idx,
                total: totalFields,
                stride: GraphTransferService.ImportTuning.cancellationStride
            )
        }
    }

    func importAttributes() async throws {
        let totalAttributes = file.attributes.count
        progress?(GraphTransferImportProgressFactory.phaseStart(
            .attributes,
            total: totalAttributes,
            label: "Attribute werden importiert…"
        ))

        for (idx, dto) in file.attributes.enumerated() {
            try await performCheckpoint(
                index: idx,
                cancellationStride: GraphTransferService.ImportTuning.cancellationStride,
                yieldStride: GraphTransferService.ImportTuning.yieldStride
            )

            guard let oldOwnerID = dto.ownerEntityID,
                  let newOwnerID = entityIDMap[oldOwnerID],
                  let owner = entitiesByNewID[newOwnerID]
            else {
                continue
            }

            let newID = UUID()
            attributeIDMap[dto.id] = newID

            let attribute = MetaAttribute(name: dto.name, owner: owner, graphID: newGraphID, iconSymbolName: dto.iconSymbolName)
            attribute.id = newID
            attribute.notes = dto.notes
            attribute.imageData = dto.imageData
            attribute.imagePath = nil
            owner.addAttribute(attribute)

            context.insert(attribute)
            attributesByNewID[newID] = attribute

            try recordInsertion()
            reportPhaseStepIfNeeded(
                phase: .attributes,
                noun: "Attribute",
                index: idx,
                total: totalAttributes,
                stride: GraphTransferService.ImportTuning.cancellationStride
            )
        }
    }

    func importDetailFieldValues() async throws {
        let totalValues = file.detailFieldValues.count
        progress?(GraphTransferImportProgressFactory.phaseStart(
            .values,
            total: totalValues,
            label: "Details-Werte werden importiert…"
        ))

        for (idx, dto) in file.detailFieldValues.enumerated() {
            try await performCheckpoint(
                index: idx,
                cancellationStride: GraphTransferService.ImportTuning.cancellationStrideValuesAndLinks,
                yieldStride: GraphTransferService.ImportTuning.yieldStrideValuesAndLinks
            )

            guard let newAttrID = attributeIDMap[dto.attributeID],
                  let attribute = attributesByNewID[newAttrID],
                  let newFieldID = fieldIDMap[dto.fieldID]
            else {
                continue
            }

            let existingFieldIDs = Set(attribute.detailValues?.map(\.fieldID) ?? [])
            if GraphTransferImportDetailValueDeduper.shouldImport(fieldID: newFieldID, existingFieldIDs: existingFieldIDs) == false {
                continue
            }

            let value = MetaDetailFieldValue(attribute: attribute, fieldID: newFieldID)
            value.id = UUID()
            value.graphID = newGraphID
            value.stringValue = dto.stringValue
            value.intValue = dto.intValue
            value.doubleValue = dto.doubleValue
            value.dateValue = dto.dateValue
            value.boolValue = dto.boolValue

            if attribute.detailValues == nil {
                attribute.detailValues = []
            }
            attribute.detailValues?.append(value)

            context.insert(value)
            importedValues += 1

            try recordInsertion()
            reportPhaseStepIfNeeded(
                phase: .values,
                noun: "Werte",
                index: idx,
                total: totalValues,
                stride: GraphTransferService.ImportTuning.cancellationStrideValuesAndLinks
            )
        }
    }

    func importLinks() async throws {
        let totalLinks = file.links.count
        progress?(GraphTransferImportProgressFactory.phaseStart(
            .links,
            total: totalLinks,
            label: "Links werden importiert…"
        ))

        for (idx, dto) in file.links.enumerated() {
            try await performCheckpoint(
                index: idx,
                cancellationStride: GraphTransferService.ImportTuning.cancellationStrideValuesAndLinks,
                yieldStride: GraphTransferService.ImportTuning.yieldStrideValuesAndLinks
            )

            guard let newSourceID = GraphTransferImportNodeRemapper.remapNodeID(
                kindRaw: dto.sourceKindRaw,
                oldID: dto.sourceID,
                entityIDMap: entityIDMap,
                attributeIDMap: attributeIDMap
            ), let newTargetID = GraphTransferImportNodeRemapper.remapNodeID(
                kindRaw: dto.targetKindRaw,
                oldID: dto.targetID,
                entityIDMap: entityIDMap,
                attributeIDMap: attributeIDMap
            ) else {
                skippedLinks += 1
                continue
            }

            let sourceKind = NodeKind(rawValue: dto.sourceKindRaw) ?? .entity
            let targetKind = NodeKind(rawValue: dto.targetKindRaw) ?? .entity

            let link = MetaLink(
                sourceKind: sourceKind,
                sourceID: newSourceID,
                sourceLabel: dto.sourceLabel,
                targetKind: targetKind,
                targetID: newTargetID,
                targetLabel: dto.targetLabel,
                note: dto.note,
                graphID: newGraphID
            )
            link.id = UUID()
            link.createdAt = dto.createdAt
            context.insert(link)

            importedLinks += 1
            try recordInsertion()
            reportPhaseStepIfNeeded(
                phase: .links,
                noun: "Links",
                index: idx,
                total: totalLinks,
                stride: GraphTransferService.ImportTuning.cancellationStrideValuesAndLinks
            )
        }
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

    func performCheckpoint(index: Int, cancellationStride: Int, yieldStride: Int) async throws {
        if index % cancellationStride == 0 {
            try Task.checkCancellation()
        }
        if index % yieldStride == 0 {
            await Task.yield()
        }
    }

    func recordInsertion() throws {
        insertedSinceLastSave += 1
        try maybeSave()
    }

    func maybeSave() throws {
        if insertedSinceLastSave >= GraphTransferService.ImportTuning.saveBatchSize {
            try saveContext()
            insertedSinceLastSave = 0
        }
    }

    func saveContext() throws {
        do {
            try context.save()
        } catch {
            throw GraphTransferError.saveFailed(underlying: String(describing: error))
        }
    }

    func reportPhaseStepIfNeeded(
        phase: GraphTransferProgress.Phase,
        noun: String,
        index: Int,
        total: Int,
        stride: Int
    ) {
        guard shouldReportProgress(index: index, total: total, stride: stride) else {
            return
        }
        progress?(GraphTransferImportProgressFactory.phaseStep(
            phase,
            completed: index + 1,
            total: total,
            noun: noun
        ))
    }

    func shouldReportProgress(index: Int, total: Int, stride: Int) -> Bool {
        index % stride == 0 || index + 1 == total
    }
}
