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
    let maximumGroupCount: Int

    static let `default` =
        GraphChatSemanticIntentLimitPolicy(
            defaultFindLimit:
                GraphChatIntentLimitPolicy
                    .default.defaultSearchResultCount,
            maximumFindLimit:
                GraphChatIntentLimitPolicy
                    .default.maximumSearchResultCount,
            defaultEntityListLimit:
                GraphChatIntentLimitPolicy
                    .default.defaultQueryResultCount,
            maximumEntityListLimit:
                GraphChatIntentLimitPolicy
                    .default.completeCollectionResultCount,
            maximumGroupCount:
                GraphChatIntentLimitPolicy
                    .default.maximumGroupCount
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

    func groupCountLimit(
        for amount: GraphChatSemanticResultAmount
    ) -> Int {
        resolvedLimit(
            amount,
            defaultLimit: min(
                defaultEntityListLimit,
                maximumGroupCount
            ),
            maximumLimit: maximumGroupCount
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
