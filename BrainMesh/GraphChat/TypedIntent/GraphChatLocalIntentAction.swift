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

nonisolated protocol GraphChatLocalIntentSearchExecuting:
    Sendable
{
    func execute(
        _ input: SearchGraphInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<SearchGraphOutput>
}

extension SearchGraphTool:
    GraphChatLocalIntentSearchExecuting
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

nonisolated enum GraphChatLocalSearchTarget:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case anyEntry
    case entities
    case attributes
    case entityNodes
}

nonisolated struct GraphChatLocalSearchAction:
    Hashable,
    Sendable
{
    let query: String
    let limit: Int
    let scope: GraphChatScope
    let target: GraphChatLocalSearchTarget
    let entityID: UUID?
}

nonisolated enum GraphChatLocalIntentAction: Hashable, Sendable {
    case queryDetailValues(GraphChatLocalQueryAction)
    case searchGraph(GraphChatLocalSearchAction)
}

nonisolated struct GraphChatTypedIntentAdaptation:
    Hashable,
    Sendable
{
    let intent: GraphChatTypedIntent
    let action: GraphChatLocalIntentAction
}
