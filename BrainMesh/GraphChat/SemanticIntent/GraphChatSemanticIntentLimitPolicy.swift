//
//  GraphChatSemanticIntentLimitPolicy.swift
//  BrainMesh
//
//  Central app-owned result limits for semantic Find and Entity List.
//

import Foundation

nonisolated struct GraphChatSemanticIntentLimitPolicy:
    Hashable,
    Sendable
{
    let defaultFindLimit: Int
    let maximumFindLimit: Int
    let defaultEntityListLimit: Int
    let maximumEntityListLimit: Int

    static let `default` =
        GraphChatSemanticIntentLimitPolicy(
            defaultFindLimit: 20,
            maximumFindLimit:
                SearchGraphTool.maximumResultCount,
            defaultEntityListLimit:
                GraphQueryPlanLimits.defaultResultLimit,
            maximumEntityListLimit:
                GraphQueryPlanLimits.maximumResultLimit
        )

    func findLimit(
        for amount: GraphChatSemanticResultAmount
    ) -> Int {
        resolvedLimit(
            amount,
            defaultLimit: defaultFindLimit,
            maximumLimit: maximumFindLimit
        )
    }

    func entityListLimit(
        for amount: GraphChatSemanticResultAmount
    ) -> Int {
        resolvedLimit(
            amount,
            defaultLimit: defaultEntityListLimit,
            maximumLimit: maximumEntityListLimit
        )
    }

    private func resolvedLimit(
        _ amount: GraphChatSemanticResultAmount,
        defaultLimit: Int,
        maximumLimit: Int
    ) -> Int {
        switch amount {
        case .standard:
            return defaultLimit
        case .all:
            return maximumLimit
        case .first(let count):
            return min(maximumLimit, max(1, count))
        }
    }
}
