//
//  GraphTransferImportCoordinator+Entities.swift
//  BrainMesh
//
//  Entity and attribute import phases.
//

import Foundation
import SwiftData

nonisolated extension GraphTransferImportCoordinator {

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
}
