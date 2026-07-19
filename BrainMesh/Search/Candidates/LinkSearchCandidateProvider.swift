//
//  LinkSearchCandidateProvider.swift
//  BrainMesh
//
//  Builds value-only global search candidates from denormalized link metadata.
//

import Foundation
import SwiftData

nonisolated struct LinkSearchCandidateProvider: BrainMeshSearchCandidateProvider {
    let source: BrainMeshSearchCandidateSource = .link

    func candidates(for request: BrainMeshSearchCandidateRequest) throws -> [BrainMeshSearchCandidate] {
        try request.checkCancellation()

        let descriptor: FetchDescriptor<MetaLink>
        if let graphID = request.graphID {
            descriptor = FetchDescriptor<MetaLink>(
                predicate: #Predicate<MetaLink> { link in
                    link.graphID == graphID
                }
            )
        } else {
            descriptor = FetchDescriptor<MetaLink>()
        }

        let links = try request.modelContext.fetch(descriptor)
        var candidates: [BrainMeshSearchCandidate] = []
        candidates.reserveCapacity(links.count)

        for link in links {
            try request.checkCancellation()

            let note = link.note ?? ""
            let title = "\(link.sourceLabel) → \(link.targetLabel)"
            let fields = [
                BrainMeshSearchRankingField(
                    text: link.sourceLabel,
                    reason: "Quell-Label",
                    priority: .primaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: link.targetLabel,
                    reason: "Ziel-Label",
                    priority: .primaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: title,
                    reason: "Verbindung",
                    priority: .secondaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: note,
                    reason: "Link-Notiz",
                    priority: .notes
                )
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(
                foldedQuery: request.foldedQuery,
                fields: fields
            ) else {
                continue
            }

            let subtitle = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Link"
                : note
            let result = BrainMeshSearchResult(
                kind: .link,
                id: link.id,
                graphID: link.graphID,
                title: title,
                subtitle: subtitle,
                iconSymbolName: BrainMeshSearchResultKind.link.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: nil,
                ownerID: nil
            )
            candidates.append(BrainMeshSearchCandidate(result: result, score: match.score))
        }

        try request.checkCancellation()
        return candidates
    }
}
