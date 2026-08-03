//
//  GraphChatResultWindow.swift
//  BrainMesh
//
//  Value-only result-window metadata shared by deterministic queries and read-only tools.
//

import Foundation

nonisolated enum GraphChatResultLimitSource: String, CaseIterable, Hashable, Sendable {
    case tool
    case query
    case source
    case appPolicy
}

nonisolated struct GraphChatResultWindow: Hashable, Sendable {
    let totalCount: Int?
    let returnedCount: Int
    let limit: Int?
    let limitReached: Bool
    let limitSources: [GraphChatResultLimitSource]

    var limitSource: GraphChatResultLimitSource? {
        limitSources.first
    }

    init(
        totalCount: Int?,
        returnedCount: Int,
        limit: Int? = nil,
        limitReached: Bool = false,
        limitSource: GraphChatResultLimitSource? = nil
    ) {
        self.init(
            totalCount: totalCount,
            returnedCount: returnedCount,
            limit: limit,
            limitReached: limitReached,
            limitSources: limitReached ? [limitSource ?? .source] : []
        )
    }

    init(
        totalCount: Int?,
        returnedCount: Int,
        limit: Int? = nil,
        limitReached: Bool,
        limitSources: [GraphChatResultLimitSource]
    ) {
        let normalizedReturnedCount = max(0, returnedCount)
        let normalizedTotalCount = totalCount.map {
            max(normalizedReturnedCount, $0)
        }
        let normalizedLimit = limit.map { max(0, $0) }
        var seenSources = Set<GraphChatResultLimitSource>()
        let normalizedSources = limitSources.filter {
            seenSources.insert($0).inserted
        }

        self.totalCount = normalizedTotalCount
        self.returnedCount = normalizedReturnedCount
        self.limit = normalizedLimit
        self.limitReached = limitReached
        self.limitSources = limitReached
            ? (normalizedSources.isEmpty ? [.source] : normalizedSources)
            : []
    }

    static func complete(totalCount: Int) -> GraphChatResultWindow {
        let normalizedCount = max(0, totalCount)
        return GraphChatResultWindow(
            totalCount: normalizedCount,
            returnedCount: normalizedCount
        )
    }

    static func unknown(
        returnedCount: Int,
        limit: Int? = nil,
        limitReached: Bool = false,
        limitSource: GraphChatResultLimitSource? = nil
    ) -> GraphChatResultWindow {
        GraphChatResultWindow(
            totalCount: nil,
            returnedCount: returnedCount,
            limit: limit,
            limitReached: limitReached,
            limitSource: limitSource
        )
    }
}
