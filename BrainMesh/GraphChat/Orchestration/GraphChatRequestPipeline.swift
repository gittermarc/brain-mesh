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
    case localExecution
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

private actor GraphChatRequestPipelineStageRegistry {
    private var stages:
        [UUID: GraphChatRequestPipelineStage] = [:]

    func set(
        _ stage: GraphChatRequestPipelineStage,
        requestID: UUID
    ) {
        stages[requestID] = stage
    }

    func take(
        requestID: UUID
    ) -> GraphChatRequestPipelineStage? {
        stages.removeValue(
            forKey: requestID
        )
    }
}

/// Trusted input for a correction that has already been rebound to a fresh
/// schema snapshot. This path deliberately contains no interpreter or answer
/// provider dependency.
nonisolated struct GraphChatInterpretationCorrectionPipelineInput:
    Sendable
{
    let requestID: UUID
    let requestedAt: Date
    let question: String
    let providerPlan: GraphChatProviderTurnPlan
    let expectedCommittedState:
        GraphChatConversationState
    let adaptation:
        GraphChatTypedIntentAdaptation
    let schemaContext: GraphSchemaContext
    let artifactIDsToReplace:
        [GraphChatAnswerArtifactID]
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
    private let stageRegistry =
        GraphChatRequestPipelineStageRegistry()

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
        do {
            let completion = try await executeStages(
                input,
                sessionResources: sessionResources,
                foundationalArtifactSession:
                    foundationalArtifactSession,
                onAttemptResources:
                    onAttemptResources,
                validateCurrentRequest:
                    validateCurrentRequest,
                commitFinalizedTurn:
                    commitFinalizedTurn,
                onProviderEvent:
                    onProviderEvent
            )
            _ = await stageRegistry.take(
                requestID: input.requestID
            )
            return completion
        } catch {
            let stage = await stageRegistry.take(
                requestID: input.requestID
            )
            if isCancellation(error) {
                await recordPlanner(
                    .cancellation(
                        cancellationStage(
                            for: stage
                        )
                    )
                )
            }
            throw error
        }
    }

    private func executeStages(
        _ input: GraphChatRequestPipelineInput,
        sessionResources: @escaping SessionResourcesProvider,
        foundationalArtifactSession:
            @escaping FoundationalArtifactSessionProvider,
        onAttemptResources:
            @escaping AttemptResourcesHandler,
        validateCurrentRequest:
            @escaping CurrentRequestValidator,
        commitFinalizedTurn:
            @escaping TurnCommitHandler,
        onProviderEvent:
            @escaping ProviderEventHandler
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
                await recordPlanner(
                    .foundationalFastPath(
                        intent.kind
                    )
                )
                await recordPlanner(
                    .localIntent(
                        typedIntentKind(
                            for: intent.kind
                        )
                    )
                )
                let artifactSession = try await foundationalArtifactSession(
                    plan.scopeKey
                )
                await record(
                    input.requestID,
                    stage: .localExecution,
                    phase: .started,
                    usesProvider: false
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
                                            correctionRequestQuestion:
                                                input.question,
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
                await record(
                    input.requestID,
                    stage: .localExecution,
                    phase: .completed,
                    usesProvider: false
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
                            commitFinalizedTurn,
                        clarificationAlreadyObserved:
                            true
                    )

                case .compiled(
                    let adaptation,
                    let executionSchemaContext
                ):
                    let artifactSession =
                        try await foundationalArtifactSession(
                            plan.scopeKey
                        )
                    await record(
                        input.requestID,
                        stage: .localExecution,
                        phase: .started,
                        usesProvider: false
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
                                                    correctionRequestQuestion:
                                                        input
                                                            .question,
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
                    await record(
                        input.requestID,
                        stage: .localExecution,
                        phase: .completed,
                        usesProvider: false
                    )
                    return GraphChatRequestPipelineCompletion(
                        finalizedTurn:
                            finalizedTurn,
                        usedProvider: false
                    )

                case .legacyProviderFallback(_):
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

    /// Re-executes a user-corrected, app-compiled intent. The caller supplies
    /// the pre-turn provider plan only as deterministic conversation context;
    /// neither semantic interpretation nor free answer generation is entered.
    func executeCorrection(
        _ input:
            GraphChatInterpretationCorrectionPipelineInput,
        artifactSession:
            GraphChatArtifactSessionResources,
        onActivity:
            @escaping @Sendable (
                GraphChatToolActivity
            ) -> Void,
        validateCurrentRequest:
            @escaping CurrentRequestValidator,
        commitFinalizedTurn:
            @escaping TurnCommitHandler
    ) async throws -> GraphChatFinalizedTurn {
        do {
            let turn = try await executeCorrectionStages(
                input,
                artifactSession:
                    artifactSession,
                onActivity:
                    onActivity,
                validateCurrentRequest:
                    validateCurrentRequest,
                commitFinalizedTurn:
                    commitFinalizedTurn
            )
            _ = await stageRegistry.take(
                requestID: input.requestID
            )
            return turn
        } catch {
            _ = await stageRegistry.take(
                requestID: input.requestID
            )
            throw error
        }
    }

    private func executeCorrectionStages(
        _ input:
            GraphChatInterpretationCorrectionPipelineInput,
        artifactSession:
            GraphChatArtifactSessionResources,
        onActivity:
            @escaping @Sendable (
                GraphChatToolActivity
            ) -> Void,
        validateCurrentRequest:
            @escaping CurrentRequestValidator,
        commitFinalizedTurn:
            @escaping TurnCommitHandler
    ) async throws -> GraphChatFinalizedTurn {
        await recordPlanner(
            .correctionRerun
        )
        await recordPlanner(
            .localIntent(
                input.adaptation.intent.kind
            )
        )
        try await validateCurrentRequest()
        await record(
            input.requestID,
            stage: .localExecution,
            phase: .started,
            usesProvider: false
        )
        let finalizedTurn =
            try await semanticExecutor.execute(
                adaptation:
                    input.adaptation,
                schemaContext:
                    input.schemaContext,
                providerPlan:
                    input.providerPlan,
                requestID:
                    input.requestID,
                artifactSession:
                    artifactSession,
                onActivity:
                    onActivity,
                validateCurrentRequest:
                    validateCurrentRequest,
                finalize: { execution in
                    await self.record(
                        input.requestID,
                        stage:
                            .answerFinalization,
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
                                        input.question,
                                    correctionRequestQuestion:
                                        input.question,
                                    expectedCommittedState:
                                        input
                                            .expectedCommittedState,
                                    execution:
                                        execution,
                                    artifactCommitBehavior:
                                        .deferred,
                                    artifactIDsToReplace:
                                        input
                                            .artifactIDsToReplace
                                ),
                                currentCommittedState:
                                    input
                                        .expectedCommittedState
                            )
                    guard
                        let interpretation =
                            turn.answer
                                .interpretation,
                        interpretation
                            .isCorrectionEditable,
                        interpretation
                            .turnBinding
                            .requestID
                            == input.requestID,
                        interpretation
                            .correctionOrigin?
                            .adaptation
                            == input.adaptation,
                        interpretation
                            .correctionOrigin?
                            .artifactSessionID
                            == artifactSession
                                .sessionID,
                        turn.deferredArtifactCommit?
                            .replacedArtifactIDs
                            == input
                                .artifactIDsToReplace
                    else {
                        throw GraphChatInterpretationCorrectionCompilationError
                            .stale(
                                .interpretationChanged
                            )
                    }
                    await self.record(
                        input.requestID,
                        stage:
                            .answerFinalization,
                        phase: .completed,
                        usesProvider: false
                    )
                    return turn
                },
                commit: { turn in
                    await self.record(
                        input.requestID,
                        stage: .turnCommit,
                        phase: .started,
                        usesProvider: false
                    )
                    try await commitFinalizedTurn(
                        turn
                    )
                }
            )
        await record(
            input.requestID,
            stage: .localExecution,
            phase: .completed,
            usesProvider: false
        )
        await record(
            input.requestID,
            stage: .turnCommit,
            phase: .completed,
            usesProvider: false
        )
        return finalizedTurn
    }

    private func finalizeLocalPlan(
        _ plan: GraphChatLocalTurnPlan,
        input: GraphChatRequestPipelineInput,
        commitFinalizedTurn:
            @escaping TurnCommitHandler,
        clarificationAlreadyObserved:
            Bool = false
    ) async throws -> GraphChatRequestPipelineCompletion {
        if clarificationAlreadyObserved == false,
           case .clarification =
                plan.answer.state
        {
            await recordPlanner(
                .clarification(nil)
            )
        }
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
        if phase == .started {
            await stageRegistry.set(
                stage,
                requestID: requestID
            )
        }
        await observer.record(
            GraphChatRequestPipelineEvent(
                requestID: requestID,
                stage: stage,
                phase: phase,
                usesProvider: usesProvider
            )
        )
    }

    private func recordPlanner(
        _ event: GraphChatTypedPlannerEvent
    ) async {
        await observability.record(
            .typedPlanner(
                GraphChatTypedPlannerMetric(
                    event: event
                )
            )
        )
    }

    private func typedIntentKind(
        for foundationalKind:
            GraphChatFoundationalIntentKind
    ) -> GraphChatTypedIntentKind {
        switch foundationalKind {
        case .singleNodeFieldValue:
            return .nodeDetails
        case .entityAttributeCollection:
            return .entityCollection
        case .nodeDetails:
            return .nodeDetails
        }
    }

    private func cancellationStage(
        for stage: GraphChatRequestPipelineStage?
    ) -> GraphChatTypedPlannerCancellationStage {
        switch stage {
        case .preflight:
            return .preflight
        case .foundationalIntent:
            return .foundationalFastPath
        case .semanticIntent:
            return .semanticInterpreter
        case .localExecution:
            return .localExecution
        case .sessionResources:
            return .providerResources
        case .providerExecution:
            return .legacyProvider
        case .answerFinalization:
            return .finalization
        case .turnCommit:
            return .commit
        case nil:
            return .unknown
        }
    }

    private func isCancellation(
        _ error: Error
    ) -> Bool {
        if error is CancellationError
            || Task.isCancelled
        {
            return true
        }
        if let providerError =
            error as? GraphChatProviderError
        {
            return providerError.code == .cancelled
        }
        if let toolError =
            error as? GraphChatToolError
        {
            return toolError.code == .cancelled
        }
        if let interpreterError =
            error as? GraphChatIntentInterpreterError
        {
            return interpreterError.code
                == .cancelled
        }
        if let graphError =
            error as? GraphChatError
        {
            return graphError.code == .cancelled
        }
        return false
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
