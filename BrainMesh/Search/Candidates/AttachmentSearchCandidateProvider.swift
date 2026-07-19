//
//  AttachmentSearchCandidateProvider.swift
//  BrainMesh
//
//  Builds value-only candidates from attachment metadata without reading attachment bytes.
//

import Foundation
import SwiftData

nonisolated struct AttachmentSearchCandidateProvider: BrainMeshSearchCandidateProvider {
    let source: BrainMeshSearchCandidateSource = .attachment

    func candidates(for request: BrainMeshSearchCandidateRequest) throws -> [BrainMeshSearchCandidate] {
        try request.checkCancellation()

        let descriptor: FetchDescriptor<MetaAttachment>
        if let graphID = request.graphID {
            descriptor = FetchDescriptor<MetaAttachment>(
                predicate: #Predicate<MetaAttachment> { attachment in
                    attachment.graphID == graphID
                }
            )
        } else {
            descriptor = FetchDescriptor<MetaAttachment>()
        }

        let attachments = try request.modelContext.fetch(descriptor)
        var candidates: [BrainMeshSearchCandidate] = []
        candidates.reserveCapacity(attachments.count)

        for attachment in attachments {
            try request.checkCancellation()

            let fields = [
                BrainMeshSearchRankingField(
                    text: attachment.title,
                    reason: "Anhang-Titel",
                    priority: .primaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: attachment.originalFilename,
                    reason: "Dateiname",
                    priority: .primaryLabel
                ),
                BrainMeshSearchRankingField(
                    text: attachment.fileExtension,
                    reason: "Dateiendung",
                    priority: .metadata
                ),
                BrainMeshSearchRankingField(
                    text: attachment.contentTypeIdentifier,
                    reason: "Dateityp",
                    priority: .metadata
                )
            ]
            guard let match = BrainMeshSearchRanking.bestMatch(
                foldedQuery: request.foldedQuery,
                fields: fields
            ) else {
                continue
            }

            let title = attachment.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? attachment.originalFilename
                : attachment.title
            let subtitle = attachment.originalFilename
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Anhang"
                : attachment.originalFilename
            let result = BrainMeshSearchResult(
                kind: .attachment,
                id: attachment.id,
                graphID: attachment.graphID,
                title: title,
                subtitle: subtitle,
                iconSymbolName: AttachmentContentKind.searchIconSymbolName(
                    for: attachment.contentKindRaw
                ),
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: (NodeKind(rawValue: attachment.ownerKindRaw) ?? .entity).rawValue,
                ownerID: attachment.ownerID
            )
            candidates.append(BrainMeshSearchCandidate(result: result, score: match.score))
        }

        try request.checkCancellation()
        return candidates
    }
}

private extension AttachmentContentKind {
    nonisolated static func searchIconSymbolName(for rawValue: Int) -> String {
        let contentKind = AttachmentContentKind(rawValue: rawValue) ?? .file
        switch contentKind {
        case .file:
            return "paperclip"
        case .video:
            return "video"
        case .galleryImage:
            return "photo"
        }
    }
}
