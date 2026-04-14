//
//  NodeImagesManageAttachmentResolver.swift
//  BrainMesh
//
//  Resolves gallery attachments for NodeImagesManageView actions.
//  Prefer an exact id match, but keep an owner-scoped fallback so action
//  handling stays resilient if a list item is stale while the gallery row data
//  is still otherwise identifiable.
//

import Foundation
import SwiftData

@MainActor
struct NodeImagesManageAttachmentResolver {

    static func resolveImageAttachment(
        in context: ModelContext,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        item: AttachmentListItem
    ) -> MetaAttachment? {
        if let exact = fetchAttachment(in: context, attachmentID: item.id) {
            return exact
        }

        return fallbackAttachment(
            in: context,
            ownerKind: ownerKind,
            ownerID: ownerID,
            graphID: graphID,
            item: item
        )
    }

    private static func fetchAttachment(in context: ModelContext, attachmentID: UUID) -> MetaAttachment? {
        let id = attachmentID
        let descriptor = FetchDescriptor<MetaAttachment>(predicate: #Predicate { attachment in
            attachment.id == id
        })
        return (try? context.fetch(descriptor))?.first
    }

    private static func fallbackAttachment(
        in context: ModelContext,
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?,
        item: AttachmentListItem
    ) -> MetaAttachment? {
        for descriptor in fallbackDescriptors(ownerKind: ownerKind, ownerID: ownerID, graphID: graphID) {
            guard let attachments = try? context.fetch(descriptor) else { continue }

            if let metadataMatch = attachments.first(where: { matches($0, item: item) }) {
                return metadataMatch
            }

            if let exactIDMatch = attachments.first(where: { $0.id == item.id }) {
                return exactIDMatch
            }
        }

        return nil
    }

    private static func fallbackDescriptors(
        ownerKind: NodeKind,
        ownerID: UUID,
        graphID: UUID?
    ) -> [FetchDescriptor<MetaAttachment>] {
        let kindRaw = ownerKind.rawValue
        let oid = ownerID
        let galleryRaw = AttachmentContentKind.galleryImage.rawValue
        let sort = [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]

        if let gid = graphID {
            let scoped = FetchDescriptor<MetaAttachment>(
                predicate: #Predicate { attachment in
                    attachment.ownerKindRaw == kindRaw &&
                    attachment.ownerID == oid &&
                    attachment.graphID == gid &&
                    attachment.contentKindRaw == galleryRaw
                },
                sortBy: sort
            )

            let legacyFallback = FetchDescriptor<MetaAttachment>(
                predicate: #Predicate { attachment in
                    attachment.ownerKindRaw == kindRaw &&
                    attachment.ownerID == oid &&
                    attachment.graphID == nil &&
                    attachment.contentKindRaw == galleryRaw
                },
                sortBy: sort
            )

            return [scoped, legacyFallback]
        }

        let unscoped = FetchDescriptor<MetaAttachment>(
            predicate: #Predicate { attachment in
                attachment.ownerKindRaw == kindRaw &&
                attachment.ownerID == oid &&
                attachment.contentKindRaw == galleryRaw
            },
            sortBy: sort
        )

        return [unscoped]
    }

    private static func matches(_ attachment: MetaAttachment, item: AttachmentListItem) -> Bool {
        attachment.title == item.title &&
        attachment.originalFilename == item.originalFilename &&
        attachment.contentTypeIdentifier == item.contentTypeIdentifier &&
        attachment.fileExtension == item.fileExtension &&
        attachment.byteCount == item.byteCount &&
        attachment.createdAt == item.createdAt &&
        attachment.localPath == item.localPath
    }
}
