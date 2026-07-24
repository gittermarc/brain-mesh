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
nonisolated struct GraphCounts: Equatable, Hashable, Sendable {
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

nonisolated enum GraphStatsCountScope: Hashable {
    case total
    case graph(UUID?)
}

nonisolated struct GraphStatsAttachmentAggregate: Equatable, Sendable {
    let count: Int
    let bytes: Int64
}

nonisolated struct GraphStatsBaseCounts: Equatable, Sendable {
    let entities: Int
    let attributes: Int
    let links: Int
    let notes: Int
    let images: Int

    func makeCounts(attachmentAggregate: GraphStatsAttachmentAggregate) -> GraphCounts {
        GraphCounts(
            entities: entities,
            attributes: attributes,
            links: links,
            notes: notes,
            images: images,
            attachments: attachmentAggregate.count,
            attachmentBytes: attachmentAggregate.bytes
        )
    }
}

nonisolated struct GraphStatsScopeRevision: Equatable, Hashable, Sendable {
    let counts: GraphCounts
    let detailFieldCount: Int
    let newestEntityCreatedAt: Date?
    let newestLinkCreatedAt: Date?
    let newestAttachmentCreatedAt: Date?
}

// MARK: - P0 Stats Extensions (Dashboard + Media + Structure)

/// Small label/value pair for rankings (e.g. top file extensions).
nonisolated struct GraphTopItem: Equatable, Sendable {
    let label: String
    let count: Int
}

/// Lightweight view model for the largest attachments list.
nonisolated struct GraphLargestAttachment: Equatable, Sendable {
    let id: UUID
    let title: String
    let byteCount: Int
    let contentKind: AttachmentContentKind
    let fileExtension: String
}

/// Ranking item for "Top nodes with media".
///
/// Media count is computed as: attachments + headerImage(0/1)
nonisolated struct GraphMediaNodeItem: Equatable, Sendable {
    let id: UUID
    let label: String
    let kind: NodeKind
    let attachmentCount: Int
    let headerImageCount: Int

    var mediaCount: Int {
        attachmentCount + headerImageCount
    }
}

/// Media breakdown (attachments) + rankings for a given graph.
nonisolated struct GraphMediaSnapshot: Equatable, Sendable {
    let headerImages: Int

    let attachmentsTotal: Int
    let attachmentsFile: Int
    let attachmentsVideo: Int
    let attachmentsGalleryImages: Int

    let topFileExtensions: [GraphTopItem]
    let largestAttachments: [GraphLargestAttachment]

    let topMediaNodes: [GraphMediaNodeItem]
}

// MARK: - P1: Trends (7 days)

nonisolated struct GraphTrendDelta: Equatable, Sendable {
    let current: Int
    let previous: Int
}

nonisolated struct GraphTrendsSnapshot: Equatable, Sendable {
    /// Labels for the last N days (oldest -> newest).
    let dayLabels: [String]

    /// Counts for last N days (oldest -> newest).
    let linkCounts: [Int]
    let attachmentCounts: [Int]

    /// Delta: last N days vs previous N days.
    let linkDelta: GraphTrendDelta
    let attachmentDelta: GraphTrendDelta

    /// Link density over the last N days (approx. links-per-node over time).
    let linkDensitySeries: [Double]
}

/// Top hub node (highest degree) derived from links.
nonisolated struct GraphHubItem: Equatable, Sendable {
    let id: UUID
    let label: String
    let kind: NodeKind
    let degree: Int
}

/// Graph structure snapshot derived from nodes + links.
nonisolated struct GraphStructureSnapshot: Equatable, Sendable {
    let nodeCount: Int
    let linkCount: Int
    let isolatedNodeCount: Int
    let topHubs: [GraphHubItem]
}

// NOTE:
// The project uses "Default Actor Isolation = MainActor".
// This service is pure SwiftData/compute work and is intentionally NOT MainActor-isolated,
// so it can be used from background loaders (e.g. GraphStatsLoader's detached task).
nonisolated final class GraphStatsService {
    let context: ModelContext
    private var countsCache: [GraphStatsCountScope: GraphCounts] = [:]
    private var attachmentAggregateCache: [GraphStatsCountScope: GraphStatsAttachmentAggregate] = [:]

    init(context: ModelContext) {
        self.context = context
    }
}

// MARK: - Shared Helpers (used across split extensions)

nonisolated extension GraphStatsService {
    func shortID(_ id: UUID) -> String {
        let s = id.uuidString
        return String(s.prefix(8))
    }

    func countsCacheEntryCountForTesting() -> Int {
        countsCache.count
    }

    func attachmentAggregateCacheEntryCountForTesting() -> Int {
        attachmentAggregateCache.count
    }
}

nonisolated extension GraphStatsService {
    func cachedCounts(for scope: GraphStatsCountScope) -> GraphCounts? {
        countsCache[scope]
    }

    func storeCounts(_ counts: GraphCounts, for scope: GraphStatsCountScope) {
        countsCache[scope] = counts
    }

    func cachedAttachmentAggregate(for scope: GraphStatsCountScope) -> GraphStatsAttachmentAggregate? {
        attachmentAggregateCache[scope]
    }

    func storeAttachmentAggregate(_ aggregate: GraphStatsAttachmentAggregate, for scope: GraphStatsCountScope) {
        attachmentAggregateCache[scope] = aggregate
    }
}

// MARK: - Graph predicates

nonisolated extension GraphStatsService {
    func entityGraphPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil }
    }

    func attributeGraphPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil }
    }

    func linkGraphPredicate(for graphID: UUID?) -> Predicate<MetaLink> {
        if let graphID {
            return #Predicate<MetaLink> { $0.graphID == graphID }
        }
        return #Predicate<MetaLink> { $0.graphID == nil }
    }

    func attachmentGraphPredicate(for graphID: UUID?) -> Predicate<MetaAttachment> {
        if let graphID {
            return #Predicate<MetaAttachment> { $0.graphID == graphID }
        }
        return #Predicate<MetaAttachment> { $0.graphID == nil }
    }

    func detailFieldGraphPredicate(for graphID: UUID?) -> Predicate<MetaDetailFieldDefinition> {
        if let graphID {
            return #Predicate<MetaDetailFieldDefinition> { $0.graphID == graphID }
        }
        return #Predicate<MetaDetailFieldDefinition> { $0.graphID == nil }
    }
}

