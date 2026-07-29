//
//  GraphChatOrchestrator.swift
//  BrainMesh
//
//  Lifecycle and composition actor for graph-scoped streamed answers.
//

import Foundation

nonisolated enum GraphChatConcurrentRequestPolicy: String, CaseIterable, Hashable, Sendable {
    case cancelPrevious
}

actor GraphChatOrchestrator {
    private let concurrentRequestPolicy: GraphChatConcurrentRequestPolicy
    private let conversationStateReducer: GraphChatConversationStateReducer
    private let conversationContextBuilder: GraphChatConversationContextBuilder
    private let requestPreflight: GraphChatRequestPreflight
    private let responseLanguageSelector: GraphChatResponseLanguageSelector
    private let schemaProvider: any GraphSchemaSnapshotProviding
    private let artifactRevalidator: any GraphChatAnswerArtifactRevalidating
    private let observability: any GraphChatObservabilityRecording
    private let sessionFactory: GraphChatProviderSessionFactory
    private let requestPipeline: GraphChatRequestPipeline
    private let correctionCompiler:
        GraphChatInterpretationCorrectionCompiler
    private let errorMapper: GraphChatProviderErrorMapper
    private let presentationResolver: GraphChatAnswerPresentationResolver
    private let referenceDate: @Sendable () -> Date

    private var stateMachine = GraphChatOrchestratorStateMachine()
    private var resources = GraphChatOrchestratorResourceStore()
    private var conversationRuntime = GraphChatOrchestratorConversationRuntime()

    init(
        provider: any GraphChatModelProvider,
        intentInterpreter:
            any GraphChatIntentInterpreting =
                PassThroughGraphChatIntentInterpreter(),
        schemaProvider: any GraphSchemaSnapshotProviding = GraphSchemaService.shared,
        foundationalQueryExecutor:
            any GraphChatFoundationalQueryExecuting =
                GraphChatQueryEngine.shared,
        semanticSearchExecutor:
            any GraphChatLocalIntentSearchExecuting =
                SearchGraphTool(),
        semanticNodeExecutor:
            any GraphChatLocalIntentNodeExecuting =
                GetNodeTool(),
        semanticStatsExecutor:
            any GraphChatLocalIntentStatsExecuting =
                UnavailableGraphChatLocalStatsExecutor(),
        toolRunnerFactory: any GraphChatModelToolRunnerFactory,
        toolBudgetPolicy: GraphChatToolBudgetPolicy = .default,
        concurrentRequestPolicy: GraphChatConcurrentRequestPolicy = .cancelPrevious,
        conversationStatePolicy: GraphChatConversationStatePolicy = .default,
        conversationContextBudget: GraphChatConversationContextBudget = .default,
        referenceResolver: GraphChatConversationReferenceResolver =
            GraphChatConversationReferenceResolver(),
        responseLanguageSelector: GraphChatResponseLanguageSelector =
            GraphChatResponseLanguageSelector(),
        artifactRevalidator: any GraphChatAnswerArtifactRevalidating =
            GraphChatLiveAnswerArtifactRevalidator(),
        evidenceValidator: any GraphEvidenceValidating =
            GraphEvidenceSourceValidator.shared,
        observability: any GraphChatObservabilityRecording =
            NoOpGraphChatObservabilityRecorder(),
        referenceDate: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current,
        pipelineObserver: GraphChatRequestPipelineObserver = .disabled
    ) {
        self.concurrentRequestPolicy = concurrentRequestPolicy
        let composition = GraphChatOrchestratorComposition(
            provider: provider,
            intentInterpreter: intentInterpreter,
            schemaProvider: schemaProvider,
            foundationalQueryExecutor: foundationalQueryExecutor,
            semanticSearchExecutor:
                semanticSearchExecutor,
            semanticNodeExecutor:
                semanticNodeExecutor,
            semanticStatsExecutor:
                semanticStatsExecutor,
            toolRunnerFactory: toolRunnerFactory,
            toolBudgetPolicy: toolBudgetPolicy,
            conversationStatePolicy: conversationStatePolicy,
            conversationContextBudget: conversationContextBudget,
            referenceResolver: referenceResolver,
            responseLanguageSelector: responseLanguageSelector,
            artifactRevalidator: artifactRevalidator,
            evidenceValidator: evidenceValidator,
            observability: observability,
            referenceDate: referenceDate,
            calendar: calendar,
            timeZone: timeZone,
            pipelineObserver: pipelineObserver
        )

        self.conversationStateReducer = composition.conversationStateReducer
        self.conversationContextBuilder = composition.conversationContextBuilder
        self.requestPreflight = composition.requestPreflight
        self.responseLanguageSelector = composition.responseLanguageSelector
        self.schemaProvider = schemaProvider
        self.artifactRevalidator = composition.artifactRevalidator
        self.observability = observability
        self.sessionFactory = composition.sessionFactory
        self.requestPipeline = composition.requestPipeline
        self.correctionCompiler =
            GraphChatInterpretationCorrectionCompiler(
                calendar: calendar,
                timeZone: timeZone
            )
        self.errorMapper = composition.errorMapper
        self.presentationResolver = composition.presentationResolver
        self.referenceDate = composition.referenceDate
    }

    func prepare(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async throws {
        let key = try requestPreflight.validatedKey(
            graphScope: graphScope,
            chatScope: chatScope
        )
        try await cancelActiveGenerationForNewRequest()
        await discardScopeMismatchedResources(matching: key)

        let turn = conversationRuntime.stateForTurn(
            key: key,
            reducer: conversationStateReducer
        )
        let responseLanguage = responseLanguageSelector.language(for: "")
        let conversationContext = conversationContextBuilder.makeSnapshot(
            from: turn.state.snapshot
        )

        if resources.preparedSessionMatches(
            key: key,
            conversationBaseState: turn.state,
            conversationContext: conversationContext,
            responseLanguage: responseLanguage
        ) {
            return
        }
        await discardPreparedSession()

        let sessionResources = try await makeSessionResources(
            for: key,
            conversationBaseState: turn.state,
            conversationContext: conversationContext,
            responseLanguage: responseLanguage
        )
        do {
            try await sessionFactory.prewarm(sessionResources)
            resources.installPreparedSession(sessionResources)
            stateMachine.transition(
                .prepared(
                    key: key,
                    sessionID: sessionResources.sessionID
                )
            )
        } catch {
            throw mapError(
                error,
                language: responseLanguage
            )
        }
    }

    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream {
        let requestID = UUID()
        let generation = GraphChatGenerationIdentity(requestID: requestID)
        let pair = GraphChatEventStream.makeStream()
        let streamController = GraphChatRequestStreamController(
            requestID: requestID,
            continuation: pair.continuation
        )
        var executionTaskCreated = false

        do {
            try await cancelActiveGenerationForNewRequest()
            let key = try requestPreflight.validatedKey(
                graphScope: graphScope,
                chatScope: chatScope
            )
            await discardScopeMismatchedResources(matching: key)
            let turn = conversationRuntime.stateForTurn(
                key: key,
                reducer: conversationStateReducer
            )

            let transition = stateMachine.transition(
                .requestStarted(
                    key: key,
                    generation: generation
                )
            )
            guard transition.wasApplied else {
                throw GraphChatError(
                    code: .concurrentRequest,
                    message: "Eine andere Graph-Chat-Anfrage ist noch aktiv."
                )
            }
            let task = Task { [weak self] in
                guard let self else {
                    await streamController.start()
                    await streamController.fail(
                        GraphChatError(
                            code: .unexpected,
                            message: "Der Graph-Chat-Orchestrator wurde verworfen."
                        )
                    )
                    await streamController.finish()
                    return
                }
                await self.runRequest(
                    generation: generation,
                    question: question,
                    key: key,
                    turnStateSnapshot: turn.state,
                    expectedCommittedState: turn.committedStateSnapshot,
                    streamController: streamController,
                    continuation: pair.continuation
                )
            }
            executionTaskCreated = true
            resources.installActiveGeneration(
                identity: generation,
                task: task
            )
            pair.continuation.onTermination = { @Sendable [weak self] _ in
                Task {
                    await self?.cancel(requestID: requestID)
                }
            }
        } catch {
            if executionTaskCreated == false {
                await recordPlanner(
                    .terminalOutcome(.failed)
                )
            }
            await streamController.start()
            await streamController.fail(
                mapError(
                    error,
                    language: responseLanguageSelector.language(
                        for: question
                    )
                )
            )
            await streamController.finish()
        }

        return pair.stream
    }

    /// Executes a correction from a trusted, finalized interpretation. The
    /// old committed state remains authoritative until the local kernel has
    /// produced and atomically committed the replacement turn.
    func streamCorrectedIntent(
        _ request:
            GraphChatInterpretationCorrectionRequest
    ) async -> GraphChatEventStream {
        let requestID = UUID()
        let generation =
            GraphChatGenerationIdentity(
                requestID: requestID
            )
        let pair =
            GraphChatEventStream.makeStream()
        let streamController =
            GraphChatRequestStreamController(
                requestID: requestID,
                continuation:
                    pair.continuation
            )
        var executionTaskCreated = false

        do {
            try await cancelActiveGenerationForNewRequest()
            let key = try requestPreflight
                .validatedKey(
                    graphScope:
                        request.binding
                            .graphScope,
                    chatScope:
                        request.binding
                            .chatScope
                )
            let state = try validatedCorrectionState(
                request,
                key: key
            )
            let transition =
                stateMachine.transition(
                    .requestStarted(
                        key: key,
                        generation: generation
                    )
                )
            guard transition.wasApplied else {
                throw GraphChatError(
                    code: .concurrentRequest,
                    message:
                        "Eine andere Graph-Chat-Anfrage ist noch aktiv."
                )
            }
            let task = Task { [weak self] in
                guard let self else {
                    await streamController.start()
                    await streamController.fail(
                        GraphChatError(
                            code: .unexpected,
                            message:
                                "Der Graph-Chat-Orchestrator wurde verworfen."
                        )
                    )
                    await streamController.finish()
                    return
                }
                await self.runCorrection(
                    request,
                    requestID: requestID,
                    generation: generation,
                    key: key,
                    baseState:
                        state.baseState,
                    expectedCommittedState:
                        state
                            .expectedCommittedState,
                    artifactSession:
                        state.artifactSession,
                    streamController:
                        streamController,
                    continuation:
                        pair.continuation
                )
            }
            executionTaskCreated = true
            resources.installActiveGeneration(
                identity: generation,
                task: task
            )
            pair.continuation.onTermination = {
                @Sendable [weak self] _ in
                Task {
                    await self?.cancel(
                        requestID: requestID
                    )
                }
            }
        } catch {
            if (error as? GraphChatError)?
                .code != .concurrentRequest
            {
                await recordInterpretation(
                    .correctionStale
                )
            }
            if executionTaskCreated == false {
                await recordPlanner(
                    .terminalOutcome(.failed)
                )
            }
            await streamController.start()
            await streamController.fail(
                mapError(
                    error,
                    language:
                        request.binding
                            .originalInterpretation
                            .responseLanguage
                )
            )
            await streamController.finish()
        }
        return pair.stream
    }

    func cancelCurrentGeneration() async {
        guard let activeGeneration = resources.activeGeneration else {
            return
        }
        await cancelAndWait(activeGeneration)
    }

    func discardSession() async {
        await discardSession(reason: .sessionDiscarded)
    }

    func discardSession(
        reason: GraphChatConversationResetReason
    ) async {
        stateMachine.transition(.discardStarted(reason: reason))
        if let activeGeneration = resources.activeGeneration {
            await cancelAndWait(activeGeneration)
        }

        let discarded = resources.removeAll()
        await cleanupPreparedSession(discarded.preparedSession)
        if let artifactSession = discarded.artifactSession {
            await artifactSession.registry.removeAll(
                reason: GraphChatArtifactClearReasonMapper.reason(for: reason)
            )
            stateMachine.transition(
                .artifactSessionDiscarded(
                    sessionID: artifactSession.sessionID
                )
            )
        }
        stateMachine.transition(.resourcesDiscarded)
        conversationRuntime.discard(reason: reason)
        stateMachine.transition(.discardFinished)
    }

    func conversationStateSnapshot() -> GraphChatConversationState? {
        conversationRuntime.snapshot()
    }

    func resolveAnswerPresentation(
        artifactIDs: [GraphChatAnswerArtifactID],
        evidence: [GraphEvidence],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatAnswerPresentationResolution {
        await presentationResolver.resolve(
            artifactIDs: artifactIDs,
            evidence: evidence,
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSession: resources.artifactSession
        )
    }

    func restoreConversationState(
        from checkpoint: GraphChatConversationCheckpoint
    ) async throws {
        let key = try requestPreflight.validatedKey(
            graphScope: checkpoint.graphScope,
            chatScope: checkpoint.chatScope
        )
        guard checkpoint.belongsTo(
            graphScope: key.graphScope,
            chatScope: key.chatScope
        ),
            conversationRuntime.acceptsRestore(
                for: key,
                lifecycleKey: stateMachine.state.scopeKey
            )
        else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Der Conversation-State gehört nicht zum aktiven Graph-Chat-Scope."
            )
        }

        stateMachine.transition(.restoreStarted)
        if let activeGeneration = resources.activeGeneration {
            await cancelAndWait(activeGeneration)
        }
        let discarded = resources.removeAll()
        await cleanupPreparedSession(discarded.preparedSession)
        if let artifactSession = discarded.artifactSession {
            await artifactSession.registry.removeAll(
                reason: GraphChatArtifactClearReasonMapper.restoredCheckpoint
            )
            stateMachine.transition(
                .artifactSessionDiscarded(
                    sessionID: artifactSession.sessionID
                )
            )
        }
        stateMachine.transition(.resourcesDiscarded)

        do {
            try conversationRuntime.restore(checkpoint, key: key)
            stateMachine.transition(.restoreFinished(key: key))
        } catch {
            stateMachine.transition(.restoreFinished(key: key))
            throw error
        }
    }

    func stateSnapshotForTesting() -> GraphChatOrchestratorState {
        stateMachine.state
    }

    private struct ValidatedCorrectionState:
        Sendable
    {
        let baseState:
            GraphChatConversationState
        let expectedCommittedState:
            GraphChatConversationState
        let artifactSession:
            GraphChatArtifactSessionResources
    }

    private func validatedCorrectionState(
        _ request:
            GraphChatInterpretationCorrectionRequest,
        key:
            GraphChatOrchestrationScopeKey
    ) throws -> ValidatedCorrectionState {
        let binding = request.binding
        guard
            binding.version == .v1,
            binding.graphScope == key.graphScope,
            binding.chatScope == key.chatScope,
            binding.originalInterpretation
                .isCorrectionEditable,
            let origin =
                binding.originalInterpretation
                    .correctionOrigin,
            origin.matches(
                binding.originalInterpretation
            ),
            origin.artifactSessionID
                == binding.artifactSessionID,
            origin.adaptation.intent.version
                == binding.intentDomainVersion,
            let expected =
                binding.expectedCurrentCheckpoint
                    .state,
            expected.conversationID
                == binding.conversationID,
            expected.graphScope
                == key.graphScope,
            expected.chatScope
                == key.chatScope,
            conversationRuntime.snapshot()
                == expected,
            expected.turnContexts.contains(
                where: {
                    $0.id
                        == binding
                            .originalTurnID
                }
            ),
            let artifactSession =
                resources.artifactSession,
            artifactSession.key == key,
            artifactSession.sessionID
                == binding.artifactSessionID
        else {
            throw GraphChatError(
                code: .invalidRequest,
                message:
                    "Die Interpretation gehört nicht mehr zum aktuellen Graph-Chat-Zustand."
            )
        }

        let baseState:
            GraphChatConversationState
        if let checkpointState =
                binding
                    .checkpointBeforeOriginalTurn
                    .state
        {
            baseState = checkpointState
        } else {
            baseState =
                GraphChatConversationState.initial(
                    graphScope:
                        key.graphScope,
                    chatScope:
                        key.chatScope,
                    conversationID:
                        binding
                            .conversationID
                )
        }
        let originalTurnIndex =
            expected.turnContexts.firstIndex {
                $0.id
                    == binding
                        .originalTurnID
            }
        guard
            let originalTurnIndex,
            baseState.conversationID
                == binding.conversationID,
            baseState.graphScope
                == key.graphScope,
            baseState.chatScope
                == key.chatScope,
            baseState.turnContexts.contains(
                where: {
                    $0.id
                        == binding
                            .originalTurnID
                }
            ) == false,
            Array(
                expected.turnContexts.prefix(
                    upTo:
                        originalTurnIndex
                )
            ) == baseState.turnContexts
        else {
            throw GraphChatError(
                code: .invalidRequest,
                message:
                    "Der Checkpoint vor dem zu ersetzenden Turn ist nicht mehr gültig."
            )
        }
        return ValidatedCorrectionState(
            baseState: baseState,
            expectedCommittedState:
                expected,
            artifactSession:
                artifactSession
        )
    }

    private func runCorrection(
        _ request:
            GraphChatInterpretationCorrectionRequest,
        requestID: UUID,
        generation:
            GraphChatGenerationIdentity,
        key:
            GraphChatOrchestrationScopeKey,
        baseState:
            GraphChatConversationState,
        expectedCommittedState:
            GraphChatConversationState,
        artifactSession:
            GraphChatArtifactSessionResources,
        streamController:
            GraphChatRequestStreamController,
        continuation:
            GraphChatEventStream.Continuation
    ) async {
        await streamController.start()
        let outcome: GraphChatRequestOutcome
        var localRerunStarted = false

        do {
            try validateCurrentCorrection(
                generation,
                request: request,
                expectedCommittedState:
                    expectedCommittedState,
                artifactSession:
                    artifactSession
            )
            let preflightResult =
                try await requestPreflight.evaluate(
                    GraphChatRequestPreflightInput(
                        requestID: requestID,
                        requestedAt:
                            referenceDate(),
                        question:
                            request.binding
                                .originalQuestion,
                        graphScope:
                            key.graphScope,
                        chatScope:
                            key.chatScope,
                        conversationState:
                            baseState
                    )
                )
            guard case .provider(let providerPlan) =
                    preflightResult,
                  providerPlan.requestBaseState
                    == baseState
            else {
                throw GraphChatInterpretationCorrectionCompilationError
                    .stale(
                        .conversationChanged
                    )
            }
            try validateCurrentCorrection(
                generation,
                request: request,
                expectedCommittedState:
                    expectedCommittedState,
                artifactSession:
                    artifactSession
            )

            let schemaContext =
                try await schemaProvider
                    .makeSnapshot(
                        in: key.graphScope,
                        exampleFieldIDs: []
                    )
            try validateCurrentCorrection(
                generation,
                request: request,
                expectedCommittedState:
                    expectedCommittedState,
                artifactSession:
                    artifactSession
            )

            let compilation =
                try correctionCompiler.compile(
                    request: request,
                    providerPlan:
                        providerPlan,
                    schemaContext:
                        schemaContext,
                    requestID:
                        requestID,
                    requestedAt:
                        referenceDate()
                )
            await recordInterpretation(
                .correctionValidated
            )
            try validateCurrentCorrection(
                generation,
                request: request,
                expectedCommittedState:
                    expectedCommittedState,
                artifactSession:
                    artifactSession
            )

            localRerunStarted = true
            await recordInterpretation(
                .localCorrectionRerunStarted
            )
            let finalizedTurn =
                try await requestPipeline
                    .executeCorrection(
                        GraphChatInterpretationCorrectionPipelineInput(
                            requestID:
                                requestID,
                            requestedAt:
                                referenceDate(),
                            question:
                                request.binding
                                    .originalQuestion,
                            providerPlan:
                                providerPlan,
                            expectedCommittedState:
                                expectedCommittedState,
                            adaptation:
                                compilation
                                    .adaptation,
                            schemaContext:
                                compilation
                                    .schemaContext,
                            artifactIDsToReplace:
                                request.binding
                                    .artifactIDsToReplace
                        ),
                        artifactSession:
                            artifactSession,
                        onActivity: {
                            continuation.yield(
                                .toolActivity($0)
                            )
                        },
                        validateCurrentRequest: {
                            [weak self] in
                            guard let self else {
                                throw CancellationError()
                            }
                            try await self
                                .validateCurrentCorrection(
                                    generation,
                                    request:
                                        request,
                                    expectedCommittedState:
                                        expectedCommittedState,
                                    artifactSession:
                                        artifactSession
                                )
                        },
                        commitFinalizedTurn: {
                            [weak self] turn in
                            guard let self else {
                                throw CancellationError()
                            }
                            try await self.commit(
                                turn,
                                generation:
                                    generation,
                                expectedCommittedState:
                                    expectedCommittedState
                            )
                        }
                    )

            await discardPreparedSession()
            await recordInterpretation(
                .localCorrectionRerunCommitted
            )
            outcome = .completed
            await streamController.complete(
                finalizedTurn.answer
            )
        } catch is CancellationError {
            if localRerunStarted {
                await recordInterpretation(
                    .localCorrectionRerunRolledBack
                )
            }
            outcome = .cancelled
            await streamController.cancel()
        } catch let error as GraphChatProviderError
        where error.code == .cancelled {
            if localRerunStarted {
                await recordInterpretation(
                    .localCorrectionRerunRolledBack
                )
            }
            outcome = .cancelled
            await streamController.cancel()
        } catch let error as GraphChatToolError
        where error.code == .cancelled {
            if localRerunStarted {
                await recordInterpretation(
                    .localCorrectionRerunRolledBack
                )
            }
            outcome = .cancelled
            await streamController.cancel()
        } catch {
            if isStaleCorrectionError(error) {
                await recordInterpretation(
                    .correctionStale
                )
            }
            if localRerunStarted {
                await recordInterpretation(
                    .localCorrectionRerunRolledBack
                )
            }
            outcome = .failed
            await streamController.fail(
                mapCorrectionError(
                    error,
                    language:
                        request.binding
                            .originalInterpretation
                            .responseLanguage
                )
            )
        }

        if outcome == .cancelled {
            await recordPlanner(
                .cancellation(.correction)
            )
        }
        await recordPlanner(
            .terminalOutcome(outcome)
        )
        finishRequest(
            requestID: requestID,
            outcome: outcome
        )
        await streamController.finish()
    }

    private func validateCurrentCorrection(
        _ generation:
            GraphChatGenerationIdentity,
        request:
            GraphChatInterpretationCorrectionRequest,
        expectedCommittedState:
            GraphChatConversationState,
        artifactSession:
            GraphChatArtifactSessionResources
    ) throws {
        try validateCurrentGeneration(
            generation
        )
        guard
            conversationRuntime.snapshot()
                == expectedCommittedState
        else {
            throw GraphChatInterpretationCorrectionCompilationError
                .stale(
                    .checkpointChanged
                )
        }
        guard
            resources.artifactSession?
                .sessionID
                == artifactSession.sessionID,
            resources.artifactSession?
                .key
                == artifactSession.key
        else {
            throw GraphChatInterpretationCorrectionCompilationError
                .stale(
                    .artifactSessionChanged
                )
        }
        guard
            request.binding
                .expectedCurrentCheckpoint
                .state
                == expectedCommittedState
        else {
            throw GraphChatInterpretationCorrectionCompilationError
                .stale(
                    .checkpointChanged
                )
        }
        guard
            request.binding
                .artifactSessionID
                == artifactSession.sessionID
        else {
            throw GraphChatInterpretationCorrectionCompilationError
                .stale(
                    .artifactSessionChanged
                )
        }
    }

    private func mapCorrectionError(
        _ error: Error,
        language:
            GraphChatResponseLanguage
    ) -> GraphChatError {
        if error
            is GraphChatInterpretationCorrectionCompilationError {
            let localizer =
                GraphChatResponseLocalizer(
                    language: language
                )
            return GraphChatError(
                code: .invalidRequest,
                message:
                    localizer.userFacingFailure(
                        .invalidRequest
                    )
            )
        }
        return mapError(
            error,
            language: language
        )
    }

    private func isStaleCorrectionError(
        _ error: Error
    ) -> Bool {
        if let compilationError =
                error
                    as? GraphChatInterpretationCorrectionCompilationError
        {
            if case .stale = compilationError {
                return true
            }
            return false
        }
        if let executionError =
                error
                    as? GraphChatLocalIntentExecutionError
        {
            return executionError
                == .staleSchemaIdentity
                || executionError
                    == .staleResultSet
        }
        if let artifactError =
                error
                    as? GraphChatAnswerArtifactRegistryError
        {
            return artifactError
                == .artifactInvalidated
        }
        return false
    }

    private func recordInterpretation(
        _ event:
            GraphChatIntentInterpretationLifecycleEvent
    ) async {
        await observability.record(
            .intentInterpretation(
                GraphChatIntentInterpretationMetric(
                    event: event
                )
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

    private func runRequest(
        generation: GraphChatGenerationIdentity,
        question: String,
        key: GraphChatOrchestrationScopeKey,
        turnStateSnapshot: GraphChatConversationState,
        expectedCommittedState: GraphChatConversationState?,
        streamController: GraphChatRequestStreamController,
        continuation: GraphChatEventStream.Continuation
    ) async {
        await streamController.start()
        let outcome: GraphChatRequestOutcome
        var pipelineStarted = false

        do {
            try validateCurrentGeneration(generation)
            pipelineStarted = true
            let completion = try await requestPipeline.execute(
                GraphChatRequestPipelineInput(
                    requestID: generation.requestID,
                    requestedAt: referenceDate(),
                    question: question,
                    key: key,
                    turnStateSnapshot: turnStateSnapshot
                ),
                sessionResources: { [weak self] plan in
                    guard let self else {
                        throw CancellationError()
                    }
                    return try await self.takeOrCreateSessionResources(
                        for: plan,
                        requestID: generation.requestID
                    )
                },
                foundationalArtifactSession: { [weak self] key in
                    guard let self else {
                        throw CancellationError()
                    }
                    return await self.artifactSessionResources(
                        for: key
                    )
                },
                onAttemptResources: { [weak self] attemptResources in
                    await self?.setActiveResources(
                        attemptResources,
                        requestID: generation.requestID
                    )
                },
                validateCurrentRequest: { [weak self] in
                    guard let self else {
                        throw CancellationError()
                    }
                    try await self.validateCurrentGeneration(generation)
                },
                commitFinalizedTurn: { [weak self] finalizedTurn in
                    guard let self else {
                        throw CancellationError()
                    }
                    try await self.commit(
                        finalizedTurn,
                        generation: generation,
                        expectedCommittedState: expectedCommittedState
                    )
                },
                onProviderEvent: { event in
                    switch event {
                    case .toolActivity(let activity):
                        continuation.yield(.toolActivity(activity))
                    case .partialAnswer(let text):
                        continuation.yield(.partialAnswer(text))
                    }
                }
            )
            if completion.usedProvider == false {
                await discardPreparedSession()
            }
            outcome = .completed
            await streamController.complete(completion.finalizedTurn.answer)
        } catch is CancellationError {
            outcome = .cancelled
            await streamController.cancel()
        } catch let error as GraphChatProviderError
        where error.code == .cancelled {
            outcome = .cancelled
            await streamController.cancel()
        } catch let error as GraphChatToolError
        where error.code == .cancelled {
            outcome = .cancelled
            await streamController.cancel()
        } catch {
            outcome = .failed
            await streamController.fail(
                mapError(
                    error,
                    language: responseLanguageSelector.language(
                        for: question
                    )
                )
            )
        }

        if outcome == .cancelled,
           pipelineStarted == false {
            await recordPlanner(
                .cancellation(.unknown)
            )
        }
        await recordPlanner(
            .terminalOutcome(outcome)
        )
        finishRequest(
            requestID: generation.requestID,
            outcome: outcome
        )
        await streamController.finish()
    }

    private func takeOrCreateSessionResources(
        for plan: GraphChatProviderTurnPlan,
        requestID: UUID
    ) async throws -> GraphChatProviderSessionResources {
        switch resources.takePreparedSession(
            matching: plan.scopeKey,
            conversationBaseState: plan.requestBaseState,
            conversationContext: plan.conversationContext,
            responseLanguage: plan.responseLanguage
        ) {
        case .missing:
            return try await makeSessionResources(
                for: plan.scopeKey,
                conversationBaseState: plan.requestBaseState,
                conversationContext: plan.conversationContext,
                responseLanguage: plan.responseLanguage
            )

        case .reused(let prepared):
            stateMachine.transition(
                .preparedConsumed(
                    requestID: requestID,
                    sessionID: prepared.sessionID
                )
            )
            return prepared

        case .discarded(let prepared):
            stateMachine.transition(
                .preparedDiscarded(sessionID: prepared.sessionID)
            )
            await cleanupPreparedSession(prepared)
            return try await makeSessionResources(
                for: plan.scopeKey,
                conversationBaseState: plan.requestBaseState,
                conversationContext: plan.conversationContext,
                responseLanguage: plan.responseLanguage
            )
        }
    }

    private func makeSessionResources(
        for key: GraphChatOrchestrationScopeKey,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage
    ) async throws -> GraphChatProviderSessionResources {
        let artifactSession = await artifactSessionResources(for: key)
        return try await sessionFactory.makeInitialSession(
            for: key,
            artifactSession: artifactSession,
            conversationBaseState: conversationBaseState,
            conversationContext: conversationContext,
            responseLanguage: responseLanguage
        )
    }

    private func artifactSessionResources(
        for key: GraphChatOrchestrationScopeKey
    ) async -> GraphChatArtifactSessionResources {
        if let artifactSession = resources.artifactSession,
           artifactSession.key == key {
            return artifactSession
        }

        if let oldSession = resources.removeArtifactSession() {
            await oldSession.registry.removeAll(
                reason: GraphChatArtifactClearReasonMapper.scopeChangeReason(
                    from: oldSession.key,
                    to: key
                )
            )
            stateMachine.transition(
                .artifactSessionDiscarded(sessionID: oldSession.sessionID)
            )
        }
        let sessionID = GraphChatAnswerArtifactSessionID()
        let artifactSession = GraphChatArtifactSessionResources(
            key: key,
            sessionID: sessionID,
            registry: GraphChatAnswerArtifactRegistry(
                graphScope: key.graphScope,
                scope: key.chatScope,
                sessionID: sessionID,
                revalidator: artifactRevalidator
            )
        )
        resources.installArtifactSession(artifactSession)
        stateMachine.transition(
            .artifactSessionInstalled(
                key: key,
                sessionID: sessionID
            )
        )
        return artifactSession
    }

    private func discardScopeMismatchedResources(
        matching key: GraphChatOrchestrationScopeKey
    ) async {
        let discarded = resources.removeScopeMismatchedResources(
            matching: key
        )
        if let preparedSession = discarded.preparedSession {
            stateMachine.transition(
                .preparedDiscarded(sessionID: preparedSession.sessionID)
            )
            await cleanupPreparedSession(preparedSession)
        }
        if let artifactSession = discarded.artifactSession {
            await artifactSession.registry.removeAll(
                reason: GraphChatArtifactClearReasonMapper.scopeChangeReason(
                    from: artifactSession.key,
                    to: key
                )
            )
            stateMachine.transition(
                .artifactSessionDiscarded(
                    sessionID: artifactSession.sessionID
                )
            )
        }
    }

    private func discardPreparedSession() async {
        guard let preparedSession = resources.removePreparedSession() else {
            return
        }
        stateMachine.transition(
            .preparedDiscarded(sessionID: preparedSession.sessionID)
        )
        await cleanupPreparedSession(preparedSession)
    }

    private func cleanupPreparedSession(
        _ preparedSession: GraphChatProviderSessionResources?
    ) async {
        guard let preparedSession else {
            return
        }
        await sessionFactory.cleanupFailedAttempt(
            preparedSession,
            requestProviderCancellation: false
        )
    }

    private func cancelActiveGenerationForNewRequest() async throws {
        guard let activeGeneration = resources.activeGeneration else {
            return
        }
        switch concurrentRequestPolicy {
        case .cancelPrevious:
            await cancelAndWait(activeGeneration)
        }
    }

    private func cancelAndWait(
        _ activeGeneration: GraphChatActiveGenerationResources
    ) async {
        stateMachine.transition(
            .cancellationRequested(
                requestID: activeGeneration.identity.requestID
            )
        )
        activeGeneration.task.cancel()
        if let providerResources = activeGeneration.providerResources {
            await sessionFactory.requestCancellation(providerResources)
        }
        await activeGeneration.task.value
    }

    private func cancel(requestID: UUID) async {
        guard let activeGeneration = resources.activeGeneration,
              activeGeneration.identity.requestID == requestID else {
            return
        }
        stateMachine.transition(
            .cancellationRequested(requestID: requestID)
        )
        activeGeneration.task.cancel()
        if let providerResources = activeGeneration.providerResources {
            await sessionFactory.requestCancellation(providerResources)
        }
    }

    private func setActiveResources(
        _ providerResources: GraphChatProviderSessionResources,
        requestID: UUID
    ) {
        guard resources.setActiveProviderResources(
            providerResources,
            requestID: requestID
        ) else {
            return
        }
        stateMachine.transition(
            .activeSessionChanged(
                requestID: requestID,
                sessionID: providerResources.sessionID
            )
        )
    }

    private func commit(
        _ finalizedTurn: GraphChatFinalizedTurn,
        generation: GraphChatGenerationIdentity,
        expectedCommittedState: GraphChatConversationState?
    ) throws {
        try validateCurrentGeneration(generation)
        try conversationRuntime.commit(
            finalizedTurn.conversationState,
            expectedCommittedState: expectedCommittedState
        )
    }

    private func validateCurrentGeneration(
        _ generation: GraphChatGenerationIdentity
    ) throws {
        try Task.checkCancellation()
        guard stateMachine.isCurrent(generation),
              resources.activeGeneration?.identity == generation else {
            throw CancellationError()
        }
    }

    private func finishRequest(
        requestID: UUID,
        outcome: GraphChatRequestOutcome
    ) {
        _ = resources.clearActiveGeneration(requestID: requestID)
        stateMachine.transition(
            .requestFinished(
                requestID: requestID,
                outcome: outcome
            )
        )
    }

    private func mapError(
        _ error: Error,
        language: GraphChatResponseLanguage
    ) -> GraphChatError {
        errorMapper.mapForPresentation(
            error,
            language: language
        )
    }
}
