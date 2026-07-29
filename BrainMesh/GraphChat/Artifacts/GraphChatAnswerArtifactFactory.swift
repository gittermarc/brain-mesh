//
//  GraphChatAnswerArtifactFactory.swift
//  BrainMesh
//
//  Deterministic entry points for revalidated read-only answer artifacts.
//

import Foundation

nonisolated struct GraphChatAnswerArtifactFactoryBudget: Hashable, Sendable {
    let maximumRows: Int
    let maximumColumns: Int

    static let `default` = GraphChatAnswerArtifactFactoryBudget(
        maximumRows:
            GraphChatIntentLimitPolicy
                .default.defaultQueryResultCount,
        maximumColumns:
            GraphChatIntentLimitPolicy
                .default.maximumProjectionFieldCount
                + 1
    )

    init(maximumRows: Int, maximumColumns: Int) {
        precondition(maximumRows > 0)
        precondition(maximumColumns > 1)
        self.maximumRows = maximumRows
        self.maximumColumns = maximumColumns
    }
}

nonisolated enum GraphChatAnswerArtifactFactory {
    static func queryResult(
        _ result: GraphChatQueryResult,
        plan: ValidatedGraphQueryPlan,
        schemaContext: GraphSchemaContext,
        language: GraphChatResponseLanguage = .english,
        budget: GraphChatAnswerArtifactFactoryBudget = .default
    ) -> GraphChatAnswerArtifactDraft? {
        let summary = querySummary(
            plan: plan,
            schemaContext: schemaContext,
            language: language
        )
        if let aggregation = result.aggregation {
            switch aggregation.kind {
            case .groupCount:
                return grouping(
                    aggregation: aggregation,
                    result: result,
                    plan: plan,
                    schemaContext: schemaContext,
                    language: language,
                    budget: budget,
                    querySummary: summary
                )
            case .count, .minimum, .maximum:
                return metric(
                    aggregation: aggregation,
                    result: result,
                    plan: plan,
                    schemaContext: schemaContext,
                    language: language,
                    querySummary: summary
                )
            }
        }
        guard result.rows.isEmpty == false else {
            return nil
        }
        if let timeline = timeline(
            result: result,
            plan: plan,
            schemaContext: schemaContext,
            language: language,
            budget: budget,
            querySummary: summary
        ) {
            return timeline
        }
        let fieldIDs = projectedFieldIDs(plan)
        if fieldIDs.count <= 1 {
            return resultList(
                result: result,
                plan: plan,
                schemaContext: schemaContext,
                language: language,
                budget: budget,
                querySummary: summary
            )
        }
        return table(
            result: result,
            plan: plan,
            schemaContext: schemaContext,
            language: language,
            budget: budget,
            querySummary: summary
        )
    }

}
