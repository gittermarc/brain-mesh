//
//  GraphChatOrchestrator.swift
//  BrainMesh
//
//  UI-independent orchestration for graph-scoped, streamed model answers.
//

import Foundation

nonisolated enum GraphChatConcurrentRequestPolicy: String, CaseIterable, Hashable, Sendable {
    case cancelPrevious
}

actor GraphChatOrchestrator {
    private struct ActiveGeneration {
        let requestID: UUID
        let task: Task<Void, Never>
        var resources: GraphChatProviderSessionResources?
    }

    private let concurrentRequestPolicy: GraphChatConcurrentRequestPolicy
    private let conversationStateReducer: GraphChatConversationStateReducer
    private let conversationContextBuilder: GraphChatConversationContextBuilder
    private let requestPreflight: GraphChatRequestPreflight
    private let responseLanguageSelector: GraphChatResponseLanguageSelector
    private let answerFinalizer: GraphChatAnswerFinalizer
    private let artifactRevalidator: any GraphChatAnswerArtifactRevalidating
    private let evidenceValidator: any GraphEvidenceValidating
    private let sessionFactory: GraphChatProviderSessionFactory
    private let contextRetry: GraphChatProviderContextRetry
    private let errorMapper: GraphChatProviderErrorMapper
    private let referenceDate: @Sendable () -> Date

    private var preparedSession: GraphChatProviderSessionResources?
    private var artifactSession: GraphChatArtifactSessionResources?
    private var activeGeneration: ActiveGeneration?
    private var conversationState: GraphChatConversationState?
    private var pendingResetReason: GraphChatConversationResetReason = .newConversation

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
        evidenceValidator: any GraphEvidenceValidating = GraphEvidenceSourceValidator.shared,
        referenceDate: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian),
        timeZone: TimeZone = .current
    ) {
        self.concurrentRequestPolicy = concurrentRequestPolicy
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
            referenceDate: referenceDate,
            calendar: calendar,
            timeZone: timeZone
        )
        let providerExecutor = GraphChatProviderExecutor(
            provider: provider,
            sessionFactory: sessionFactory
        )
        self.conversationStateReducer = stateReducer
        self.conversationContextBuilder = contextBuilder
        self.requestPreflight = GraphChatRequestPreflight(
            conversationStateReducer: stateReducer,
            conversationContextBuilder: contextBuilder,
            referenceResolver: referenceResolver,
            responseLanguageSelector: responseLanguageSelector,
            missingContextPolicy: missingContextPolicy,
            localAnswerBuilder: localAnswerBuilder
        )
        self.answerFinalizer = GraphChatAnswerFinalizer(
            conversationStateReducer: stateReducer,
            referenceResolver: referenceResolver,
            missingContextPolicy: missingContextPolicy,
            localAnswerBuilder: localAnswerBuilder,
            evidenceValidator: evidenceValidator
        )
        self.responseLanguageSelector = responseLanguageSelector
        self.artifactRevalidator = artifactRevalidator
        self.evidenceValidator = evidenceValidator
        self.sessionFactory = sessionFactory
        self.contextRetry = GraphChatProviderContextRetry(
            sessionFactory: sessionFactory,
            requestBuilder: requestBuilder,
            executor: providerExecutor
        )
        self.errorMapper = errorMapper
        self.referenceDate = referenceDate
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
        let baseState = conversationStateForTurn(for: key)
        await discardPreparedSession(
            unlessMatching: key,
            conversationBaseState: baseState
        )

        if preparedSession?.key == key,
            preparedSession?.conversationBaseState == baseState
        {
            return
        }

        let preparationLanguage = responseLanguageSelector.language(for: "")
        let preparationContext = conversationContextBuilder.makeSnapshot(
            from: baseState.snapshot
        )
        let resources = try await makeSessionResources(
            for: key,
            conversationBaseState: baseState,
            conversationContext: preparationContext,
            responseLanguage: preparationLanguage
        )
        do {
            try await sessionFactory.prewarm(resources)
            preparedSession = resources
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
        let pair = GraphChatEventStream.makeStream()

        do {
            try await cancelActiveGenerationForNewRequest()
            let key = try requestPreflight.validatedKey(
                graphScope: graphScope,
                chatScope: chatScope
            )
            let turnStateSnapshot = conversationStateForTurn(for: key)
            await discardPreparedSession(
                unlessMatching: key,
                conversationBaseState: turnStateSnapshot
            )

            let task = Task { [weak self] in
                guard let self else {
                    pair.continuation.yield(
                        .failure(
                            GraphChatError(
                                code: .unexpected,
                                message: "Der Graph-Chat-Orchestrator wurde verworfen."
                            )
                        )
                    )
                    pair.continuation.finish()
                    return
                }
                await self.performRequest(
                    requestID: requestID,
                    question: question,
                    key: key,
                    turnStateSnapshot: turnStateSnapshot,
                    continuation: pair.continuation
                )
            }
            activeGeneration = ActiveGeneration(
                requestID: requestID,
                task: task,
                resources: nil
            )
            pair.continuation.onTermination = { @Sendable [weak self] _ in
                Task {
                    await self?.cancel(requestID: requestID)
                }
            }
        } catch {
            pair.continuation.yield(.started(requestID: requestID))
            pair.continuation.yield(.failure(mapError(error)))
            pair.continuation.finish()
        }

        return pair.stream
    }

    func cancelCurrentGeneration() async {
        guard let activeGeneration else {
            return
        }
        activeGeneration.task.cancel()
        if let resources = activeGeneration.resources {
            await sessionFactory.requestCancellation(resources)
        }
        await activeGeneration.task.value
    }

    func discardSession() async {
        await discardSession(reason: .sessionDiscarded)
    }

    func discardSession(
        reason: GraphChatConversationResetReason
    ) async {
        await cancelCurrentGeneration()
        if let preparedSession {
            await sessionFactory.cleanupFailedAttempt(
                preparedSession,
                requestProviderCancellation: false
            )
            self.preparedSession = nil
        }
        if let artifactSession {
            await artifactSession.registry.removeAll(
                reason: artifactClearReason(for: reason)
            )
            self.artifactSession = nil
        }
        conversationState = nil
        pendingResetReason = reason
    }

    func conversationStateSnapshot() -> GraphChatConversationState? {
        conversationState
    }

    func resolveAnswerPresentation(
        artifactIDs: [GraphChatAnswerArtifactID],
        evidence: [GraphEvidence],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatAnswerPresentationResolution {
        guard graphScope == chatScope.graphScope else {
            return .unavailable(
                graphScope: graphScope,
                chatScope: chatScope,
                requestedArtifactIDs: artifactIDs,
                reason: .scopeMismatch
            )
        }

        let validatedEvidence: [GraphEvidence]
        do {
            validatedEvidence = try await evidenceValidator.validatedEvidence(
                evidence,
                in: chatScope
            )
        } catch {
            return .unavailable(
                graphScope: graphScope,
                chatScope: chatScope,
                requestedArtifactIDs: artifactIDs,
                reason: .notRegisteredOrInvalidated
            )
        }

        let expectedKey = GraphChatOrchestrationScopeKey(
            graphScope: graphScope,
            chatScope: chatScope
        )
        guard let artifactSession, artifactSession.key == expectedKey else {
            return .unavailable(
                graphScope: graphScope,
                chatScope: chatScope,
                requestedArtifactIDs: artifactIDs,
                evidence: validatedEvidence,
                reason: .sessionUnavailable
            )
        }

        let revalidatedAt = referenceDate()
        var resolvedArtifacts: [GraphChatResolvedAnswerArtifact] = []
        var artifactEvidence: [GraphEvidence] = []
        resolvedArtifacts.reserveCapacity(artifactIDs.count)

        var seenArtifactIDs = Set<GraphChatAnswerArtifactID>()
        for artifactID in artifactIDs where seenArtifactIDs.insert(artifactID).inserted {
            do {
                guard let resolution = try await artifactSession.registry.resolvedArtifact(
                    for: artifactID,
                    graphScope: graphScope,
                    sessionID: artifactSession.sessionID
                ) else {
                    continue
                }
                resolvedArtifacts.append(
                    GraphChatResolvedAnswerArtifact(
                        artifact: resolution.artifact,
                        revalidatedAt: revalidatedAt
                    )
                )
                artifactEvidence.append(contentsOf: resolution.evidence)
            } catch {
                continue
            }
        }

        return GraphChatAnswerPresentationResolution(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: artifactSession.sessionID,
            requestedArtifactIDs: artifactIDs,
            artifacts: resolvedArtifacts,
            evidence: GraphEvidenceCollection(
                validatedEvidence + artifactEvidence
            ).values
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
        ) else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Der Conversation-State gehört nicht zum aktiven Graph-Chat-Scope."
            )
        }

        await cancelCurrentGeneration()
        if let preparedSession {
            await sessionFactory.cleanupFailedAttempt(
                preparedSession,
                requestProviderCancellation: false
            )
            self.preparedSession = nil
        }
        if let artifactSession {
            await artifactSession.registry.removeAll(reason: .restoredCheckpoint)
            self.artifactSession = nil
        }

        if let state = checkpoint.state {
            guard state.graphScope == key.graphScope,
                  state.chatScope == key.chatScope else {
                throw GraphChatError(
                    code: .invalidRequest,
                    message: "Der wiederherzustellende Conversation-State ist scopefremd."
                )
            }
            conversationState = state
        } else {
            conversationState = GraphChatConversationState.initial(
                graphScope: key.graphScope,
                chatScope: key.chatScope,
                resetReason: .newConversation
            )
        }
        pendingResetReason = .newConversation
    }

    private func performRequest(
        requestID: UUID,
        question: String,
        key: GraphChatOrchestrationScopeKey,
        turnStateSnapshot: GraphChatConversationState,
        continuation: GraphChatEventStream.Continuation
    ) async {
        continuation.yield(.started(requestID: requestID))
        var completedResourcesForCleanup: GraphChatProviderSessionResources?
        defer {
            continuation.finish()
            clearActiveGeneration(requestID: requestID)
        }

        do {
            let preflightResult = try await requestPreflight.evaluate(
                GraphChatRequestPreflightInput(
                    requestID: requestID,
                    requestedAt: referenceDate(),
                    question: question,
                    graphScope: key.graphScope,
                    chatScope: key.chatScope,
                    conversationState: turnStateSnapshot
                )
            )
            guard case .provider(let plan) = preflightResult else {
                if case .local(let localPlan) = preflightResult {
                    guard let currentCommittedState = conversationState else {
                        throw CancellationError()
                    }
                    let finalizedTurn = try await answerFinalizer.finalizeLocalTurn(
                        GraphChatLocalAnswerFinalizationInput(
                            requestID: requestID,
                            completedAt: referenceDate(),
                            answer: localPlan.answer,
                            baseState: localPlan.baseState,
                            expectedCommittedState: localPlan.expectedCommittedState,
                            pendingClarification: localPlan.pendingClarification
                        ),
                        currentCommittedState: currentCommittedState
                    )
                    conversationState = finalizedTurn.conversationState
                    continuation.yield(
                        .completed(finalizedTurn.answer)
                    )
                }
                return
            }

            let initialResources = try await takeOrCreateSessionResources(
                for: plan.scopeKey,
                conversationBaseState: plan.requestBaseState,
                conversationContext: plan.conversationContext,
                responseLanguage: plan.responseLanguage
            )
            let execution = try await contextRetry.execute(
                initialResources: initialResources,
                question: plan.providerQuestion,
                continuationOperation: plan.continuationOperation,
                onAttemptResources: { [weak self] resources in
                    await self?.setActiveResources(
                        resources,
                        requestID: requestID
                    )
                },
                onEvent: { event in
                    switch event {
                    case .toolActivity(let activity):
                        continuation.yield(.toolActivity(activity))
                    case .partialAnswer(let text):
                        continuation.yield(.partialAnswer(text))
                    }
                }
            )
            let completedResources = execution.resources
            completedResourcesForCleanup = completedResources
            let validationContext =
                execution.request.conversationContext
                ?? completedResources.conversationContext
            guard let currentCommittedState = conversationState else {
                throw CancellationError()
            }
            let finalizedTurn = try await answerFinalizer.finalizeProviderTurn(
                GraphChatProviderAnswerFinalizationInput(
                    requestID: requestID,
                    completedAt: referenceDate(),
                    providerAnswer: execution.finalAnswer,
                    conversationContext: validationContext,
                    responseLanguage: completedResources.responseLanguage,
                    continuationOperation: plan.continuationOperation,
                    requestQuestion: plan.providerQuestion,
                    expectedCommittedState: plan.expectedCommittedState,
                    artifactContext: GraphChatArtifactCommitContext(
                        graphScope: completedResources.key.graphScope,
                        chatScope: completedResources.key.chatScope,
                        sessionID: completedResources.artifactSessionID,
                        transactionID: completedResources.artifactTransactionID
                    )
                ),
                evidenceRegistry: completedResources.evidenceRegistry,
                artifactRegistry: completedResources.artifactRegistry,
                conversationTransaction: completedResources.conversationTransaction,
                currentCommittedState: currentCommittedState
            )
            conversationState = finalizedTurn.conversationState
            await sessionFactory.finishCommittedAttempt(completedResources)
            completedResourcesForCleanup = nil
            continuation.yield(.completed(finalizedTurn.answer))
        } catch is CancellationError {
            if let completedResourcesForCleanup {
                await sessionFactory.cleanupFailedAttempt(
                    completedResourcesForCleanup,
                    requestProviderCancellation: false
                )
            }
            continuation.yield(.cancelled)
        } catch let error as GraphChatProviderError where error.code == .cancelled {
            if let completedResourcesForCleanup {
                await sessionFactory.cleanupFailedAttempt(
                    completedResourcesForCleanup,
                    requestProviderCancellation: false
                )
            }
            continuation.yield(.cancelled)
        } catch let error as GraphChatToolError where error.code == .cancelled {
            if let completedResourcesForCleanup {
                await sessionFactory.cleanupFailedAttempt(
                    completedResourcesForCleanup,
                    requestProviderCancellation: false
                )
            }
            continuation.yield(.cancelled)
        } catch {
            if let completedResourcesForCleanup {
                await sessionFactory.cleanupFailedAttempt(
                    completedResourcesForCleanup,
                    requestProviderCancellation: false
                )
            }
            continuation.yield(.failure(mapError(error)))
        }
    }

    private func takeOrCreateSessionResources(
        for key: GraphChatOrchestrationScopeKey,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage
    ) async throws -> GraphChatProviderSessionResources {
        if let preparedSession,
            preparedSession.key == key,
            preparedSession.conversationBaseState == conversationBaseState,
            preparedSession.conversationContext == conversationContext,
            preparedSession.responseLanguage == responseLanguage
        {
            self.preparedSession = nil
            return preparedSession
        }
        if let preparedSession {
            await sessionFactory.cleanupFailedAttempt(
                preparedSession,
                requestProviderCancellation: false
            )
            self.preparedSession = nil
        }
        return try await makeSessionResources(
            for: key,
            conversationBaseState: conversationBaseState,
            conversationContext: conversationContext,
            responseLanguage: responseLanguage
        )
    }

    private func makeSessionResources(
        for key: GraphChatOrchestrationScopeKey,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage
    ) async throws -> GraphChatProviderSessionResources {
        let artifactResources = await artifactSessionResources(for: key)
        return try await sessionFactory.makeInitialSession(
            for: key,
            artifactSession: artifactResources,
            conversationBaseState: conversationBaseState,
            conversationContext: conversationContext,
            responseLanguage: responseLanguage
        )
    }

    private func cancelActiveGenerationForNewRequest() async throws {
        guard let activeGeneration else {
            return
        }
        switch concurrentRequestPolicy {
        case .cancelPrevious:
            activeGeneration.task.cancel()
            if let resources = activeGeneration.resources {
                await sessionFactory.requestCancellation(resources)
            }
            await activeGeneration.task.value
        }
    }

    private func cancel(requestID: UUID) async {
        guard let activeGeneration, activeGeneration.requestID == requestID else {
            return
        }
        activeGeneration.task.cancel()
        if let resources = activeGeneration.resources {
            await sessionFactory.requestCancellation(resources)
        }
    }

    private func setActiveResources(
        _ resources: GraphChatProviderSessionResources,
        requestID: UUID
    ) {
        guard var activeGeneration, activeGeneration.requestID == requestID else {
            return
        }
        activeGeneration.resources = resources
        self.activeGeneration = activeGeneration
    }

    private func clearActiveGeneration(requestID: UUID) {
        guard activeGeneration?.requestID == requestID else {
            return
        }
        activeGeneration = nil
    }

    private func discardPreparedSession(
        unlessMatching key: GraphChatOrchestrationScopeKey,
        conversationBaseState: GraphChatConversationState
    ) async {
        guard let preparedSession else {
            return
        }
        guard
            preparedSession.key != key
                || preparedSession.conversationBaseState != conversationBaseState
        else {
            return
        }
        await sessionFactory.cleanupFailedAttempt(
            preparedSession,
            requestProviderCancellation: false
        )
        self.preparedSession = nil
    }

    private func artifactSessionResources(
        for key: GraphChatOrchestrationScopeKey
    ) async -> GraphChatArtifactSessionResources {
        if let artifactSession, artifactSession.key == key {
            return artifactSession
        }
        if let artifactSession {
            await artifactSession.registry.removeAll(reason: .scopeChanged)
        }
        let sessionID = GraphChatAnswerArtifactSessionID()
        let resources = GraphChatArtifactSessionResources(
            key: key,
            sessionID: sessionID,
            registry: GraphChatAnswerArtifactRegistry(
                graphScope: key.graphScope,
                scope: key.chatScope,
                sessionID: sessionID,
                revalidator: artifactRevalidator
            )
        )
        artifactSession = resources
        return resources
    }

    private func artifactClearReason(
        for reason: GraphChatConversationResetReason
    ) -> GraphChatAnswerArtifactRegistryClearReason {
        switch reason {
        case .newConversation:
            return .newConversation
        case .graphChanged:
            return .graphChanged
        case .scopeChanged:
            return .scopeChanged
        case .graphLocked, .accessRevoked:
            return .graphLocked
        case .graphDeleted:
            return .graphDeleted
        case .sessionDiscarded:
            return .sessionDiscarded
        }
    }

    private func conversationStateForTurn(
        for key: GraphChatOrchestrationScopeKey
    ) -> GraphChatConversationState {
        if let conversationState {
            if conversationState.graphScope == key.graphScope,
                conversationState.chatScope == key.chatScope
            {
                return conversationState
            }
            let transition = conversationStateReducer.transition(
                conversationState,
                to: key.chatScope
            )
            self.conversationState = transition.state
            pendingResetReason = .newConversation
            return transition.state
        }

        let initial = GraphChatConversationState.initial(
            graphScope: key.graphScope,
            chatScope: key.chatScope,
            resetReason: pendingResetReason
        )
        conversationState = initial
        pendingResetReason = .newConversation
        return initial
    }

    private func mapError(_ error: Error) -> GraphChatError {
        errorMapper.map(error)
    }
}
