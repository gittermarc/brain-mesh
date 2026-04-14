//
//  GraphStatsService+Counts.swift
//  BrainMesh
//

import Foundation
import SwiftData

nonisolated extension GraphStatsService {
    /// Total counts across all graphs (including legacy / graphID == nil).
    func totalCounts() throws -> GraphCounts {
        let scope = GraphStatsCountScope.total
        if let cached = cachedCounts(for: scope) {
            return cached
        }

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

        let attachmentAggregate = try totalAttachmentAggregate()

        let counts = GraphCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: entityNotes + attributeNotes + linkNotes,
            images: entityImages + attributeImages,
            attachments: attachmentAggregate.count,
            attachmentBytes: attachmentAggregate.bytes
        )
        storeCounts(counts, for: scope)
        return counts
    }

    /// Counts for a single graph. Pass `nil` to get legacy counts (graphID == nil).
    func counts(for graphID: UUID?) throws -> GraphCounts {
        let scope = GraphStatsCountScope.graph(graphID)
        if let cached = cachedCounts(for: scope) {
            return cached
        }

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

        let attachmentAggregate = try attachmentAggregate(for: graphID)

        let counts = GraphCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: entityNotes + attributeNotes + linkNotes,
            images: entityImages + attributeImages,
            attachments: attachmentAggregate.count,
            attachmentBytes: attachmentAggregate.bytes
        )
        storeCounts(counts, for: scope)
        return counts
    }
}

// MARK: - Attachment aggregate

private nonisolated extension GraphStatsService {
    func totalAttachmentAggregate() throws -> GraphStatsAttachmentAggregate {
        let scope = GraphStatsCountScope.total
        if let cached = cachedAttachmentAggregate(for: scope) {
            return cached
        }

        let items = try context.fetch(FetchDescriptor<MetaAttachment>())
        let aggregate = makeAttachmentAggregate(from: items)
        storeAttachmentAggregate(aggregate, for: scope)
        return aggregate
    }

    func attachmentAggregate(for graphID: UUID?) throws -> GraphStatsAttachmentAggregate {
        let scope = GraphStatsCountScope.graph(graphID)
        if let cached = cachedAttachmentAggregate(for: scope) {
            return cached
        }

        let items = try context.fetch(
            FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
        )
        let aggregate = makeAttachmentAggregate(from: items)
        storeAttachmentAggregate(aggregate, for: scope)
        return aggregate
    }

    func makeAttachmentAggregate(from items: [MetaAttachment]) -> GraphStatsAttachmentAggregate {
        var totalBytes: Int64 = 0
        for item in items {
            totalBytes += Int64(item.byteCount)
        }
        return GraphStatsAttachmentAggregate(count: items.count, bytes: totalBytes)
    }
}
