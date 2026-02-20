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
nonisolated struct GraphCounts: Equatable, Sendable {
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
