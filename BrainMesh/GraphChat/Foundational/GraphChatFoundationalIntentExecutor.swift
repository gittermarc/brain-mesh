//
//  GraphChatFoundationalIntentExecutor.swift
//  BrainMesh
//
//  Thin foundational adapter into the shared provider-free execution kernel.
//

import Foundation

nonisolated struct GraphChatFoundationalIntentExecutor:
    Sendable
{
    typealias ActivityHandler =
        GraphChatLocalIntentExecutionKernel.ActivityHandler
    typealias CurrentRequestValidator =
        GraphChatLocalIntentExecutionKernel
            .CurrentRequestValidator
    typealias FinalizationHandler =
        GraphChatLocalIntentExecutionKernel
            .FinalizationHandler
    typealias CommitHandler =
        GraphChatLocalIntentExecutionKernel.CommitHandler

    private let adapter:
        GraphChatFoundationalIntentAdapter
    private let kernel:
        GraphChatLocalIntentExecutionKernel
    private let observability:
        any GraphChatObservabilityRecording

    init(
        queryExecutor:
            any GraphChatFoundationalQueryExecuting,
        conversationStateReducer:
            GraphChatConversationStateReducer,
        calendar: Calendar,
        timeZone: TimeZone,
        referenceDate:
            @escaping @Sendable () -> Date,
        adapter:
            GraphChatFoundationalIntentAdapter =
                GraphChatFoundationalIntentAdapter(),
        observability:
            any GraphChatObservabilityRecording =
                NoOpGraphChatObservabilityRecorder(),
        kernelObserver:
            GraphChatLocalIntentExecutionKernelObserver =
                .disabled
    ) {
        self.adapter = adapter
        self.observability = observability
        self.kernel = GraphChatLocalIntentExecutionKernel(
            queryExecutor: queryExecutor,
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
        intent: GraphChatFoundationalIntent,
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
        let adaptation = try adapter.adapt(intent)
        await observability.record(
            .localIntent(
                GraphChatLocalIntentMetric(
                    event: .foundationalAdapted,
                    kind: adaptation.intent.kind,
                    rejection: nil
                )
            )
        )
        return try await kernel.execute(
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
