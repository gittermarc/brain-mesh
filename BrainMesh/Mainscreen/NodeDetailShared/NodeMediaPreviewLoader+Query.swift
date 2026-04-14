//
//  NodeMediaPreviewLoader+Query.swift
//  BrainMesh
//
//  Off-main snapshot query helpers for NodeMediaPreviewLoader.
//

import Foundation
import SwiftData

private nonisolated struct NodeMediaPreviewRecord: Sendable {
    let id: UUID
    let createdAt: Date
}

private nonisolated struct NodeMediaPreviewQueryResult: Sendable {
    let count: Int
    let previewRecords: [NodeMediaPreviewRecord]
}

private nonisolated enum NodeMediaPreviewGraphScope: Sendable {
    case all
    case exact(UUID)
    case legacyNil
}

private nonisolated struct NodeMediaPreviewQueryPlan: Sendable {
    let graphScopes: [NodeMediaPreviewGraphScope]

    static func make(graphID: UUID?) -> NodeMediaPreviewQueryPlan {
        if let graphID {
            return NodeMediaPreviewQueryPlan(
                graphScopes: [.exact(graphID), .legacyNil]
            )
        }

        return NodeMediaPreviewQueryPlan(graphScopes: [.all])
    }

    func mergePreviewIDs(
        from results: [NodeMediaPreviewQueryResult],
        limit: Int
    ) -> [UUID] {
        guard limit > 0 else { return [] }

        if results.count == 1 {
            return Array(results[0].previewRecords.prefix(limit).map(\.id))
        }

        let mergedRecords = results.flatMap(\.previewRecords)
        return Array(
            mergedRecords
                .sorted { lhs, rhs in
                    if lhs.createdAt == rhs.createdAt {
                        return lhs.id.uuidString < rhs.id.uuidString
                    }
                    return lhs.createdAt > rhs.createdAt
                }
                .prefix(limit)
                .map(\.id)
        )
    }
}

extension NodeMediaPreviewLoader {

    static func makeSnapshot(
        context: ModelContext,
        ownerKindRaw: Int,
        ownerID: UUID,
        graphID: UUID?,
        galleryLimit: Int,
        attachmentLimit: Int
    ) throws -> NodeMediaPreviewSnapshot {
        let queryPlan = NodeMediaPreviewQueryPlan.make(graphID: graphID)

        let gallery = try loadScopedPreview(
            context: context,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            queryPlan: queryPlan,
            contentKind: .galleryImage,
            previewLimit: galleryLimit
        )
        try Task.checkCancellation()

        let attachments = try loadScopedPreview(
            context: context,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            queryPlan: queryPlan,
            contentKind: .fileAndVideo,
            previewLimit: attachmentLimit
        )

        return NodeMediaPreviewSnapshot(
            galleryPreviewIDs: gallery.previewIDs,
            attachmentPreviewIDs: attachments.previewIDs,
            galleryCount: gallery.count,
            attachmentCount: attachments.count
        )
    }

    private static func loadScopedPreview(
        context: ModelContext,
        ownerKindRaw: Int,
        ownerID: UUID,
        queryPlan: NodeMediaPreviewQueryPlan,
        contentKind: NodeMediaPreviewContentKind,
        previewLimit: Int
    ) throws -> (count: Int, previewIDs: [UUID]) {
        let results = try fetchQueryResults(
            context: context,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphScopes: queryPlan.graphScopes,
            contentKind: contentKind,
            previewLimit: previewLimit
        )

        let count = results.reduce(0) { partialResult, result in
            partialResult + result.count
        }
        let previewIDs = queryPlan.mergePreviewIDs(from: results, limit: previewLimit)
        return (count, previewIDs)
    }

    private static func fetchQueryResults(
        context: ModelContext,
        ownerKindRaw: Int,
        ownerID: UUID,
        graphScopes: [NodeMediaPreviewGraphScope],
        contentKind: NodeMediaPreviewContentKind,
        previewLimit: Int
    ) throws -> [NodeMediaPreviewQueryResult] {
        var results: [NodeMediaPreviewQueryResult] = []
        results.reserveCapacity(graphScopes.count)

        for (index, graphScope) in graphScopes.enumerated() {
            let result = try fetchQueryResult(
                context: context,
                ownerKindRaw: ownerKindRaw,
                ownerID: ownerID,
                graphScope: graphScope,
                contentKind: contentKind,
                previewLimit: previewLimit
            )
            results.append(result)

            if index < graphScopes.count - 1 {
                try Task.checkCancellation()
            }
        }

        return results
    }

    private static func fetchQueryResult(
        context: ModelContext,
        ownerKindRaw: Int,
        ownerID: UUID,
        graphScope: NodeMediaPreviewGraphScope,
        contentKind: NodeMediaPreviewContentKind,
        previewLimit: Int
    ) throws -> NodeMediaPreviewQueryResult {
        let predicate = makePredicate(
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphScope: graphScope,
            contentKind: contentKind
        )

        let count = try context.fetchCount(
            FetchDescriptor<MetaAttachment>(predicate: predicate)
        )

        let previewRecords: [NodeMediaPreviewRecord]
        if previewLimit == 0 {
            previewRecords = []
        } else {
            var descriptor = FetchDescriptor<MetaAttachment>(
                predicate: predicate,
                sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
            )
            descriptor.fetchLimit = previewLimit

            previewRecords = try context.fetch(descriptor).map { attachment in
                NodeMediaPreviewRecord(id: attachment.id, createdAt: attachment.createdAt)
            }
        }

        return NodeMediaPreviewQueryResult(count: count, previewRecords: previewRecords)
    }
}

private nonisolated enum NodeMediaPreviewContentKind: Sendable {
    case galleryImage
    case fileAndVideo
}

private nonisolated func makePredicate(
    ownerKindRaw: Int,
    ownerID: UUID,
    graphScope: NodeMediaPreviewGraphScope,
    contentKind: NodeMediaPreviewContentKind
) -> Predicate<MetaAttachment> {
    let kindRaw = ownerKindRaw
    let oid = ownerID
    let galleryRaw = AttachmentContentKind.galleryImage.rawValue

    switch graphScope {
    case .all:
        switch contentKind {
        case .galleryImage:
            return #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.contentKindRaw == galleryRaw
            }
        case .fileAndVideo:
            return #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.contentKindRaw != galleryRaw
            }
        }

    case .exact(let graphID):
        switch contentKind {
        case .galleryImage:
            return #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.graphID == graphID &&
                attachment.contentKindRaw == galleryRaw
            }
        case .fileAndVideo:
            return #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.graphID == graphID &&
                attachment.contentKindRaw != galleryRaw
            }
        }

    case .legacyNil:
        switch contentKind {
        case .galleryImage:
            return #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.graphID == nil &&
                attachment.contentKindRaw == galleryRaw
            }
        case .fileAndVideo:
            return #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.graphID == nil &&
                attachment.contentKindRaw != galleryRaw
            }
        }
    }
}