// MARK: - Notes predicates

nonisolated extension GraphStatsService {
    func entityNotesPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID && $0.notes != "" }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil && $0.notes != "" }
    }

    func attributeNotesPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID && $0.notes != "" }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil && $0.notes != "" }
    }

    func linkNotesPredicate(for graphID: UUID?) -> Predicate<MetaLink> {
        if let graphID {
            return #Predicate<MetaLink> { $0.graphID == graphID && $0.note != nil && $0.note != "" }
        }
        return #Predicate<MetaLink> { $0.graphID == nil && $0.note != nil && $0.note != "" }
    }
}

// MARK: - Image predicates (imageData only)

nonisolated extension GraphStatsService {
    func entityImageDataPredicate(for graphID: UUID?) -> Predicate<MetaEntity> {
        if let graphID {
            return #Predicate<MetaEntity> { $0.graphID == graphID && $0.imageData != nil }
        }
        return #Predicate<MetaEntity> { $0.graphID == nil && $0.imageData != nil }
    }

    func attributeImageDataPredicate(for graphID: UUID?) -> Predicate<MetaAttribute> {
        if let graphID {
            return #Predicate<MetaAttribute> { $0.graphID == graphID && $0.imageData != nil }
        }
        return #Predicate<MetaAttribute> { $0.graphID == nil && $0.imageData != nil }
    }
}


// MARK: - Revision helpers

nonisolated extension GraphStatsService {
    func totalRevision() throws -> GraphStatsScopeRevision {
        GraphStatsScopeRevision(
            counts: try totalCounts(),
            detailFieldCount: try detailFieldCount(for: nil, scoped: false),
            newestEntityCreatedAt: try newestEntityCreatedAt(),
            newestLinkCreatedAt: try newestLinkCreatedAt(for: nil, scoped: false),
            newestAttachmentCreatedAt: try newestAttachmentCreatedAt(for: nil, scoped: false)
        )
    }

    func revision(for graphID: UUID?) throws -> GraphStatsScopeRevision {
        GraphStatsScopeRevision(
            counts: try counts(for: graphID),
            detailFieldCount: try detailFieldCount(for: graphID, scoped: true),
            newestEntityCreatedAt: try newestEntityCreatedAt(for: graphID),
            newestLinkCreatedAt: try newestLinkCreatedAt(for: graphID, scoped: true),
            newestAttachmentCreatedAt: try newestAttachmentCreatedAt(for: graphID, scoped: true)
        )
    }
}

private nonisolated extension GraphStatsService {

    func detailFieldCount(for graphID: UUID?, scoped: Bool) throws -> Int {
        if scoped {
            return try context.fetchCount(
                FetchDescriptor<MetaDetailFieldDefinition>(predicate: detailFieldGraphPredicate(for: graphID))
            )
        }
        return try context.fetchCount(FetchDescriptor<MetaDetailFieldDefinition>())
    }

    func newestEntityCreatedAt() throws -> Date? {
        var descriptor = FetchDescriptor<MetaEntity>(sortBy: [SortDescriptor(\MetaEntity.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.createdAt
    }

    func newestEntityCreatedAt(for graphID: UUID?) throws -> Date? {
        var descriptor = FetchDescriptor<MetaEntity>(
            predicate: entityGraphPredicate(for: graphID),
            sortBy: [SortDescriptor(\MetaEntity.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.createdAt
    }

    func newestLinkCreatedAt(for graphID: UUID?, scoped: Bool) throws -> Date? {
        let descriptor: FetchDescriptor<MetaLink>
        if scoped {
            descriptor = newestLinkCreatedAtDescriptor(for: graphID)
        } else {
            descriptor = newestLinkCreatedAtDescriptor()
        }
        return try context.fetch(descriptor).first?.createdAt
    }

    func newestAttachmentCreatedAt(for graphID: UUID?, scoped: Bool) throws -> Date? {
        let descriptor: FetchDescriptor<MetaAttachment>
        if scoped {
            descriptor = newestAttachmentCreatedAtDescriptor(for: graphID)
        } else {
            descriptor = newestAttachmentCreatedAtDescriptor()
        }
        return try context.fetch(descriptor).first?.createdAt
    }

    func newestLinkCreatedAtDescriptor() -> FetchDescriptor<MetaLink> {
        var descriptor = FetchDescriptor<MetaLink>(sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    func newestLinkCreatedAtDescriptor(for graphID: UUID?) -> FetchDescriptor<MetaLink> {
        var descriptor = FetchDescriptor<MetaLink>(
            predicate: linkGraphPredicate(for: graphID),
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    func newestAttachmentCreatedAtDescriptor() -> FetchDescriptor<MetaAttachment> {
        var descriptor = FetchDescriptor<MetaAttachment>(sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    func newestAttachmentCreatedAtDescriptor(for graphID: UUID?) -> FetchDescriptor<MetaAttachment> {
        var descriptor = FetchDescriptor<MetaAttachment>(
            predicate: attachmentGraphPredicate(for: graphID),
            sortBy: [SortDescriptor(\MetaAttachment.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }
}
