//
//  GraphChatRequestPipeline.swift
//  BrainMesh
//
//  Explicit composition of preflight, execution, finalization and turn commit.
//

import Foundation

nonisolated enum GraphChatRequestPipelineStage: String, CaseIterable, Hashable, Sendable {
    case preflight
    case foundationalIntent
    case semanticIntent
    case sessionResources
    case providerExecution
    case answerFinalization
    case turnCommit
}

nonisolated enum GraphChatRequestPipelineStagePhase: String, CaseIterable, Hashable, Sendable {
    case started
    case completed
}

nonisolated struct GraphChatRequestPipelineEvent: Hashable, Sendable {
    let requestID: UUID
    let stage: GraphChatRequestPipelineStage
    let phase: GraphChatRequestPipelineStagePhase
    let usesProvider: Bool
}

nonisolated struct GraphChatRequestPipelineObserver: Sendable {
    private let handler: @Sendable (GraphChatRequestPipelineEvent) async -> Void

    static let disabled = GraphChatRequestPipelineObserver { _ in }

    init(
        handler: @escaping @Sendable (GraphChatRequestPipelineEvent) async -> Void
    ) {
        self.handler = handler
    }

    func record(_ event: GraphChatRequestPipelineEvent) async {
        await handler(event)
    }
}

nonisolated struct GraphChatRequestPipelineInput: Hashable, Sendable {
    let requestID: UUID
    let requestedAt: Date
    let question: String
    let key: GraphChatOrchestrationScopeKey
    let turnStateSnapshot: GraphChatConversationState
}

nonisolated struct GraphChatRequestPipelineCompletion: Sendable {
    let finalizedTurn: GraphChatFinalizedTurn
    let usedProvider: Bool
}

