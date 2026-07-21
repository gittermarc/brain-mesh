//
//  IndexedSearchCandidateProvider.swift
//  BrainMesh
//
//  Value-only mapping from local index documents to the established global-search candidates.
//

import Foundation

nonisolated struct BrainMeshIndexedSearchCandidateResponse: Sendable {
    let candidates: [BrainMeshSearchCandidate]
    let indexDocumentCount: Int
}

nonisolated protocol BrainMeshIndexedSearchCandidateProviding: Sendable {
    func candidates(
        graphIDs: [UUID],
        foldedQuery: String,
        resultLimit: Int
    ) async throws -> BrainMeshIndexedSearchCandidateResponse
}

nonisolated struct IndexedSearchCandidateProvider: BrainMeshIndexedSearchCandidateProviding {
    static let maximumDocumentCandidateCount = GraphSearchIndexStore.maximumSearchLimit

    private struct ResultKey: Hashable {
        let graphID: UUID
        let kind: BrainMeshSearchResultKind
        let sourceID: UUID
    }

    private let store: GraphSearchIndexStore

    init(store: GraphSearchIndexStore = GraphSearchIndexStore.shared) {
        self.store = store
    }

    func candidates(
        graphIDs: [UUID],
        foldedQuery: String,
        resultLimit: Int
    ) async throws -> BrainMeshIndexedSearchCandidateResponse {
        try Task.checkCancellation()
        let query = BMSearch.fold(foldedQuery)
        guard query.isEmpty == false, resultLimit > 0 else {
            return BrainMeshIndexedSearchCandidateResponse(
                candidates: [],
                indexDocumentCount: 0
            )
        }

        let normalizedGraphIDs = GraphSearchIndexStore.normalizedGraphIDs(graphIDs)
        guard normalizedGraphIDs.isEmpty == false else {
            return BrainMeshIndexedSearchCandidateResponse(
                candidates: [],
                indexDocumentCount: 0
            )
        }

        let documentLimit = Self.documentCandidateLimit(for: resultLimit)
        let hits = try await store.search(
            in: normalizedGraphIDs,
            text: query,
            limit: documentLimit
        )
        try Task.checkCancellation()

        var groupedDocuments: [ResultKey: [GraphSearchDocument]] = [:]
        groupedDocuments.reserveCapacity(hits.count)
        for (index, hit) in hits.enumerated() {
            if index.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            guard let kind = Self.resultKind(for: hit.document.documentKind) else {
                continue
            }
            let key = ResultKey(
                graphID: hit.document.graphID,
                kind: kind,
                sourceID: hit.document.sourceID
            )
            groupedDocuments[key, default: []].append(hit.document)
        }

        let sortedKeys = groupedDocuments.keys.sorted(by: Self.resultKeySort)
        var candidates: [BrainMeshSearchCandidate] = []
        candidates.reserveCapacity(sortedKeys.count)
        for (index, key) in sortedKeys.enumerated() {
            if index.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            guard let documents = groupedDocuments[key],
                  let candidate = Self.candidate(
                    key: key,
                    documents: documents,
                    foldedQuery: query
                  )
            else {
                continue
            }
            candidates.append(candidate)
        }
        try Task.checkCancellation()

        return BrainMeshIndexedSearchCandidateResponse(
            candidates: candidates,
            indexDocumentCount: hits.count
        )
    }

    nonisolated static func documentCandidateLimit(for resultLimit: Int) -> Int {
        GraphSearchIndexStore.internalCandidateLimit(for: max(1, resultLimit))
    }

    private static func candidate(
        key: ResultKey,
        documents: [GraphSearchDocument],
        foldedQuery: String
    ) -> BrainMeshSearchCandidate? {
        let sortedDocuments = documents.sorted(by: documentSort)
        guard let canonical = sortedDocuments.first else { return nil }

        let fields = sortedDocuments.flatMap { document in
            legacyRankingFields(for: document)
        }
        guard let match = BrainMeshSearchRanking.bestMatch(
            foldedQuery: foldedQuery,
            fields: fields
        ) else {
            return nil
        }

        let result: BrainMeshSearchResult
        switch key.kind {
        case .entity:
            result = BrainMeshSearchResult(
                kind: .entity,
                id: key.sourceID,
                graphID: key.graphID,
                title: canonical.title,
                subtitle: "Entität",
                iconSymbolName: canonical.presentation.iconSymbolName
                    ?? BrainMeshSearchResultKind.entity.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: NodeKind.entity.rawValue,
                nodeID: key.sourceID,
                ownerKindRaw: nil,
                ownerID: nil
            )
        case .attribute:
            let owner = canonical.navigation.ownerNode
            let ownerLabel = owner?.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle = ownerLabel.flatMap { value in
                value.isEmpty ? nil : value
            } ?? canonical.subtitle
            result = BrainMeshSearchResult(
                kind: .attribute,
                id: key.sourceID,
                graphID: key.graphID,
                title: canonical.title,
                subtitle: subtitle,
                iconSymbolName: canonical.presentation.iconSymbolName
                    ?? BrainMeshSearchResultKind.attribute.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: NodeKind.attribute.rawValue,
                nodeID: key.sourceID,
                ownerKindRaw: NodeKind.entity.rawValue,
                ownerID: owner?.id ?? canonical.ownerID
            )
        case .link:
            result = BrainMeshSearchResult(
                kind: .link,
                id: key.sourceID,
                graphID: key.graphID,
                title: canonical.title,
                subtitle: canonical.subtitle,
                iconSymbolName: BrainMeshSearchResultKind.link.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: nil,
                ownerID: nil
            )
        case .detail:
            result = BrainMeshSearchResult(
                kind: .detail,
                id: key.sourceID,
                graphID: key.graphID,
                title: canonical.title,
                subtitle: canonical.subtitle,
                iconSymbolName: canonical.presentation.iconSymbolName
                    ?? BrainMeshSearchResultKind.detail.defaultIconSymbolName,
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: canonical.ownerKindRaw,
                ownerID: canonical.ownerID
            )
        case .attachment:
            let metadata = canonical.attachmentMetadata
            let rawTitle = metadata?.title ?? canonical.title
            let rawFilename = metadata?.originalFilename ?? canonical.subtitle
            let cleanTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanFilename = rawFilename.trimmingCharacters(in: .whitespacesAndNewlines)
            result = BrainMeshSearchResult(
                kind: .attachment,
                id: key.sourceID,
                graphID: key.graphID,
                title: cleanTitle.isEmpty ? rawFilename : rawTitle,
                subtitle: cleanFilename.isEmpty ? "Anhang" : rawFilename,
                iconSymbolName: attachmentIconSymbolName(
                    contentKindRaw: metadata?.contentKindRaw
                ),
                matchReason: match.matchReason,
                nodeKindRaw: nil,
                nodeID: nil,
                ownerKindRaw: canonical.ownerKindRaw,
                ownerID: canonical.ownerID
            )
        }
        return BrainMeshSearchCandidate(result: result, score: match.score)
    }

    private static func legacyRankingFields(
        for document: GraphSearchDocument
    ) -> [BrainMeshSearchRankingField] {
        let allowedReasons = allowedRankingReasons(for: document.documentKind)
        return document.ranking.fields.compactMap { field in
            guard allowedReasons.contains(field.reason) else { return nil }
            return BrainMeshSearchRankingField(
                text: field.text,
                reason: field.reason,
                priority: field.priority.searchPriority
            )
        }
    }

    private static func allowedRankingReasons(
        for documentKind: GraphSearchDocumentKind
    ) -> Set<String> {
        switch documentKind {
        case .entity:
            return ["Name"]
        case .entityNotes:
            return ["Notiz"]
        case .attribute:
            return ["Attribut", "Label", "Entität"]
        case .attributeNotes:
            return ["Notiz"]
        case .link:
            return ["Quell-Label", "Ziel-Label", "Verbindung"]
        case .linkNotes:
            return ["Link-Notiz"]
        case .detailFieldDefinition:
            // The legacy SwiftData provider prefilters definitions by nameFolded.
            // Owner labels are ranking context only and must not create extra results.
            return ["Detailfeld"]
        case .detailValue:
            return ["Detailwert", "Detailfeld", "Attribut"]
        case .attachmentMetadata:
            return ["Anhang-Titel", "Dateiname", "Dateiendung", "Dateityp"]
        }
    }

    private static func resultKind(
        for documentKind: GraphSearchDocumentKind
    ) -> BrainMeshSearchResultKind? {
        switch documentKind {
        case .entity, .entityNotes:
            return .entity
        case .attribute, .attributeNotes:
            return .attribute
        case .link, .linkNotes:
            return .link
        case .detailFieldDefinition, .detailValue:
            return .detail
        case .attachmentMetadata:
            return .attachment
        }
    }

    private static func attachmentIconSymbolName(
        contentKindRaw: Int?
    ) -> String {
        let contentKind = contentKindRaw.flatMap(AttachmentContentKind.init(rawValue:)) ?? .file
        switch contentKind {
        case .file:
            return "paperclip"
        case .video:
            return "video"
        case .galleryImage:
            return "photo"
        }
    }

    private static func resultKeySort(_ lhs: ResultKey, _ rhs: ResultKey) -> Bool {
        if lhs.graphID != rhs.graphID {
            return lhs.graphID.uuidString < rhs.graphID.uuidString
        }
        if lhs.kind.sortPrecedence != rhs.kind.sortPrecedence {
            return lhs.kind.sortPrecedence < rhs.kind.sortPrecedence
        }
        return lhs.sourceID.uuidString < rhs.sourceID.uuidString
    }

    private static func documentSort(
        _ lhs: GraphSearchDocument,
        _ rhs: GraphSearchDocument
    ) -> Bool {
        if lhs.documentKind.sortPrecedence != rhs.documentKind.sortPrecedence {
            return lhs.documentKind.sortPrecedence < rhs.documentKind.sortPrecedence
        }
        return lhs.documentID < rhs.documentID
    }
}

private extension GraphSearchRankingFieldPriority {
    nonisolated var searchPriority: BrainMeshSearchFieldPriority {
        switch self {
        case .primaryLabel:
            return .primaryLabel
        case .secondaryLabel:
            return .secondaryLabel
        case .metadata:
            return .metadata
        case .notes:
            return .notes
        }
    }
}
