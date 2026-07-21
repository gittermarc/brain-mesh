//
//  QueryDetailValuesTool.swift
//  BrainMesh
//
//  Tool boundary for deterministic execution of validated detail queries.
//

import Foundation

nonisolated struct QueryDetailValuesInput: Sendable {
    let plan: ValidatedGraphQueryPlan
}

nonisolated struct QueryDetailValuesOutput: Sendable {
    let result: GraphChatQueryResult
}

nonisolated struct QueryDetailValuesTool: GraphChatTool {
    let kind = GraphChatToolKind.queryDetailValues
    static let maximumResultCount = 50

    private let queryEngine: GraphChatQueryEngine
    private let logger: any GraphChatToolLogging

    init(
        queryEngine: GraphChatQueryEngine = .shared,
        logger: any GraphChatToolLogging = GraphChatTechnicalLogger()
    ) {
        self.queryEngine = queryEngine
        self.logger = logger
    }

    func execute(
        _ input: QueryDetailValuesInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<QueryDetailValuesOutput> {
        let timer = GraphChatToolTimer()
        do {
            guard GraphChatScopeAuthorization.allows(
                plan: input.plan,
                within: context.scope
            ) else {
                throw GraphChatToolError(
                    code: .graphScopeMismatch,
                    message: "Der validierte Query-Plan liegt außerhalb des aktiven Chat-Scopes."
                )
            }
            _ = try await context.budget.beginCall(
                tool: kind,
                requestedResultCount: input.plan.limit,
                toolMaximumResultCount: Self.maximumResultCount
            )
            try Task.checkCancellation()
            let result = try await queryEngine.execute(input.plan)
            try await context.budget.consumeEvidence(result.evidence.count)
            let output = QueryDetailValuesOutput(result: result)
            let resultCount = result.rows.count + (result.aggregation == nil ? 0 : 1)
            logger.record(timer.metric(tool: kind, resultCount: resultCount, wasCancelled: false))

            switch result.state {
            case .success:
                return .success(output, evidence: result.evidence)
            case .noResults:
                return GraphChatToolResult(
                    state: .noResults,
                    payload: output,
                    evidence: result.evidence
                )
            case .noEvidence:
                return .noEvidence()
            }
        } catch is CancellationError {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: true))
            throw GraphChatToolError.cancelled()
        } catch {
            logger.record(timer.metric(tool: kind, resultCount: 0, wasCancelled: false))
            throw error
        }
    }
}
