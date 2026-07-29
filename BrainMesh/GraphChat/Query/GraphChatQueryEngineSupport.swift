//
//  GraphChatQueryEngineSupport.swift
//  BrainMesh
//
//  Internal value-only preparation types for deterministic query execution.
//

import Foundation

nonisolated struct GraphChatPreparedQueryRow: Sendable {
    let attribute: GraphAttributeDTO
    let valuesByFieldID: [UUID: GraphDetailValueDTO]
}

nonisolated struct GraphChatQueryEngineLimits: Hashable, Sendable {
    let maximumResultCount: Int
    let maximumEvidenceCount: Int

    static let `default` = GraphChatQueryEngineLimits(
        maximumResultCount:
            GraphChatIntentLimitPolicy
                .default.maximumQueryResultCount,
        maximumEvidenceCount:
            GraphChatIntentLimitPolicy
                .default.maximumQueryEvidenceCount
    )

    init(maximumResultCount: Int, maximumEvidenceCount: Int) {
        precondition(maximumResultCount > 0)
        precondition(maximumEvidenceCount > 0)
        self.maximumResultCount = maximumResultCount
        self.maximumEvidenceCount = maximumEvidenceCount
    }
}

nonisolated enum GraphChatQueryComparisonResult: Int, Sendable {
    case orderedAscending = -1
    case orderedSame = 0
    case orderedDescending = 1
}
