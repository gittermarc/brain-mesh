//
//  AttributeSearchCandidateProvider.swift
//  BrainMesh
//
//  Builds value-only global search candidates from attribute metadata.
//

import Foundation
import SwiftData

nonisolated struct AttributeSearchCandidateProvider: BrainMeshSearchCandidateProvider {
    let source: BrainMeshSearchCandidateSource = .attribute

    func candidates(for request: BrainMeshSearchCandidateRequest) throws -> [BrainMeshSearchCandidate] {
        try request.checkCancellation()

        let foldedQuery = request.foldedQuery
        let descriptor: FetchDescriptor<MetaAttribute>
        if let graphID = request.graphID {
            descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    attribute.graphID == graphID
                        && (attribute.searchLabelFolded.contains(foldedQuery)
                            || attribute.notesFolded.contains(foldedQuery))
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        } else {
            descriptor = FetchDescriptor<MetaAttribute>(
                predicate: #Predicate<MetaAttribute> { attribute in
                    attribute.searchLabelFolded.contains(foldedQuery)
                        || attribute.notesFolded.contains(foldedQuery)
                },
                sortBy: [SortDescriptor(\MetaAttribute.name)]
            )
        }

        let attributes = try request.modelContext.fetch(descriptor)
        var candidates: [BrainMeshSearchCandidate] = []
        candidates.reserveCapacity(attributes.count)

        for attribute in attributes {
            try request.checkCancellation()

            let ownerName = attribute.owner?.name ?? "Ohne Entität"
            let displayName = attribute.displayName
            let fields = [
                BrainMeshSearchRankingField(
                    text: attribute.name,
                    reason: "Attribut",
                    priority: .primaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: displayName,
                    reason: "Label",
                    priority: .primaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: ownerName,
                    reason: "Entität",
                    priority: .secondaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: attribute.notes,
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
                kind: .attribute,
                id: attribute.id,
                graphID: attribute.graphID,
                title: attribute.name,
                subtitle: ownerName,
                iconSymbolName: attribute.iconSymbolName
                    ?? BrainMeshSearchResultKind.attribute.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: NodeKind.attribute.rawValue,
                nodeID: attribute.id,
                ownerKindRaw: NodeKind.entity.rawValue,
                ownerID: attribute.owner?.id
            )
            candidates.append(BrainMeshSearchCandidate(result: result, score: match.score))
        }

        try request.checkCancellation()
        return candidates
    }
}
