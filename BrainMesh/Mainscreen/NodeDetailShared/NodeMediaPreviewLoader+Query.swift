//
//  NodeMediaPreviewLoader+Query.swift
//  BrainMesh
//
//  Off-main snapshot query helpers for NodeMediaPreviewLoader.
//

import Foundation
import SwiftData

private struct NodeMediaPreviewRecord: Sendable {
    let id: UUID
    let createdAt: Date
}

private struct NodeMediaPreviewQueryResult: Sendable {
    let count: Int
    let previewRecords: [NodeMediaPreviewRecord]
}

private enum NodeMediaPreviewGraphScope: Sendable {
    case all
    case exact(UUID)
    case legacyNil
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
        let gallery = try loadScopedPreview(
            context: context,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphID: graphID,
            contentKind: .galleryImage,
            previewLimit: galleryLimit
        )
        try Task.checkCancellation()

        let attachments = try loadScopedPreview(
            context: context,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphID: graphID,
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
        graphID: UUID?,
        contentKind: NodeMediaPreviewContentKind,
        previewLimit: Int
    ) throws -> (count: Int, previewIDs: [UUID]) {
        if let graphID {
            let current = try fetchQueryResult(
                context: context,
                ownerKindRaw: ownerKindRaw,
                ownerID: ownerID,
                graphScope: .exact(graphID),
                contentKind: contentKind,
                previewLimit: previewLimit
            )
            try Task.checkCancellation()

            let legacy = try fetchQueryResult(
                context: context,
                ownerKindRaw: ownerKindRaw,
                ownerID: ownerID,
                graphScope: .legacyNil,
                contentKind: contentKind,
                previewLimit: previewLimit
            )

            let previewIDs = mergePreviewIDs(
                current.previewRecords,
                legacy.previewRecords,
                limit: previewLimit
            )
            return (current.count + legacy.count, previewIDs)
        }

        let all = try fetchQueryResult(
            context: context,
            ownerKindRaw: ownerKindRaw,
            ownerID: ownerID,
            graphScope: .all,
            contentKind: contentKind,
            previewLimit: previewLimit
        )
        return (all.count, all.previewRecords.map(\.id))
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

    private static func mergePreviewIDs(
        _ current: [NodeMediaPreviewRecord],
        _ legacy: [NodeMediaPreviewRecord],
        limit: Int
    ) -> [UUID] {
        guard limit > 0 else { return [] }

        return Array(
            (current + legacy)
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

private enum NodeMediaPreviewContentKind: Sendable {
    case galleryImage
    case fileAndVideo
}

private func makePredicate(
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
