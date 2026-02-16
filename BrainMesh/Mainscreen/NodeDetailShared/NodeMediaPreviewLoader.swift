//
//  NodeMediaPreviewLoader.swift
//  BrainMesh
//
//  P0.1/P0.2: Fetch-limited media preview + counts for Entity/Attribute detail views.
//

import Foundation
import SwiftData

struct NodeMediaPreview {
    var galleryPreview: [MetaAttachment]
    var attachmentPreview: [MetaAttachment]

    var galleryCount: Int
    var attachmentCount: Int

    static let empty = NodeMediaPreview(
        galleryPreview: [],
        attachmentPreview: [],
        galleryCount: 0,
        attachmentCount: 0
    )

    var totalCount: Int { galleryCount + attachmentCount }
}

enum NodeMediaPreviewLoader {

    /// Loads a small preview set (gallery + attachments) and total counts.
    ///
    /// - Note: Uses `fetchLimit` to avoid pulling all attachments into memory.
    @MainActor
    static func load(
        context: ModelContext,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        galleryLimit: Int = 6,
        attachmentLimit: Int = 3
    ) throws -> NodeMediaPreview {
        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let gid = graphID
        let galleryRaw = AttachmentContentKind.galleryImage.rawValue

        let galleryPredicate = #Predicate<MetaAttachment> { a in
            a.ownerKindRaw == kindRaw &&
            a.ownerID == oid &&
            (gid == nil || a.graphID == gid) &&
            a.contentKindRaw == galleryRaw
        }

        let attachmentPredicate = #Predicate<MetaAttachment> { a in
            a.ownerKindRaw == kindRaw &&
            a.ownerID == oid &&
            (gid == nil || a.graphID == gid) &&
            a.contentKindRaw != galleryRaw
        }

        // Counts (cheap, avoids loading full objects).
        let galleryCount = try context.fetchCount(FetchDescriptor<MetaAttachment>(predicate: galleryPredicate))
        let attachmentCount = try context.fetchCount(FetchDescriptor<MetaAttachment>(predicate: attachmentPredicate))

        // Preview fetches.
        var galleryFD = FetchDescriptor<MetaAttachment>(
            predicate: galleryPredicate,
            sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
        )
        galleryFD.fetchLimit = max(0, galleryLimit)

        var attachmentFD = FetchDescriptor<MetaAttachment>(
            predicate: attachmentPredicate,
            sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
        )
        attachmentFD.fetchLimit = max(0, attachmentLimit)

        let galleryPreview = (galleryFD.fetchLimit == 0) ? [] : (try context.fetch(galleryFD))
        let attachmentPreview = (attachmentFD.fetchLimit == 0) ? [] : (try context.fetch(attachmentFD))

        return NodeMediaPreview(
            galleryPreview: galleryPreview,
            attachmentPreview: attachmentPreview,
            galleryCount: galleryCount,
            attachmentCount: attachmentCount
        )
    }
}