nonisolated struct GraphChatRequestPipeline: Sendable {
    typealias SessionResourcesProvider = @Sendable (
        GraphChatProviderTurnPlan
    ) async throws -> GraphChatProviderSessionResources
    typealias FoundationalArtifactSessionProvider = @Sendable (
        GraphChatOrchestrationScopeKey
    ) async throws -> GraphChatArtifactSessionResources
    typealias AttemptResourcesHandler = @Sendable (
        GraphChatProviderSessionResources
    ) async -> Void
    typealias CurrentRequestValidator = @Sendable () async throws -> Void
    typealias TurnCommitHandler = @Sendable (
        GraphChatFinalizedTurn
    ) async throws -> Void
    typealias ProviderEventHandler = @Sendable (
        GraphChatProviderForwardedEvent
    ) -> Void

    private let preflight: GraphChatRequestPreflight
    private let foundationalCoordinator:
        GraphChatFoundationalIntentCoordinator
    private let foundationalExecutor: GraphChatFoundationalIntentExecutor
    private let semanticCoordinator:
        GraphChatSemanticIntentCoordinator
    private let semanticExecutor:
        GraphChatSemanticIntentExecutor
    private let contextRetry: GraphChatProviderContextRetry
    private let finalizer: GraphChatAnswerFinalizer
    private let sessionFactory: GraphChatProviderSessionFactory
    private let referenceDate: @Sendable () -> Date
    private let observer: GraphChatRequestPipelineObserver
    private let observability:
        any GraphChatObservabilityRecording

    init(
        preflight: GraphChatRequestPreflight,
        foundationalCoordinator: GraphChatFoundationalIntentCoordinator,
        foundationalExecutor: GraphChatFoundationalIntentExecutor,
        semanticCoordinator:
            GraphChatSemanticIntentCoordinator,
        semanticExecutor:
            GraphChatSemanticIntentExecutor,
        contextRetry: GraphChatProviderContextRetry,
        finalizer: GraphChatAnswerFinalizer,
        sessionFactory: GraphChatProviderSessionFactory,
        referenceDate: @escaping @Sendable () -> Date,
        observer: GraphChatRequestPipelineObserver = .disabled,
        observability:
            any GraphChatObservabilityRecording =
                NoOpGraphChatObservabilityRecorder()
    ) {
        self.preflight = preflight
        self.foundationalCoordinator = foundationalCoordinator
        self.foundationalExecutor = foundationalExecutor
        self.semanticCoordinator = semanticCoordinator
        self.semanticExecutor = semanticExecutor
        self.contextRetry = contextRetry
        self.finalizer = finalizer
        self.sessionFactory = sessionFactory
        self.referenceDate = referenceDate
        self.observer = observer
        self.observability = observability
    }

    func execute(
        _ input: GraphChatRequestPipelineInput,
        sessionResources: @escaping SessionResourcesProvider,
        foundationalArtifactSession:
            @escaping FoundationalArtifactSessionProvider,
        onAttemptResources: @escaping AttemptResourcesHandler,
        validateCurrentRequest: @escaping CurrentRequestValidator,
        commitFinalizedTurn: @escaping TurnCommitHandler,
        onProviderEvent: @escaping ProviderEventHandler
    ) async throws -> GraphChatRequestPipelineCompletion {
        await record(
            input.requestID,
            stage: .preflight,
            phase: .started,
            usesProvider: false
        )
        let preflightResult = try await preflight.evaluate(
            GraphChatRequestPreflightInput(
                requestID: input.requestID,
                requestedAt: input.requestedAt,
                question: input.question,
                graphScope: input.key.graphScope,
                chatScope: input.key.chatScope,
                conversationState: input.turnStateSnapshot
            )
        )
        await record(
            input.requestID,
            stage: .preflight,
            phase: .completed,
            usesProvider: preflightResult.usesProvider
        )
        try await validateCurrentRequest()

        switch preflightResult {
        case .local(let plan):
            return try await finalizeLocalPlan(
                plan,
                input: input,
                commitFinalizedTurn: commitFinalizedTurn
            )

        case .provider(let plan):
            await record(
                input.requestID,
                stage: .foundationalIntent,
                phase: .started,
                usesProvider: false
            )
            let foundationalResolution =
                try await foundationalCoordinator.resolve(
                    providerPlan: plan,
                    requestID: input.requestID,
                    requestedAt: input.requestedAt
                )
            await record(
                input.requestID,
                stage: .foundationalIntent,
                phase: .completed,
                usesProvider: false
            )
            try await validateCurrentRequest()

            switch foundationalResolution {
            case .local(let localPlan):
                return try await finalizeLocalPlan(
                    localPlan,
                    input: input,
                    commitFinalizedTurn: commitFinalizedTurn
                )

            case .compiled(let intent, let schemaContext):
                let artifactSession = try await foundationalArtifactSession(
                    plan.scopeKey
                )
                let finalizedTurn =
                    try await foundationalExecutor.execute(
                        intent: intent,
                        schemaContext: schemaContext,
                        providerPlan: plan,
                        requestID: input.requestID,
                        artifactSession: artifactSession,
                        onActivity: { activity in
                            onProviderEvent(
                                .toolActivity(activity)
                            )
                        },
                        validateCurrentRequest:
                            validateCurrentRequest,
                        finalize: { execution in
                            await self.record(
                                input.requestID,
                                stage: .answerFinalization,
                                phase: .started,
                                usesProvider: false
                            )
                            let turn =
                                try await self.finalizer
                                    .finalizeLocalIntentTurn(
                                        GraphChatLocalIntentAnswerFinalizationInput(
                                            requestID:
                                                input.requestID,
                                            completedAt:
                                                self.referenceDate(),
                                            requestQuestion:
                                                plan.providerQuestion,
                                            expectedCommittedState:
                                                plan.expectedCommittedState,
                                            execution: execution
                                        ),
                                        currentCommittedState:
                                            input.turnStateSnapshot
                                    )
                            await self.record(
                                input.requestID,
                                stage: .answerFinalization,
                                phase: .completed,
                                usesProvider: false
                            )
                            return turn
                        },
                        commit: { turn in
                            try await self.commit(
                                turn,
                                requestID: input.requestID,
                                usesProvider: false,
                                commitFinalizedTurn:
                                    commitFinalizedTurn
                            )
                        }
                    )
                return GraphChatRequestPipelineCompletion(
                    finalizedTurn: finalizedTurn,
                    usedProvider: false
                )

            case .providerFallback(let schemaContext):
                await record(
                    input.requestID,
                    stage: .semanticIntent,
                    phase: .started,
                    usesProvider: false
                )
                let semanticResolution =
                    try await semanticCoordinator
                        .resolve(
                            providerPlan: plan,
                            schemaContext:
                                schemaContext,
                            requestID:
                                input.requestID,
                            requestedAt:
                                input.requestedAt
                        )
                await record(
                    input.requestID,
                    stage: .semanticIntent,
                    phase: .completed,
                    usesProvider: false
                )
                try await validateCurrentRequest()

                switch semanticResolution {
                case .local(let localPlan):
                    return try await finalizeLocalPlan(
                        localPlan,
                        input: input,
                        commitFinalizedTurn:
                            commitFinalizedTurn
                    )

                case .compiled(
                    let adaptation,
                    let executionSchemaContext
                ):
                    let artifactSession =
                        try await foundationalArtifactSession(
                            plan.scopeKey
                        )
                    let finalizedTurn =
                        try await semanticExecutor
                            .execute(
                                adaptation:
                                    adaptation,
                                schemaContext:
                                    executionSchemaContext,
                                providerPlan: plan,
                                requestID:
                                    input.requestID,
                                artifactSession:
                                    artifactSession,
                                onActivity: {
                                    activity in
                                    onProviderEvent(
                                        .toolActivity(
                                            activity
                                        )
                                    )
                                },
                                validateCurrentRequest:
                                    validateCurrentRequest,
                                finalize: {
                                    execution in
                                    await self.record(
                                        input.requestID,
                                        stage:
                                            .answerFinalization,
                                        phase: .started,
                                        usesProvider:
                                            false
                                    )
                                    let turn =
                                        try await self
                                            .finalizer
                                            .finalizeLocalIntentTurn(
                                                GraphChatLocalIntentAnswerFinalizationInput(
                                                    requestID:
                                                        input.requestID,
                                                    completedAt:
                                                        self.referenceDate(),
                                                    requestQuestion:
                                                        plan.providerQuestion,
                                                    expectedCommittedState:
                                                        plan.expectedCommittedState,
                                                    execution:
                                                        execution
                                                ),
                                                currentCommittedState:
                                                    input.turnStateSnapshot
                                            )
                                    await self.record(
                                        input.requestID,
                                        stage:
                                            .answerFinalization,
                                        phase:
                                            .completed,
                                        usesProvider:
                                            false
                                    )
                                    return turn
                                },
                                commit: { turn in
                                    try await self
                                        .commit(
                                            turn,
                                            requestID:
                                                input.requestID,
                                            usesProvider:
                                                false,
                                            commitFinalizedTurn:
                                                commitFinalizedTurn
                                        )
                                }
                            )
                    return GraphChatRequestPipelineCompletion(
                        finalizedTurn:
                            finalizedTurn,
                        usedProvider: false
                    )

                case .legacyProviderFallback:
                    break
                }
            }

            await record(
                input.requestID,
                stage: .sessionResources,
                phase: .started,
                usesProvider: true
            )
            let initialResources = try await sessionResources(plan)
            await record(
                input.requestID,
                stage: .sessionResources,
                phase: .completed,
                usesProvider: true
            )
            do {
                try await initialResources.primaryResultLedger.bind(
                    requestID: input.requestID
                )
            } catch {
                await sessionFactory.cleanupFailedAttempt(
                    initialResources,
                    requestProviderCancellation: false
                )
                throw error
            }

            var completedResourcesForCleanup: GraphChatProviderSessionResources?
            do {
                let execution = try await contextRetry.execute(
                    initialResources: initialResources,
                    question: plan.providerQuestion,
                    continuationOperation: plan.continuationOperation,
                    onAttemptResources: { resources in
                        await self.observability.record(
                            .semanticIntent(
                                GraphChatSemanticIntentMetric(
                                    event:
                                        .answerProviderStarted,
                                    family: nil,
                                    answerProviderCallCount:
                                        1
                                )
                            )
                        )
                        await self.record(
                            input.requestID,
                            stage: .providerExecution,
                            phase: .started,
                            usesProvider: true
                        )
                        await onAttemptResources(resources)
                    },
                    onEvent: onProviderEvent
                )
                await record(
                    input.requestID,
                    stage: .providerExecution,
                    phase: .completed,
                    usesProvider: true
                )
                completedResourcesForCleanup = execution.resources
                try await validateCurrentRequest()

                let validationContext =
                    execution.request.conversationContext
                    ?? execution.resources.conversationContext
                let primaryResult = await execution.resources
                    .primaryResultLedger.primaryResult(
                        requestID: input.requestID,
                        graphScope: execution.resources.key.graphScope,
                        chatScope: execution.resources.key.chatScope,
                        artifactSessionID:
                            execution.resources.artifactSessionID,
                        transactionID:
                            execution.resources.artifactTransactionID
                    )
                await record(
                    input.requestID,
                    stage: .answerFinalization,
                    phase: .started,
                    usesProvider: true
                )
                let finalizedTurn = try await finalizer.finalizeProviderTurn(
                    GraphChatProviderAnswerFinalizationInput(
                        requestID: input.requestID,
                        completedAt: referenceDate(),
                        providerAnswer: execution.finalAnswer,
                        conversationContext: validationContext,
                        responseLanguage: execution.resources.responseLanguage,
                        continuationOperation: plan.continuationOperation,
                        requestQuestion: plan.providerQuestion,
                        expectedCommittedState: plan.expectedCommittedState,
                        primaryResult: primaryResult,
                        authoritativeFactExpectation: nil,
                        artifactContext: GraphChatArtifactCommitContext(
                            graphScope: execution.resources.key.graphScope,
                            chatScope: execution.resources.key.chatScope,
                            sessionID: execution.resources.artifactSessionID,
                            transactionID:
                                execution.resources.artifactTransactionID
                        ),
                        presentationRegistry:
                            execution.resources.presentationRegistry
                    ),
                    evidenceRegistry: execution.resources.evidenceRegistry,
                    artifactRegistry: execution.resources.artifactRegistry,
                    conversationTransaction:
                        execution.resources.conversationTransaction,
                    currentCommittedState: input.turnStateSnapshot
                )
                await record(
                    input.requestID,
                    stage: .answerFinalization,
                    phase: .completed,
                    usesProvider: true
                )
                do {
                    try await commit(
                        finalizedTurn,
                        requestID: input.requestID,
                        usesProvider: true,
                        commitFinalizedTurn: commitFinalizedTurn
                    )
                } catch {
                    await execution.resources.artifactRegistry
                        .removeCommittedArtifacts(
                            finalizedTurn.committedArtifactIDs,
                            sessionID: execution.resources.artifactSessionID
                        )
                    throw error
                }
                await sessionFactory.finishCommittedAttempt(
                    execution.resources,
                    requestID: input.requestID
                )
                completedResourcesForCleanup = nil
                return GraphChatRequestPipelineCompletion(
                    finalizedTurn: finalizedTurn,
                    usedProvider: true
                )
            } catch {
                if let completedResourcesForCleanup {
                    await sessionFactory.cleanupFailedAttempt(
                        completedResourcesForCleanup,
                        requestProviderCancellation: false
                    )
                }
                throw error
            }
        }
    }

    private func finalizeLocalPlan(
        _ plan: GraphChatLocalTurnPlan,
        input: GraphChatRequestPipelineInput,
        commitFinalizedTurn: @escaping TurnCommitHandler
    ) async throws -> GraphChatRequestPipelineCompletion {
        await record(
            input.requestID,
            stage: .answerFinalization,
            phase: .started,
            usesProvider: false
        )
        let finalizedTurn = try await finalizer.finalizeLocalTurn(
            GraphChatLocalAnswerFinalizationInput(
                requestID: input.requestID,
                completedAt: referenceDate(),
                answer: plan.answer,
                baseState: plan.baseState,
                expectedCommittedState: plan.expectedCommittedState,
                pendingClarification: plan.pendingClarification,
                responseLanguage: plan.responseLanguage
            ),
            currentCommittedState: input.turnStateSnapshot
        )
        await record(
            input.requestID,
            stage: .answerFinalization,
            phase: .completed,
            usesProvider: false
        )
        try await commit(
            finalizedTurn,
            requestID: input.requestID,
            usesProvider: false,
            commitFinalizedTurn: commitFinalizedTurn
        )
        return GraphChatRequestPipelineCompletion(
            finalizedTurn: finalizedTurn,
            usedProvider: false
        )
    }

    private func commit(
        _ finalizedTurn: GraphChatFinalizedTurn,
        requestID: UUID,
        usesProvider: Bool,
        commitFinalizedTurn: TurnCommitHandler
    ) async throws {
        await record(
            requestID,
            stage: .turnCommit,
            phase: .started,
            usesProvider: usesProvider
        )
        try await commitFinalizedTurn(finalizedTurn)
        await record(
            requestID,
            stage: .turnCommit,
            phase: .completed,
            usesProvider: usesProvider
        )
    }

    private func record(
        _ requestID: UUID,
        stage: GraphChatRequestPipelineStage,
        phase: GraphChatRequestPipelineStagePhase,
        usesProvider: Bool
    ) async {
        await observer.record(
            GraphChatRequestPipelineEvent(
                requestID: requestID,
                stage: stage,
                phase: phase,
                usesProvider: usesProvider
            )
        )
    }
}

private nonisolated extension GraphChatRequestPreflightResult {
    var usesProvider: Bool {
        if case .provider = self {
            return true
        }
        return false
    }
}
