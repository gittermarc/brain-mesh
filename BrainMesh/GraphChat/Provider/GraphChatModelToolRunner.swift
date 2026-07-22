//
//  GraphChatModelToolRunner.swift
//  BrainMesh
//
//  Provider-independent compact tool requests and bounded responses.
//

import Foundation

nonisolated struct GraphChatModelQueryFilterRequest: Hashable, Sendable {
    let fieldAlias: String
    let operation: String
    let value: String?
    let secondValue: String?
    let values: [String]
}

nonisolated struct GraphChatModelQueryRequest: Hashable, Sendable {
    let entityAlias: String
    let filters: [GraphChatModelQueryFilterRequest]
    let sortFieldAlias: String?
    let sortDirection: String?
    let projectionFieldAliases: [String]
    let aggregation: String?
    let aggregationFieldAlias: String?
    let limit: Int
}

nonisolated enum GraphChatModelToolRequest: Hashable, Sendable {
    case describeSchema(exampleFieldAliases: [String])
    case searchGraph(query: String, limit: Int)
    case queryDetailValues(GraphChatModelQueryRequest)
    case getNode(nodeAlias: String, relatedLimit: Int)
    case getNeighbors(nodeAlias: String, limit: Int)
    case graphStats(hubLimit: Int)

    var kind: GraphChatToolKind {
        switch self {
        case .describeSchema:
            return .describeGraphSchema
        case .searchGraph:
            return .searchGraph
        case .queryDetailValues:
            return .queryDetailValues
        case .getNode:
            return .getNode
        case .getNeighbors:
            return .getNeighbors
        case .graphStats:
            return .graphStats
        }
    }
}

nonisolated struct GraphChatModelToolResponse: Hashable, Sendable {
    let tool: GraphChatToolKind
    let state: GraphChatToolResultState
    let content: String
    let evidenceIDs: [GraphEvidenceID]
}

nonisolated protocol GraphChatModelToolRunning: Sendable {
    func registeredToolKinds() async -> Set<GraphChatToolKind>

    func run(
        _ request: GraphChatModelToolRequest
    ) async throws -> GraphChatModelToolResponse
}

nonisolated protocol GraphChatModelToolRunnerFactory: Sendable {
    func makeRunner(
        scope: GraphChatScope,
        schemaContext: GraphSchemaContext,
        budget: GraphChatToolBudget,
        evidenceRegistry: GraphChatEvidenceRegistry,
        conversationTransaction: GraphChatConversationStateTransaction,
        referenceDate: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> any GraphChatModelToolRunning
}
