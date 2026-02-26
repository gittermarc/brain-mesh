//
//  BulkLinkSnapshot.swift
//  BrainMesh
//
//  P0.1: Value-only snapshot for BulkLinkView.
//  Goal: Keep SwiftData fetches out of the SwiftUI render path.
//

import Foundation

/// Value-only container holding the current link sets for the Bulk Link flow.
///
/// Important: This snapshot must not contain SwiftData `@Model` instances.
struct BulkLinkSnapshot: @unchecked Sendable {
    let existingOutgoingTargets: Set<NodeRefKey>
    let existingIncomingSources: Set<NodeRefKey>

    static let empty = BulkLinkSnapshot(
        existingOutgoingTargets: [],
        existingIncomingSources: []
    )
}
