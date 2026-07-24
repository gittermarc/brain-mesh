//
//  EntitiesHomeCockpitLoader.swift
//  BrainMesh
//
//  Compatibility facade that reconstructs a combined Cockpit snapshot from
//  the independent Recent Nodes loader and revision-cached Health provider.
//

import Foundation

actor EntitiesHomeCockpitLoader {
    static let shared = EntitiesHomeCockpitLoader(
        recentNodesLoader: .shared,
        healthProvider: .shared
    )

    private let recentNodesLoader: EntitiesHomeRecentNodesLoader
    private let healthProvider: EntitiesHomeHealthSummaryProvider

    init(
        recentNodesLoader: EntitiesHomeRecentNodesLoader =
            EntitiesHomeRecentNodesLoader(),
        healthProvider: EntitiesHomeHealthSummaryProvider =
            EntitiesHomeHealthSummaryProvider()
    ) {
        self.recentNodesLoader = recentNodesLoader
        self.healthProvider = healthProvider
    }

    func configure(container: AnyModelContainer) async {
        await recentNodesLoader.configure(container: container)
        await healthProvider.configure(container: container)
    }

    func loadSnapshot(
        graphID: UUID?,
        recentItems: [RecentNodeItem],
        limit: Int
    ) async throws -> EntitiesHomeCockpitSnapshot {
        guard let graphID else {
            return .empty
        }

        async let recentNodes = recentNodesLoader.load(
            graphID: graphID,
            recentItems: recentItems,
            limit: limit
        )
        async let health = healthProvider.summary(for: graphID)

        let (resolvedRecentNodes, resolvedHealth) =
            try await (recentNodes, health)
        return EntitiesHomeCockpitSnapshot(
            graphID: graphID,
            recentNodes: resolvedRecentNodes,
            healthSummary: resolvedHealth.summary,
            quickFilters: EntitiesHomeQuickFilterSnapshot.snapshots(
                from: resolvedHealth.summary
            )
        )
    }
}
