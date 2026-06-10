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

    func quickFilterSnapshot(for filter: EntitiesHomeQuickFilter) -> EntitiesHomeQuickFilterSnapshot? {
        quickFilters.first { $0.filter == filter }
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
