//
//  NodeLinksQueryBuilder.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import SwiftData

/// Fetch-limited link preview + total counts for a node.
///
/// Why this exists:
/// - @Query without a fetchLimit will eagerly load *all* links into memory.
/// - Detail screens only need a small preview + accurate counts.
struct NodeLinksPreview {
    var outgoingPreview: [MetaLink]
    var incomingPreview: [MetaLink]
    var outgoingCount: Int
    var incomingCount: Int

    static let empty = NodeLinksPreview(
        outgoingPreview: [],
        incomingPreview: [],
        outgoingCount: 0,
        incomingCount: 0
    )

    var totalCount: Int { outgoingCount + incomingCount }
}

/// Central place to build predicates + run fetchCount/fetchLimit queries for links.
/// Keeps EntityDetailView / AttributeDetailView lean and ensures both use identical predicates.
enum NodeLinksQueryBuilder {

    /// Loads a small preview set (incoming + outgoing) and total counts.
    ///
    /// - Note: Uses `fetchLimit` to avoid pulling all links into memory.
    @MainActor
    static func load(
        context: ModelContext,
        kind: NodeKind,
        id: UUID,
        graphID: UUID?,
        previewLimit: Int = 12
    ) throws -> NodeLinksPreview {
        let kindRaw = kind.rawValue
        let nodeID = id

        // IMPORTANT: Keep predicates store-translatable (avoid OR / optional tricks).
        let outgoingPredicate: Predicate<MetaLink>
        let incomingPredicate: Predicate<MetaLink>
        if let gid = graphID {
            outgoingPredicate = #Predicate { l in
                l.sourceKindRaw == kindRaw &&
                l.sourceID == nodeID &&
                l.graphID == gid
            }
            incomingPredicate = #Predicate { l in
                l.targetKindRaw == kindRaw &&
                l.targetID == nodeID &&
                l.graphID == gid
            }
        } else {
            outgoingPredicate = #Predicate { l in
                l.sourceKindRaw == kindRaw &&
                l.sourceID == nodeID
            }
            incomingPredicate = #Predicate { l in
                l.targetKindRaw == kindRaw &&
                l.targetID == nodeID
            }
        }

        // Counts (cheap, avoids loading full objects).
        let outgoingCount = try context.fetchCount(FetchDescriptor<MetaLink>(predicate: outgoingPredicate))
        let incomingCount = try context.fetchCount(FetchDescriptor<MetaLink>(predicate: incomingPredicate))

        // Preview fetches.
        let limit = max(0, previewLimit)

        var outFD = FetchDescriptor<MetaLink>(
            predicate: outgoingPredicate,
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
        outFD.fetchLimit = limit

        var inFD = FetchDescriptor<MetaLink>(
            predicate: incomingPredicate,
            sortBy: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
        inFD.fetchLimit = limit

        let outgoingPreview = (limit == 0 || outgoingCount == 0) ? [] : (try context.fetch(outFD))
        let incomingPreview = (limit == 0 || incomingCount == 0) ? [] : (try context.fetch(inFD))

        return NodeLinksPreview(
            outgoingPreview: outgoingPreview,
            incomingPreview: incomingPreview,
            outgoingCount: outgoingCount,
            incomingCount: incomingCount
        )
    }
}
