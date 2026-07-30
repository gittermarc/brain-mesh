//
//  GraphChatSemanticIntentExecutor.swift
//  BrainMesh
//
//  Thin semantic-intent entry into the shared provider-free kernel.
//

import Foundation

nonisolated struct GraphChatSemanticIntentExecutor:
    Sendable
{
    typealias ActivityHandler =
        GraphChatLocalIntentExecutionKernel
            .ActivityHandler
    typealias CurrentRequestValidator =
        GraphChatLocalIntentExecutionKernel
            .CurrentRequestValidator
    typealias FinalizationHandler =
        GraphChatLocalIntentExecutionKernel
            .FinalizationHandler
    typealias CommitHandler =
        GraphChatLocalIntentExecutionKernel
            .CommitHandler

    private let kernel:
        GraphChatLocalIntentExecutionKernel

    init(
        queryExecutor:
            any GraphChatLocalIntentQueryExecuting,
        searchExecutor:
            any GraphChatLocalIntentSearchExecuting,
        nodeExecutor:
            any GraphChatLocalIntentNodeExecuting =
                GetNodeTool(),
        statsExecutor:
            any GraphChatLocalIntentStatsExecuting =
                UnavailableGraphChatLocalStatsExecutor(),
        relationshipExecutor:
            any GraphChatLocalIntentRelationshipExecuting =
                GraphChatRelationshipExecutor(),
        conversationStateReducer:
            GraphChatConversationStateReducer,
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate:
            @escaping @Sendable () -> Date,
        observability:
            any GraphChatObservabilityRecording =
                NoOpGraphChatObservabilityRecorder(),
        kernelObserver:
            GraphChatLocalIntentExecutionKernelObserver =
                .disabled
    ) {
        self.kernel =
            GraphChatLocalIntentExecutionKernel(
                queryExecutor: queryExecutor,
                searchExecutor: searchExecutor,
                nodeExecutor: nodeExecutor,
                statsExecutor: statsExecutor,
                relationshipExecutor:
                    relationshipExecutor,
                conversationStateReducer:
                    conversationStateReducer,
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: referenceDate,
                observability: observability,
                observer: kernelObserver
            )
    }

    func execute(
        adaptation:
            GraphChatTypedIntentAdaptation,
        schemaContext: GraphSchemaContext,
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        artifactSession:
            GraphChatArtifactSessionResources,
        onActivity: ActivityHandler,
        validateCurrentRequest:
            @escaping CurrentRequestValidator,
        finalize: @escaping FinalizationHandler,
        commit: @escaping CommitHandler
    ) async throws -> GraphChatFinalizedTurn {
        try await kernel.execute(
            adaptation: adaptation,
            schemaContext: schemaContext,
            providerPlan: providerPlan,
            requestID: requestID,
            artifactSession: artifactSession,
            onActivity: onActivity,
            validateCurrentRequest:
                validateCurrentRequest,
            finalize: finalize,
            commit: commit
        )
    }
}
