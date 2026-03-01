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

        let data = try GraphTransferFileIO.readFileData(url: url)
        let file = try GraphTransferCodec.decode(data)
        try GraphTransferValidator.validate(exportFile: file)

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

        progress?(GraphTransferProgress(phase: .inspecting, completed: 0, label: "Datei wird geprüft…"))

        let data = try GraphTransferFileIO.readFileData(url: url)
        let file = try GraphTransferCodec.decode(data)
        try GraphTransferValidator.validate(exportFile: file)

        switch mode {
        case .asNewGraphRemap:
            return try await Self.importAsNewGraphRemap(file: file, container: container, progress: progress)
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

    static func importAsNewGraphRemap(
        file: GraphExportFileV1,
        container: AnyModelContainer,
        progress: (@Sendable (GraphTransferProgress) -> Void)?
    ) async throws -> ImportResult {
        let context = ModelContext(container.container)
        context.autosaveEnabled = false

        progress?(GraphTransferProgress(phase: .creatingGraph, completed: 0, label: "Neuer Graph wird angelegt…"))

        let newGraphID = UUID()

        let graph = MetaGraph(name: file.graph.name)
        graph.id = newGraphID
        graph.createdAt = file.graph.createdAt
        context.insert(graph)

        // Remap dictionaries
        var entityIDMap: [UUID: UUID] = [:]
        var attributeIDMap: [UUID: UUID] = [:]
        var fieldIDMap: [UUID: UUID] = [:]

        var entitiesByNewID: [UUID: MetaEntity] = [:]
        var attributesByNewID: [UUID: MetaAttribute] = [:]

        // Batch save helper
        var insertedSinceLastSave = 0
        func maybeSave() throws {
            if insertedSinceLastSave >= ImportTuning.saveBatchSize {
                do {
                    try context.save()
                    insertedSinceLastSave = 0
                } catch {
                    throw GraphTransferError.saveFailed(underlying: String(describing: error))
                }
            }
        }

        // 1) Entities
        let totalEntities = file.entities.count
        progress?(GraphTransferProgress(phase: .entities, completed: 0, total: totalEntities, label: "Entitäten werden importiert…"))

        for (idx, dto) in file.entities.enumerated() {
            if idx % ImportTuning.cancellationStride == 0 { try Task.checkCancellation() }
            if idx % ImportTuning.yieldStride == 0 { await Task.yield() }

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

            insertedSinceLastSave += 1
            try maybeSave()

            if idx % ImportTuning.cancellationStride == 0 || idx + 1 == totalEntities {
                progress?(GraphTransferProgress(phase: .entities, completed: idx + 1, total: totalEntities, label: "Entitäten: \(idx + 1)/\(totalEntities)"))
            }
        }

        // 2) Detail field definitions
        let totalFields = file.detailFieldDefinitions.count
        progress?(GraphTransferProgress(phase: .fields, completed: 0, total: totalFields, label: "Details-Felder werden importiert…"))

        for (idx, dto) in file.detailFieldDefinitions.enumerated() {
            if idx % ImportTuning.cancellationStride == 0 { try Task.checkCancellation() }
            if idx % ImportTuning.yieldStride == 0 { await Task.yield() }

            guard let newOwnerEntityID = entityIDMap[dto.entityID],
                  let owner = entitiesByNewID[newOwnerEntityID]
            else {
                continue
            }

            let newID = UUID()
            fieldIDMap[dto.id] = newID

            let type = DetailFieldType(rawValue: dto.typeRaw) ?? .singleLineText
            let def = MetaDetailFieldDefinition(
                owner: owner,
                name: dto.name,
                type: type,
                sortIndex: dto.sortIndex,
                unit: dto.unit,
                options: dto.options,
                isPinned: dto.isPinned
            )
            def.id = newID
            def.graphID = newGraphID
            owner.addDetailField(def)

            context.insert(def)
            insertedSinceLastSave += 1
            try maybeSave()

            if idx % ImportTuning.cancellationStride == 0 || idx + 1 == totalFields {
                progress?(GraphTransferProgress(phase: .fields, completed: idx + 1, total: totalFields, label: "Felder: \(idx + 1)/\(totalFields)"))
            }
        }

        // 3) Attributes
        let totalAttributes = file.attributes.count
        progress?(GraphTransferProgress(phase: .attributes, completed: 0, total: totalAttributes, label: "Attribute werden importiert…"))

        for (idx, dto) in file.attributes.enumerated() {
            if idx % ImportTuning.cancellationStride == 0 { try Task.checkCancellation() }
            if idx % ImportTuning.yieldStride == 0 { await Task.yield() }

            guard let oldOwnerID = dto.ownerEntityID,
                  let newOwnerID = entityIDMap[oldOwnerID],
                  let owner = entitiesByNewID[newOwnerID]
            else {
                // Attribute without owner are ignored (would be orphaned and mostly useless in UI).
                continue
            }

            let newID = UUID()
            attributeIDMap[dto.id] = newID

            let attr = MetaAttribute(name: dto.name, owner: owner, graphID: newGraphID, iconSymbolName: dto.iconSymbolName)
            attr.id = newID
            attr.notes = dto.notes
            attr.imageData = dto.imageData
            attr.imagePath = nil
            owner.addAttribute(attr)

            context.insert(attr)
            attributesByNewID[newID] = attr

            insertedSinceLastSave += 1
            try maybeSave()

            if idx % ImportTuning.cancellationStride == 0 || idx + 1 == totalAttributes {
                progress?(GraphTransferProgress(phase: .attributes, completed: idx + 1, total: totalAttributes, label: "Attribute: \(idx + 1)/\(totalAttributes)"))
            }
        }

        // 4) Detail field values
        let totalValues = file.detailFieldValues.count
        progress?(GraphTransferProgress(phase: .values, completed: 0, total: totalValues, label: "Details-Werte werden importiert…"))

        var importedValues = 0
        for (idx, dto) in file.detailFieldValues.enumerated() {
            if idx % ImportTuning.cancellationStrideValuesAndLinks == 0 { try Task.checkCancellation() }
            if idx % ImportTuning.yieldStrideValuesAndLinks == 0 { await Task.yield() }

            guard let newAttrID = attributeIDMap[dto.attributeID],
                  let attr = attributesByNewID[newAttrID]
            else {
                continue
            }
            guard let newFieldID = fieldIDMap[dto.fieldID] else {
                continue
            }

            let value = MetaDetailFieldValue(attribute: attr, fieldID: newFieldID)
            value.id = UUID()
            value.graphID = newGraphID

            value.stringValue = dto.stringValue
            value.intValue = dto.intValue
            value.doubleValue = dto.doubleValue
            value.dateValue = dto.dateValue
            value.boolValue = dto.boolValue

            if attr.detailValues == nil { attr.detailValues = [] }
            // De-dupe per attribute+field (defensive against legacy duplicates).
            if attr.detailValues?.contains(where: { $0.fieldID == newFieldID }) == true {
                continue
            }
            attr.detailValues?.append(value)

            context.insert(value)
            importedValues += 1

            insertedSinceLastSave += 1
            try maybeSave()

            if idx % ImportTuning.cancellationStrideValuesAndLinks == 0 || idx + 1 == totalValues {
                progress?(GraphTransferProgress(phase: .values, completed: idx + 1, total: totalValues, label: "Werte: \(idx + 1)/\(totalValues)"))
            }
        }

        // 5) Links
        let totalLinks = file.links.count
        progress?(GraphTransferProgress(phase: .links, completed: 0, total: totalLinks, label: "Links werden importiert…"))

        var importedLinks = 0
        var skippedLinks = 0

        for (idx, dto) in file.links.enumerated() {
            if idx % ImportTuning.cancellationStrideValuesAndLinks == 0 { try Task.checkCancellation() }
            if idx % ImportTuning.yieldStrideValuesAndLinks == 0 { await Task.yield() }

            guard let newSourceID = remapNodeID(kindRaw: dto.sourceKindRaw, oldID: dto.sourceID, entityIDMap: entityIDMap, attributeIDMap: attributeIDMap),
                  let newTargetID = remapNodeID(kindRaw: dto.targetKindRaw, oldID: dto.targetID, entityIDMap: entityIDMap, attributeIDMap: attributeIDMap)
            else {
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

            insertedSinceLastSave += 1
            try maybeSave()

            if idx % ImportTuning.cancellationStrideValuesAndLinks == 0 || idx + 1 == totalLinks {
                progress?(GraphTransferProgress(phase: .links, completed: idx + 1, total: totalLinks, label: "Links: \(idx + 1)/\(totalLinks)"))
            }
        }

        // Final save
        progress?(GraphTransferProgress(phase: .saving, completed: 0, label: "Speichere…"))
        do {
            try context.save()
        } catch {
            throw GraphTransferError.saveFailed(underlying: String(describing: error))
        }

        let insertedCounts = CountsDTO(
            graphs: 1,
            entities: entitiesByNewID.count,
            attributes: attributesByNewID.count,
            detailFieldDefinitions: fieldIDMap.count,
            detailFieldValues: importedValues,
            links: importedLinks
        )

        progress?(GraphTransferProgress(phase: .done, completed: 1, total: 1, label: "Fertig"))

        return ImportResult(
            newGraphID: newGraphID,
            insertedCounts: insertedCounts,
            skippedLinks: skippedLinks
        )
    }

    static func remapNodeID(
        kindRaw: Int,
        oldID: UUID,
        entityIDMap: [UUID: UUID],
        attributeIDMap: [UUID: UUID]
    ) -> UUID? {
        if kindRaw == NodeKind.entity.rawValue {
            return entityIDMap[oldID]
        }
        if kindRaw == NodeKind.attribute.rawValue {
            return attributeIDMap[oldID]
        }
        return nil
    }
}
