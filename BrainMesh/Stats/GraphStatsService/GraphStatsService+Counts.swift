//
//  GraphStatsService+Counts.swift
//  BrainMesh
//

import Foundation
import SwiftData

nonisolated extension GraphStatsService {
    /// Total counts across all graphs (including legacy / graphID == nil).
    func totalCounts() throws -> GraphCounts {
        try counts(for: .total)
    }

    /// Counts for a single graph. Pass `nil` to get legacy counts (graphID == nil).
    func counts(for graphID: UUID?) throws -> GraphCounts {
        try counts(for: .graph(graphID))
    }
}

// MARK: - Shared counts computation

private nonisolated extension GraphStatsService {
    func counts(for scope: GraphStatsCountScope) throws -> GraphCounts {
        if let cached = cachedCounts(for: scope) {
            return cached
        }

        let baseCounts = try baseCounts(for: scope)
        let attachmentAggregate = try attachmentAggregate(for: scope)
        let counts = baseCounts.makeCounts(attachmentAggregate: attachmentAggregate)
        storeCounts(counts, for: scope)
        return counts
    }

    func baseCounts(for scope: GraphStatsCountScope) throws -> GraphStatsBaseCounts {
        switch scope {
        case .total:
            return try totalBaseCounts()
        case let .graph(graphID):
            return try scopedBaseCounts(for: graphID)
        }
    }

    func totalBaseCounts() throws -> GraphStatsBaseCounts {
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

        let entityImages = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: #Predicate { $0.imageData != nil })
        )
        let attributeImages = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: #Predicate { $0.imageData != nil })
        )

        return GraphStatsBaseCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: entityNotes + attributeNotes + linkNotes,
            images: entityImages + attributeImages
        )
    }

    func scopedBaseCounts(for graphID: UUID?) throws -> GraphStatsBaseCounts {
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

        let entityImages = try context.fetchCount(
            FetchDescriptor<MetaEntity>(predicate: entityImageDataPredicate(for: graphID))
        )
        let attributeImages = try context.fetchCount(
            FetchDescriptor<MetaAttribute>(predicate: attributeImageDataPredicate(for: graphID))
        )

        return GraphStatsBaseCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: entityNotes + attributeNotes + linkNotes,
            images: entityImages + attributeImages
        )
    }
}

// MARK: - Attachment aggregate

private nonisolated extension GraphStatsService {
    func attachmentAggregate(for scope: GraphStatsCountScope) throws -> GraphStatsAttachmentAggregate {
        if let cached = cachedAttachmentAggregate(for: scope) {
            return cached
        }

        let items = try attachmentAggregateItems(for: scope)
        let aggregate = makeAttachmentAggregate(from: items)
        storeAttachmentAggregate(aggregate, for: scope)
        return aggregate
    }

    func attachmentAggregateItems(for scope: GraphStatsCountScope) throws -> [MetaAttachment] {
        switch scope {
        case .total:
            return try context.fetch(FetchDescriptor<MetaAttachment>())
        case let .graph(graphID):
            return try context.fetch(
                FetchDescriptor<MetaAttachment>(predicate: attachmentGraphPredicate(for: graphID))
            )
        }
    }

    func makeAttachmentAggregate(from items: [MetaAttachment]) -> GraphStatsAttachmentAggregate {
        let totalBytes = items.reduce(into: Int64.zero) { partialResult, item in
            partialResult += Int64(item.byteCount)
        }
        return GraphStatsAttachmentAggregate(count: items.count, bytes: totalBytes)
    }
}
