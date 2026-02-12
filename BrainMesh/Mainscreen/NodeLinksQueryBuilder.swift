//
//  NodeLinksQueryBuilder.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import SwiftData
import _SwiftData_SwiftUI

/// Central place to build the SwiftData queries for a node's outgoing/incoming links.
/// Keeps EntityDetailView / AttributeDetailView lean and ensures both use identical predicates.
enum NodeLinksQueryBuilder {

    static func outgoingLinksQuery(
        kind: NodeKind,
        id: UUID,
        graphID: UUID?
    ) -> Query<MetaLink, [MetaLink]> {
        let k = kind.rawValue
        let nodeID = id
        let gid = graphID

        return Query(
            filter: #Predicate<MetaLink> { l in
                l.sourceKindRaw == k && l.sourceID == nodeID && (gid == nil || l.graphID == gid)
            },
            sort: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
    }

    static func incomingLinksQuery(
        kind: NodeKind,
        id: UUID,
        graphID: UUID?
    ) -> Query<MetaLink, [MetaLink]> {
        let k = kind.rawValue
        let nodeID = id
        let gid = graphID

        return Query(
            filter: #Predicate<MetaLink> { l in
                l.targetKindRaw == k && l.targetID == nodeID && (gid == nil || l.graphID == gid)
            },
            sort: [SortDescriptor(\MetaLink.createdAt, order: .reverse)]
        )
    }
}
