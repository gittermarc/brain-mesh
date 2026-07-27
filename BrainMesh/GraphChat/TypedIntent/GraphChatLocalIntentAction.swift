//
//  GraphChatLocalIntentAction.swift
//  BrainMesh
//
//  Already compiled local actions accepted by the provider-free kernel.
//

import Foundation

nonisolated protocol GraphChatLocalIntentQueryExecuting:
    Sendable
{
    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult
}

typealias GraphChatFoundationalQueryExecuting =
    GraphChatLocalIntentQueryExecuting

extension GraphChatQueryEngine:
    GraphChatLocalIntentQueryExecuting
{}

nonisolated enum GraphChatLocalQueryResultContract:
    Hashable,
    Sendable
{
    case authoritativeSingleField(
        node: GraphChatTypedNodeIdentity,
        field: GraphChatTypedFieldIdentity
    )
    case entityCollection
}

nonisolated struct GraphChatLocalQueryAction: Hashable, Sendable {
    let plan: GraphQueryPlan
    let resultContract: GraphChatLocalQueryResultContract
}

nonisolated enum GraphChatLocalIntentAction: Hashable, Sendable {
    case queryDetailValues(GraphChatLocalQueryAction)
}

nonisolated struct GraphChatTypedIntentAdaptation:
    Hashable,
    Sendable
{
    let intent: GraphChatTypedIntent
    let action: GraphChatLocalIntentAction
}
