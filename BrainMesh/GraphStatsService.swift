//
//  GraphStatsService.swift
//  BrainMesh
//
//  Counts are computed via `fetchCount` to avoid loading full model objects.
//
//  IMPORTANT:
//  SwiftData `#Predicate` + optional String comparisons can trigger
//  "unable to type-check this expression in reasonable time" in Xcode/Swift.
//  To keep builds stable, this service avoids predicates that touch `imagePath`
//  (a derived local cache field). Image presence is counted via `imageData`,
//  which is the authoritative, synced storage.
//

import Foundation
import SwiftData

/// Aggregated counters for a graph (or totals / legacy).
struct GraphCounts: Equatable, Sendable {
    let entities: Int
    let attributes: Int
    let links: Int
    let notes: Int
    let images: Int
    let attachments: Int
    let attachmentBytes: Int64

    static let zero = GraphCounts(
        entities: 0,
        attributes: 0,
        links: 0,
        notes: 0,
        images: 0,
        attachments: 0,
        attachmentBytes: 0
    )

    var isEmpty: Bool {
        entities == 0
            && attributes == 0
            && links == 0
            && notes == 0
            && images == 0
            && attachments == 0
            && attachmentBytes == 0
    }
}

@MainActor
final class GraphStatsService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

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

    // MARK: - Graph predicates

    private func entityGraphPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil }
    }

    private func attributeGraphPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil }
    }

    private func linkGraphPredicate(for graphID: UUID?) -> Predicate<MetaLink> {
        if let graphID {
            return #Predicate<MetaLink> { $0.graphID == graphID }
        }
        return #Predicate<MetaLink> { $0.graphID == nil }
    }

    private func attachmentGraphPredicate(for graphID: UUID?) -> Predicate<MetaAttachment> {
        if let graphID {
            return #Predicate<MetaAttachment> { $0.graphID == graphID }
        }
        return #Predicate<MetaAttachment> { $0.graphID == nil }
    }

    // MARK: - Notes predicates

    private func entityNotesPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID && $0.notes != "" }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil && $0.notes != "" }
    }

    private func attributeNotesPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID && $0.notes != "" }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil && $0.notes != "" }
    }

    private func linkNotesPredicate(for graphID: UUID?) -> Predicate<MetaLink> {
        if let graphID {
            return #Predicate<MetaLink> { $0.graphID == graphID && $0.note != nil && $0.note != "" }
        }
        return #Predicate<MetaLink> { $0.graphID == nil && $0.note != nil && $0.note != "" }
    }

    // MARK: - Image predicates (imageData only)

    private func entityImageDataPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID && $0.imageData != nil }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil && $0.imageData != nil }
    }

    private func attributeImageDataPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID && $0.imageData != nil }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil && $0.imageData != nil }
    }

    // MARK: - Attachment bytes

    private func totalAttachmentBytes() throws -> Int64 {
        let items = try context.fetch(FetchDescriptor<MetaAttachment>())
        var total: Int64 = 0
        for a in items {
            total += Int64(a.byteCount)
        }
        return total
    }

    private func attachmentBytes(for graphID: UUID?) throws -> Int64 {
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
