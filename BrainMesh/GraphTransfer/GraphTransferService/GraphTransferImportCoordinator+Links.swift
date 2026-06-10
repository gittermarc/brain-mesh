//
//  GraphTransferImportCoordinator+Links.swift
//  BrainMesh
//
//  Link import phase.
//

import Foundation
import SwiftData

nonisolated extension GraphTransferImportCoordinator {

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
}
