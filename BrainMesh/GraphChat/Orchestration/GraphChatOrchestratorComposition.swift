//
//  GraphChatOrchestratorComposition.swift
//  BrainMesh
//
//  Named construction of the extracted graph-chat request components.
//

import Foundation

nonisolated struct GraphChatOrchestratorComposition: Sendable {
    let conversationStateReducer: GraphChatConversationStateReducer
    let conversationContextBuilder: GraphChatConversationContextBuilder
    let requestPreflight: GraphChatRequestPreflight
    let responseLanguageSelector: GraphChatResponseLanguageSelector
    let artifactRevalidator: any GraphChatAnswerArtifactRevalidating
    let sessionFactory: GraphChatProviderSessionFactory
    let requestPipeline: GraphChatRequestPipeline
    let errorMapper: GraphChatProviderErrorMapper
    let presentationResolver: GraphChatAnswerPresentationResolver
    let referenceDate: @Sendable () -> Date

    init(
        provider: any GraphChatModelProvider,
        schemaProvider: any GraphSchemaSnapshotProviding,
        foundationalQueryExecutor:
            any GraphChatFoundationalQueryExecuting,
        toolRunnerFactory: any GraphChatModelToolRunnerFactory,
        toolBudgetPolicy: GraphChatToolBudgetPolicy,
        conversationStatePolicy: GraphChatConversationStatePolicy,
        conversationContextBudget: GraphChatConversationContextBudget,
        referenceResolver: GraphChatConversationReferenceResolver,
        responseLanguageSelector: GraphChatResponseLanguageSelector,
        artifactRevalidator: any GraphChatAnswerArtifactRevalidating,
        evidenceValidator: any GraphEvidenceValidating,
        observability: any GraphChatObservabilityRecording,
        referenceDate: @escaping @Sendable () -> Date,
        calendar: Calendar,
        timeZone: TimeZone,
        pipelineObserver: GraphChatRequestPipelineObserver
    ) {
        let stateReducer = GraphChatConversationStateReducer(
            policy: conversationStatePolicy
        )
        let contextBuilder = GraphChatConversationContextBuilder(
            budget: conversationContextBudget
        )
        let missingContextPolicy = GraphChatReferenceMissingContextDeferPolicy()
        let localAnswerBuilder = GraphChatLocalAnswerBuilder()
        let requestBuilder = GraphChatProviderRequestBuilder()
        let errorMapper = GraphChatProviderErrorMapper()
        let sessionFactory = GraphChatProviderSessionFactory(
            provider: provider,
            schemaProvider: schemaProvider,
            toolRunnerFactory: toolRunnerFactory,
            standardToolBudgetPolicy: toolBudgetPolicy,
            conversationStateReducer: stateReducer,
            referenceResolver: referenceResolver,
            requestBuilder: requestBuilder,
            errorMapper: errorMapper,
            observability: observability,
            referenceDate: referenceDate,
            calendar: calendar,
            timeZone: timeZone
        )
        let providerExecutor = GraphChatProviderExecutor(
            provider: provider,
            sessionFactory: sessionFactory
        )
        let foundationalCoordinator =
            GraphChatFoundationalIntentCoordinator(
                schemaProvider: schemaProvider
            )
        let foundationalExecutor =
            GraphChatFoundationalIntentExecutor(
                queryExecutor: foundationalQueryExecutor,
                conversationStateReducer: stateReducer,
                calendar: calendar,
                timeZone: timeZone,
                referenceDate: referenceDate,
                observability: observability
            )
        let requestPreflight = GraphChatRequestPreflight(
            conversationStateReducer: stateReducer,
            conversationContextBuilder: contextBuilder,
            referenceResolver: referenceResolver,
            responseLanguageSelector: responseLanguageSelector,
            missingContextPolicy: missingContextPolicy,
            localAnswerBuilder: localAnswerBuilder
        )
        let answerFinalizer = GraphChatAnswerFinalizer(
            conversationStateReducer: stateReducer,
            referenceResolver: referenceResolver,
            missingContextPolicy: missingContextPolicy,
            localAnswerBuilder: localAnswerBuilder,
            evidenceValidator: evidenceValidator,
            observability: observability
        )
        let contextRetry = GraphChatProviderContextRetry(
            sessionFactory: sessionFactory,
            requestBuilder: requestBuilder,
            executor: providerExecutor
        )

        self.conversationStateReducer = stateReducer
        self.conversationContextBuilder = contextBuilder
        self.requestPreflight = requestPreflight
        self.responseLanguageSelector = responseLanguageSelector
        self.artifactRevalidator = artifactRevalidator
        self.sessionFactory = sessionFactory
        self.requestPipeline = GraphChatRequestPipeline(
            preflight: requestPreflight,
            foundationalCoordinator: foundationalCoordinator,
            foundationalExecutor: foundationalExecutor,
            contextRetry: contextRetry,
            finalizer: answerFinalizer,
            sessionFactory: sessionFactory,
            referenceDate: referenceDate,
            observer: pipelineObserver
        )
        self.errorMapper = errorMapper
        self.presentationResolver = GraphChatAnswerPresentationResolver(
            evidenceValidator: evidenceValidator,
            referenceDate: referenceDate
        )
        self.referenceDate = referenceDate
    }
}
