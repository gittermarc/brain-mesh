//
//  GraphStatsService+Counts.swift
//  BrainMesh
//

import Foundation
import SwiftData

extension GraphStatsService {
    /// Total counts across all graphs (including legacy / graphID == nil).
    func totalCounts() throws -> GraphCounts {
        let entities = try context.fetchCount(FetchDescriptor<MetaEntity>())
        let attributes = try context.fetchCount(FetchDescriptor<MetaAttribute>())
        let links = try context.fetchCount(FetchDescriptor<MetaLink>())

        let entityNotes = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: #Predicate { $0.notes != "" })
        )
        let attributeNotes = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: #Predicate { $0.notes != "" })
        )
        let linkNotes = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: #Predicate { $0.note != nil && $0.note != "" })
        )

        // Images: count via imageData (authoritative). Avoid `imagePath` in predicates to prevent type-check timeouts.
        let entityImages = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: #Predicate { $0.imageData != nil })
        )
        let attributeImages = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: #Predicate { $0.imageData != nil })
        )

        // Attachments: count is cheap, bytes require a small fetch to sum byteCount.
        let attachments = try context.fetchCount(FetchDescriptor<MetaAttachment>())
        let attachmentBytes = try totalAttachmentBytes()

        return GraphCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: entityNotes + attributeNotes + linkNotes,
            images: entityImages + attributeImages,
            attachments: attachments,
            attachmentBytes: attachmentBytes
        )
    }

    /// Counts for a single graph. Pass `nil` to get legacy counts (graphID == nil).
    func counts(for graphID: UUID?) throws -> GraphCounts {
        let entities = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityGraphPredicate(for: graphID))
        )
        let attributes = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeGraphPredicate(for: graphID))
        )
        let links = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: linkGraphPredicate(for: graphID))
        )

        let entityNotes = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityNotesPredicate(for: graphID))
        )
        let attributeNotes = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeNotesPredicate(for: graphID))
        )
        let linkNotes = try context.fetchCount(
            FetchDescriptor<MetaLink>(predicate: linkNotesPredicate(for: graphID))
        )

        // Images: count via imageData (authoritative). Avoid `imagePath` in predicates to prevent type-check timeouts.
        let entityImages = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityImageDataPredicate(for: graphID))
        )
        let attributeImages = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeImageDataPredicate(for: graphID))
        )

        let attachments = try context.fetchCount(
            FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
        )
        let attachmentBytes = try attachmentBytes(for: graphID)

        return GraphCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: entityNotes + attributeNotes + linkNotes,
            images: entityImages + attributeImages,
            attachments: attachments,
            attachmentBytes: attachmentBytes
        )
    }
}

// MARK: - Attachment bytes

private extension GraphStatsService {
    func totalAttachmentBytes() throws -> Int64 {
        let items = try context.fetch(FetchDescriptor<MetaAttachment>())
        var total: Int64 = 0
        for a in items {
            total += Int64(a.byteCount)
        }
        return total
    }

    func attachmentBytes(for graphID: UUID?) throws -> Int64 {
        let items = try context.fetch(
            FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
        )
        var total: Int64 = 0
        for a in items {
            total += Int64(a.byteCount)
        }
        return total
    }
}
