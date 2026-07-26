//
//  GraphTransferImportCoordinator+Details.swift
//  BrainMesh
//
//  Detail field definition and value import phases.
//

import Foundation
import SwiftData

nonisolated extension GraphTransferImportCoordinator {

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
            _ = try DetailDataWriteValidator.validate(
                field: definition,
                owner: owner
            )
            owner.addDetailField(definition)

            context.insert(definition)
            fieldsByNewID[newID] = definition
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

    func importDetailFieldValues(
        _ authoritativeValues: [DetailFieldValueDTO]
    ) async throws {
        let totalValues = authoritativeValues.count
        progress?(GraphTransferImportProgressFactory.phaseStart(
            .values,
            total: totalValues,
            label: "Details-Werte werden importiert…"
        ))

        for (idx, dto) in authoritativeValues.enumerated() {
            try await performCheckpoint(
                index: idx,
                cancellationStride: GraphTransferService.ImportTuning.cancellationStrideValuesAndLinks,
                yieldStride: GraphTransferService.ImportTuning.yieldStrideValuesAndLinks
            )

            guard let newAttrID = attributeIDMap[dto.attributeID],
                  let attribute = attributesByNewID[newAttrID],
                  let newFieldID = fieldIDMap[dto.fieldID],
                  let field = fieldsByNewID[newFieldID]
            else {
                continue
            }

            let existingFieldIDs = Set(attribute.detailValues?.map(\.fieldID) ?? [])
            if GraphTransferImportDetailValueDeduper.shouldImport(fieldID: newFieldID, existingFieldIDs: existingFieldIDs) == false {
                continue
            }

            let proposedStorage = DetailTypedStorageSnapshot(
                stringValue: dto.stringValue,
                intValue: dto.intValue,
                doubleValue: dto.doubleValue,
                dateValue: dto.dateValue,
                boolValue: dto.boolValue
            )
            _ = try DetailDataWriteValidator.validateProposedValue(
                storage: proposedStorage,
                field: field,
                attribute: attribute
            )

            let value = MetaDetailFieldValue(
                attribute: attribute,
                fieldID: newFieldID
            )
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
}
