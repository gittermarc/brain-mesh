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
    private let artifactRevalidator: any GraphChatAnswerArtifactRevalidating
    private let sessionFactory: GraphChatProviderSessionFactory
    private let requestPipeline: GraphChatRequestPipeline
    private let errorMapper: GraphChatProviderErrorMapper
    private let presentationResolver: GraphChatAnswerPresentationResolver
    private let referenceDate: @Sendable () -> Date

    private var stateMachine = GraphChatOrchestratorStateMachine()
    private var resources = GraphChatOrchestratorResourceStore()
    private var conversationRuntime = GraphChatOrchestratorConversationRuntime()

    init(
        provider: any GraphChatModelProvider,
        schemaProvider: any GraphSchemaSnapshotProviding = GraphSchemaService.shared,
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
        referenceDate: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current,
        pipelineObserver: GraphChatRequestPipelineObserver = .disabled
    ) {
        self.concurrentRequestPolicy = concurrentRequestPolicy
        let composition = GraphChatOrchestratorComposition(
            provider: provider,
            schemaProvider: schemaProvider,
            toolRunnerFactory: toolRunnerFactory,
            toolBudgetPolicy: toolBudgetPolicy,
            conversationStatePolicy: conversationStatePolicy,
            conversationContextBudget: conversationContextBudget,
            referenceResolver: referenceResolver,
            responseLanguageSelector: responseLanguageSelector,
            artifactRevalidator: artifactRevalidator,
            evidenceValidator: evidenceValidator,
            referenceDate: referenceDate,
            calendar: calendar,
            timeZone: timeZone,
            pipelineObserver: pipelineObserver
        )

        self.conversationStateReducer = composition.conversationStateReducer
        self.conversationContextBuilder = composition.conversationContextBuilder
        self.requestPreflight = composition.requestPreflight
        self.responseLanguageSelector = composition.responseLanguageSelector
        self.artifactRevalidator = composition.artifactRevalidator
        self.sessionFactory = composition.sessionFactory
        self.requestPipeline = composition.requestPipeline
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
            throw mapError(error)
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

            let transition = stateMachine.transition(
                .requestStarted(
                    key: key,
                    generation: generation
                )
            )
            guard transition.wasApplied else {
                task.cancel()
                throw GraphChatError(
                    code: .concurrentRequest,
                    message: "Eine andere Graph-Chat-Anfrage ist noch aktiv."
                )
            }
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
            await streamController.start()
            await streamController.fail(mapError(error))
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

        do {
            try validateCurrentGeneration(generation)
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
            await streamController.fail(mapError(error))
        }

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

    private func mapError(_ error: Error) -> GraphChatError {
        errorMapper.map(error)
    }
}
