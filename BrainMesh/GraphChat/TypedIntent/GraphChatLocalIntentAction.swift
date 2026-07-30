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

nonisolated protocol GraphChatLocalIntentNodeExecuting:
    Sendable
{
    func execute(
        _ input: GetNodeInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<GetNodeOutput>
}

extension GetNodeTool:
    GraphChatLocalIntentNodeExecuting
{}

nonisolated protocol GraphChatLocalIntentStatsExecuting:
    Sendable
{
    func execute(
        _ input: GraphStatsInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<GraphStatsOutput>
}

extension GraphStatsTool:
    GraphChatLocalIntentStatsExecuting
{}

nonisolated protocol GraphChatLocalIntentRelationshipExecuting:
    Sendable
{
    func execute(
        _ plan: GraphChatRelationshipPlan,
        context: GraphChatToolContext
    ) async throws
        -> GraphChatToolResult<GraphChatRelationshipOutput>
}

nonisolated struct UnavailableGraphChatLocalStatsExecutor:
    GraphChatLocalIntentStatsExecuting
{
    func execute(
        _ input: GraphStatsInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<GraphStatsOutput> {
        throw GraphChatToolError(
            code: .unavailable,
            message:
                "GraphStats ist für diese lokale Ausführungsumgebung nicht konfiguriert."
        )
    }
}

nonisolated enum GraphChatLocalQueryResultContract:
    Hashable,
    Sendable
{
    case authoritativeSingleField(
        node: GraphChatTypedNodeIdentity,
        field: GraphChatTypedFieldIdentity
    )
    case entityCollection
    case compiledCollection
    case count
    case groupCount
    case refinement
    case comparison
}

nonisolated struct GraphChatLocalQueryAction: Hashable, Sendable {
    let plan: GraphQueryPlan
    let resultContract: GraphChatLocalQueryResultContract
    let refinementSource:
        GraphChatResolvedConversationScope?
    let compilationReferenceDate: Date?

    init(
        plan: GraphQueryPlan,
        resultContract: GraphChatLocalQueryResultContract,
        refinementSource:
            GraphChatResolvedConversationScope? = nil,
        compilationReferenceDate: Date? = nil
    ) {
        self.plan = plan
        self.resultContract = resultContract
        self.refinementSource = refinementSource
        self.compilationReferenceDate =
            compilationReferenceDate
    }
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

nonisolated struct GraphChatLocalNodeDetailsAction:
    Hashable,
    Sendable
{
    let node: GraphChatTypedNodeIdentity
    let relatedLimit: Int
}

nonisolated struct GraphChatLocalGraphStateAction:
    Hashable,
    Sendable
{
    let aspect: GraphChatGraphStateAspect
    let hubLimit: Int
}

nonisolated enum GraphChatLocalIntentAction: Hashable, Sendable {
    case queryDetailValues(GraphChatLocalQueryAction)
    case searchGraph(GraphChatLocalSearchAction)
    case nodeDetails(GraphChatLocalNodeDetailsAction)
    case compareNodes(GraphChatComparisonPlan)
    case inspectGraphState(GraphChatLocalGraphStateAction)
    case relationships(GraphChatRelationshipPlan)
}

nonisolated struct GraphChatTypedIntentAdaptation:
    Hashable,
    Sendable
{
    let intent: GraphChatTypedIntent
    let action: GraphChatLocalIntentAction
}
