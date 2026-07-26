//
//  GraphChatProviderContextRetry.swift
//  BrainMesh
//
//  Exactly-once recovery for provider context-window failures.
//

import Foundation

nonisolated struct GraphChatProviderContextRetry: Sendable {
    private let sessionFactory: GraphChatProviderSessionFactory
    private let requestBuilder: GraphChatProviderRequestBuilder
    private let executor: GraphChatProviderExecutor
    private let initialContextProfilePlanner: GraphChatInitialContextProfilePlanner

    init(
        sessionFactory: GraphChatProviderSessionFactory,
        requestBuilder: GraphChatProviderRequestBuilder,
        executor: GraphChatProviderExecutor,
        initialContextProfilePlanner: GraphChatInitialContextProfilePlanner =
            GraphChatInitialContextProfilePlanner()
    ) {
        self.sessionFactory = sessionFactory
        self.requestBuilder = requestBuilder
        self.executor = executor
        self.initialContextProfilePlanner = initialContextProfilePlanner
    }

    func execute(
        initialResources: GraphChatProviderSessionResources,
        question: String,
        continuationOperation: GraphChatConversationContinuationOperation?,
        onAttemptResources: @escaping @Sendable (
            GraphChatProviderSessionResources
        ) async -> Void,
        onEvent: @escaping @Sendable (GraphChatProviderForwardedEvent) -> Void
    ) async throws -> GraphChatProviderExecutionResult {
        var resources = initialResources
        var retryCount = 0
        let initialProfile = requestBuilder.initialContextProfile(
            schemaContext: initialResources.schemaContext,
            chatScope: initialResources.key.chatScope,
            conversationContext: initialResources.conversationContext,
            question: question,
            responseLanguage: initialResources.responseLanguage,
            planner: initialContextProfilePlanner
        )

        while true {
            await onAttemptResources(resources)
            let profile: GraphChatModelContextProfile =
                retryCount == 0 ? initialProfile : .recovery
            let request = requestBuilder.makeRequest(
                resources: resources,
                question: question,
                continuationOperation: continuationOperation,
                contextProfile: profile
            )
            do {
                let finalAnswer = try await executor.execute(
                    resources: resources,
                    request: request,
                    onEvent: onEvent
                )
                try Task.checkCancellation()
                return GraphChatProviderExecutionResult(
                    finalAnswer: finalAnswer,
                    resources: resources,
                    request: request
                )
            } catch let error as GraphChatProviderError
                where error.code == .contextWindowExceeded && retryCount == 0
            {
                await sessionFactory.cleanupFailedAttempt(
                    resources,
                    requestProviderCancellation: false
                )
                retryCount += 1
                resources = try await sessionFactory.makeRecoverySession(
                    replacing: resources
                )
            } catch {
                let isCancellation =
                    error is CancellationError
                    || Task.isCancelled
                    || (error as? GraphChatProviderError)?.code == .cancelled
                    || (error as? GraphChatToolError)?.code == .cancelled
                await sessionFactory.cleanupFailedAttempt(
                    resources,
                    requestProviderCancellation: isCancellation
                )
                throw error
            }
        }
    }
}
