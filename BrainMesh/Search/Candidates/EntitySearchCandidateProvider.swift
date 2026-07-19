//
//  EntitySearchCandidateProvider.swift
//  BrainMesh
//
//  Builds value-only global search candidates from entity metadata.
//

import Foundation
import SwiftData

nonisolated struct EntitySearchCandidateProvider: BrainMeshSearchCandidateProvider {
    let source: BrainMeshSearchCandidateSource = .entity

    func candidates(for request: BrainMeshSearchCandidateRequest) throws -> [BrainMeshSearchCandidate] {
        try request.checkCancellation()

        let foldedQuery = request.foldedQuery
        let descriptor: FetchDescriptor<MetaEntity>
        if let graphID = request.graphID {
            descriptor = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { entity in
                    entity.graphID == graphID
                        && (entity.nameFolded.contains(foldedQuery)
                            || entity.notesFolded.contains(foldedQuery))
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        } else {
            descriptor = FetchDescriptor<MetaEntity>(
                predicate: #Predicate<MetaEntity> { entity in
                    entity.nameFolded.contains(foldedQuery)
                        || entity.notesFolded.contains(foldedQuery)
                },
                sortBy: [SortDescriptor(\MetaEntity.name)]
            )
        }

        let entities = try request.modelContext.fetch(descriptor)
        var candidates: [BrainMeshSearchCandidate] = []
        candidates.reserveCapacity(entities.count)

        for entity in entities {
            try request.checkCancellation()

            let fields = [
                BrainMeshSearchRankingField(
                    text: entity.name,
                    reason: "Name",
                    priority: .primaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: entity.notes,
                    reason: "Notiz",
                    priority: .notes
                )
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(
                foldedQuery: foldedQuery,
                fields: fields
            ) else {
                continue
            }

            let result = BrainMeshSearchResult(
                kind: .entity,
                id: entity.id,
                graphID: entity.graphID,
                title: entity.name,
                subtitle: "Entität",
                iconSymbolName: entity.iconSymbolName
                    ?? BrainMeshSearchResultKind.entity.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: entity.id,
                ownerKindRaw: nil,
                ownerID: nil
            )
            candidates.append(BrainMeshSearchCandidate(result: result, score: match.score))
        }

        try request.checkCancellation()
        return candidates
    }
}
