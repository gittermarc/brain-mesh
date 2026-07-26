//
//  GraphChatRequestPipeline.swift
//  BrainMesh
//
//  Explicit composition of preflight, execution, finalization and turn commit.
//

import Foundation

nonisolated enum GraphChatRequestPipelineStage: String, CaseIterable, Hashable, Sendable {
    case preflight
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
    private let contextRetry: GraphChatProviderContextRetry
    private let finalizer: GraphChatAnswerFinalizer
    private let sessionFactory: GraphChatProviderSessionFactory
    private let referenceDate: @Sendable () -> Date
    private let observer: GraphChatRequestPipelineObserver

    init(
        preflight: GraphChatRequestPreflight,
        contextRetry: GraphChatProviderContextRetry,
        finalizer: GraphChatAnswerFinalizer,
        sessionFactory: GraphChatProviderSessionFactory,
        referenceDate: @escaping @Sendable () -> Date,
        observer: GraphChatRequestPipelineObserver = .disabled
    ) {
        self.preflight = preflight
        self.contextRetry = contextRetry
        self.finalizer = finalizer
        self.sessionFactory = sessionFactory
        self.referenceDate = referenceDate
        self.observer = observer
    }

    func execute(
        _ input: GraphChatRequestPipelineInput,
        sessionResources: @escaping SessionResourcesProvider,
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

        case .provider(let plan):
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
