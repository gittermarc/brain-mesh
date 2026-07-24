//
//  EntitiesHomeCockpitDTO.swift
//  BrainMesh
//
//  Value-only snapshots for the Entities Home Cockpit data layer.
//

import Foundation

nonisolated struct EntitiesHomeCockpitSnapshot: Equatable, Sendable {
    let graphID: UUID?
    let recentNodes: [EntitiesHomeCockpitRecentNode]
    let healthSummary: GraphHealthSummary
    let quickFilters: [EntitiesHomeQuickFilterSnapshot]

    static let empty = EntitiesHomeCockpitSnapshot(
        graphID: nil,
        recentNodes: [],
        healthSummary: .empty,
        quickFilters: EntitiesHomeQuickFilter.allCases.map { filter in
            EntitiesHomeQuickFilterSnapshot(filter: filter, matchingEntityIDs: [], count: 0)
        }
    )

    static func empty(graphID: UUID) -> EntitiesHomeCockpitSnapshot {
        EntitiesHomeCockpitSnapshot(
            graphID: graphID,
            recentNodes: [],
            healthSummary: .empty,
            quickFilters: EntitiesHomeQuickFilterSnapshot.snapshots(
                from: .empty
            )
        )
    }

    func quickFilterSnapshot(for filter: EntitiesHomeQuickFilter) -> EntitiesHomeQuickFilterSnapshot? {
        quickFilters.first { $0.filter == filter }
    }

    func replacingRecentNodes(
        _ recentNodes: [EntitiesHomeCockpitRecentNode],
        for graphID: UUID
    ) -> EntitiesHomeCockpitSnapshot? {
        guard self.graphID == graphID else {
            return nil
        }
        return EntitiesHomeCockpitSnapshot(
            graphID: graphID,
            recentNodes: recentNodes,
            healthSummary: healthSummary,
            quickFilters: quickFilters
        )
    }

    func replacingHealth(
        _ health: EntitiesHomeHealthSummarySnapshot
    ) -> EntitiesHomeCockpitSnapshot? {
        guard graphID == health.graphID else {
            return nil
        }
        return EntitiesHomeCockpitSnapshot(
            graphID: health.graphID,
            recentNodes: recentNodes,
            healthSummary: health.summary,
            quickFilters: EntitiesHomeQuickFilterSnapshot.snapshots(
                from: health.summary
            )
        )
    }
}

nonisolated struct EntitiesHomeCockpitRecentNode: Identifiable, Hashable, Sendable {
    let graphID: UUID?
    let nodeKindRaw: Int
    let nodeID: UUID
    let label: String
    let subtitle: String
    let iconSymbolName: String
    let openedAt: Date
    let ownerEntityID: UUID?

    var id: String {
        let graphPart = graphID?.uuidString ?? "legacy"
        return "\(graphPart)|\(nodeKindRaw)|\(nodeID.uuidString)"
    }

    var nodeKind: NodeKind? {
        NodeKind(rawValue: nodeKindRaw)
    }

    var nodeKey: NodeKey? {
        guard let nodeKind else { return nil }
        return NodeKey(kind: nodeKind, uuid: nodeID)
    }
}
