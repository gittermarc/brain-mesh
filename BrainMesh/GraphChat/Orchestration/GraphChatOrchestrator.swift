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
    private let referenceResolver: GraphChatConversationReferenceResolver
    private let requestPreflight: GraphChatRequestPreflight
    private let responseLanguageSelector: GraphChatResponseLanguageSelector
    private let missingContextPolicy: GraphChatReferenceMissingContextDeferPolicy
    private let localAnswerBuilder: GraphChatLocalAnswerBuilder
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
        self.referenceResolver = referenceResolver
        self.requestPreflight = GraphChatRequestPreflight(
            conversationStateReducer: stateReducer,
            conversationContextBuilder: contextBuilder,
            referenceResolver: referenceResolver,
            responseLanguageSelector: responseLanguageSelector,
            missingContextPolicy: missingContextPolicy,
            localAnswerBuilder: localAnswerBuilder
        )
        self.responseLanguageSelector = responseLanguageSelector
        self.missingContextPolicy = missingContextPolicy
        self.localAnswerBuilder = localAnswerBuilder
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
                    try await completeLocalAnswer(
                        localPlan,
                        requestID: requestID,
                        continuation: continuation
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
            var answer = try await validatedAnswer(
                from: execution.finalAnswer,
                registry: completedResources.evidenceRegistry,
                artifactRegistry: completedResources.artifactRegistry,
                artifactSessionID: completedResources.artifactSessionID,
                artifactTransactionID: completedResources.artifactTransactionID,
                transaction: completedResources.conversationTransaction,
                context: validationContext,
                language: completedResources.responseLanguage,
                continuationOperation: plan.continuationOperation,
                requestQuestion: plan.providerQuestion
            )
            try Task.checkCancellation()
            let candidateState = try await completedResources.conversationTransaction.finalizedState(
                requestID: requestID,
                completedAt: referenceDate(),
                validatedEvidenceIDs: answer.evidenceIDs
            )
            try Task.checkCancellation()
            guard conversationState == plan.expectedCommittedState else {
                throw CancellationError()
            }
            let committedArtifactIDs = try await completedResources.artifactRegistry.commit(
                transactionID: completedResources.artifactTransactionID,
                retaining: answer.artifactIDs
            )
            answer = answer.retainingArtifactIDs(Set(committedArtifactIDs))
            conversationState = candidateState
            await sessionFactory.finishCommittedAttempt(completedResources)
            completedResourcesForCleanup = nil
            continuation.yield(.completed(answer))
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

    private func validatedAnswer(
        from providerAnswer: GraphChatProviderFinalAnswer,
        registry: GraphChatEvidenceRegistry,
        artifactRegistry: GraphChatAnswerArtifactRegistry,
        artifactSessionID: GraphChatAnswerArtifactSessionID,
        artifactTransactionID: GraphChatAnswerArtifactTransactionID,
        transaction: GraphChatConversationStateTransaction,
        context: GraphChatConversationContextSnapshot,
        language: GraphChatResponseLanguage,
        continuationOperation: GraphChatConversationContinuationOperation?,
        requestQuestion: String
    ) async throws -> GraphChatAnswer {
        let requestedArtifactIDValues = providerAnswer.artifactIDValues
            + providerAnswer.sections.flatMap(\.artifactIDValues)
        let artifacts = try await artifactRegistry.validatedArtifacts(
            for: requestedArtifactIDValues,
            graphScope: context.graphScope,
            sessionID: artifactSessionID,
            transactionID: artifactTransactionID
        )
        let artifactsByID = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.id, $0) })
        var allEvidence: [GraphEvidence] = await registry.validatedEvidence(
            for: providerAnswer.evidenceIDValues
        )
        allEvidence.append(
            contentsOf: await registry.validatedEvidence(
                for: artifacts.flatMap(\.allEvidenceIDs).map {
                    $0.rawValue.uuidString
                }
            )
        )
        var sections: [GraphChatAnswerSection] = []
        sections.reserveCapacity(providerAnswer.sections.count)

        for section in providerAnswer.sections {
            let sectionEvidence = await registry.validatedEvidence(
                for: section.evidenceIDValues
            )
            let sectionArtifactIDs = validatedArtifactIDs(
                from: section.artifactIDValues,
                artifactsByID: artifactsByID
            )
            let sectionArtifactEvidence = await registry.validatedEvidence(
                for: sectionArtifactIDs.flatMap { artifactsByID[$0]?.allEvidenceIDs ?? [] }.map {
                    $0.rawValue.uuidString
                }
            )
            allEvidence.append(contentsOf: sectionEvidence)
            allEvidence.append(contentsOf: sectionArtifactEvidence)
            sections.append(
                GraphChatAnswerSection(
                    title: section.title,
                    text: section.text,
                    evidenceIDs: GraphEvidenceCollection(
                        sectionEvidence + sectionArtifactEvidence
                    ).values.map(\.id),
                    artifactIDs: sectionArtifactIDs,
                    querySummary: sectionArtifactIDs.compactMap {
                        artifactsByID[$0]?.querySummary
                    }.first,
                    state: sectionAnswerState(for: providerAnswer.responseState)
                )
            )
        }

        let validatedEvidence = GraphEvidenceCollection(allEvidence).values
        let deterministicFilters = await registry.filtersForAnswer()
        let providerFilters = providerAnswer.appliedFilters.map { filter in
            GraphChatAppliedFilter(
                fieldName: filter.fieldName,
                operationDescription: filter.operationDescription,
                valueDescription: filter.valueDescription
            )
        }
        let filters =
            deterministicFilters.isEmpty
            ? providerFilters
            : deterministicFilters
        let followUps = providerAnswer.followUpSuggestions.map { suggestion in
            GraphChatFollowUpSuggestion(
                title: suggestion.title,
                prompt: suggestion.prompt
            )
        }
        let localizer = GraphChatResponseLocalizer(language: language)
        let candidateState = await transaction.snapshot()
        let latestToolState = candidateState.resultContexts.last?.state

        switch providerAnswer.responseState {
        case .answer:
            if let proposal = providerAnswer.referenceProposal {
                let resolution = try await referenceResolver.resolve(
                    proposal,
                    in: context,
                    expectedGraphScope: context.graphScope,
                    expectedChatScope: context.chatScope
                )
                if case .resolved = resolution {
                    // The proposal was app-side validated. The normal answer may be returned.
                } else if missingContextPolicy.shouldIgnoreUnresolvedProviderProposal(
                    resolution,
                    directAnswer: providerAnswer.directAnswer
                ) {
                    // A non-binding missing-context proposal must not replace a usable answer.
                } else {
                    let fallback = localAnswerBuilder.referenceResolution(
                        resolution,
                        language: language,
                        operation: continuationOperation ?? .answerAboutReference,
                        state: candidateState,
                        sourceTurnID: candidateState.turnContexts.last?.id,
                        continuationQuestion: requestQuestion,
                        clarificationID: UUID(),
                        referenceDate: referenceDate()
                    )
                    if let pending = fallback.pendingClarification {
                        try await transaction.apply(
                            GraphChatConversationTrustedEvent(
                                graphScope: context.graphScope,
                                chatScope: context.chatScope,
                                payload: .clarificationRequested(pending)
                            )
                        )
                    }
                    return fallback.answer
                }
            }
            return GraphChatAnswer(
                state: .answer,
                directAnswer: providerAnswer.directAnswer,
                sections: sections,
                evidence: validatedEvidence,
                artifactIDs: artifacts.map(\.id),
                appliedFilters: filters,
                followUpSuggestions: followUps,
                hasInsufficientEvidence: providerAnswer.hasInsufficientEvidence
                    || validatedEvidence.isEmpty
            )
        case .noResults:
            guard latestToolState == .noResults else {
                return GraphChatAnswer(
                    state: .answer,
                    directAnswer: providerAnswer.directAnswer,
                    sections: sections,
                    evidence: validatedEvidence,
                    artifactIDs: artifacts.map(\.id),
                    appliedFilters: filters,
                    followUpSuggestions: followUps,
                    hasInsufficientEvidence: true
                )
            }
            let text =
                providerAnswer.directAnswer.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                ? localizer.noResults()
                : providerAnswer.directAnswer
            return GraphChatAnswer(
                state: .noResults,
                directAnswer: text,
                sections: sections,
                evidence: validatedEvidence,
                artifactIDs: artifacts.map(\.id),
                appliedFilters: filters,
                followUpSuggestions: followUps,
                hasInsufficientEvidence: true
            )
        case .unsupported:
            let capability = providerAnswer.unsupportedCapability ?? .other
            let text =
                providerAnswer.directAnswer.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
                ? localizer.unsupported(capability)
                : providerAnswer.directAnswer
            return GraphChatAnswer(
                state: .unsupported(capability),
                directAnswer: text,
                sections: [],
                evidence: [],
                appliedFilters: [],
                followUpSuggestions: [],
                hasInsufficientEvidence: false
            )
        case .clarification:
            let options = try await validatedClarificationOptions(
                providerAnswer: providerAnswer,
                context: context
            )
            let normalizedQuestion = providerAnswer.clarificationQuestion?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let question =
                normalizedQuestion?.isEmpty == false
                ? normalizedQuestion!
                : localizer.clarificationQuestion(reason: .ambiguous)
            let pending = localAnswerBuilder.makePendingClarification(
                id: UUID(),
                options: options,
                operation: continuationOperation ?? .answerAboutReference,
                state: candidateState,
                continuationQuestion: requestQuestion,
                referenceDate: referenceDate()
            )
            if let pending {
                try await transaction.apply(
                    GraphChatConversationTrustedEvent(
                        graphScope: context.graphScope,
                        chatScope: context.chatScope,
                        payload: .clarificationRequested(pending)
                    )
                )
            }
            return GraphChatAnswer(
                state: .clarification(
                    GraphChatClarification(
                        id: pending?.id ?? UUID(),
                        question: question,
                        options: options.map {
                            GraphChatClarificationOption(id: $0.id, title: $0.title)
                        }
                    )
                ),
                directAnswer: question,
                sections: [],
                evidence: [],
                appliedFilters: [],
                followUpSuggestions: [],
                hasInsufficientEvidence: true
            )
        }
    }

    private func validatedClarificationOptions(
        providerAnswer: GraphChatProviderFinalAnswer,
        context: GraphChatConversationContextSnapshot
    ) async throws -> [GraphChatPendingClarificationOption] {
        var options: [GraphChatPendingClarificationOption] = []
        var seen = Set<String>()

        for rawAlias in providerAnswer.clarificationOptionAliases.prefix(8) {
            guard let alias = context.alias(rawAlias) else {
                continue
            }
            let resolution = try await referenceResolver.resolve(
                .alias(alias.alias),
                in: context,
                expectedGraphScope: context.graphScope,
                expectedChatScope: context.chatScope
            )
            guard case .resolved = resolution, seen.insert(alias.alias).inserted else {
                continue
            }
            options.append(
                GraphChatPendingClarificationOption(
                    id: alias.alias,
                    title: alias.label,
                    proposal: .alias(alias.alias)
                )
            )
        }

        if options.isEmpty, let proposal = providerAnswer.referenceProposal {
            let resolution = try await referenceResolver.resolve(
                proposal,
                in: context,
                expectedGraphScope: context.graphScope,
                expectedChatScope: context.chatScope
            )
            if case .clarification(let clarification) = resolution {
                options = clarification.options
            }
        }
        return Array(options.prefix(8))
    }

    private func completeLocalAnswer(
        _ plan: GraphChatLocalTurnPlan,
        requestID: UUID,
        continuation: GraphChatEventStream.Continuation
    ) async throws {
        let transaction = GraphChatConversationStateTransaction(
            baseState: plan.baseState,
            reducer: conversationStateReducer
        )
        if let pendingClarification = plan.pendingClarification {
            try await transaction.apply(
                GraphChatConversationTrustedEvent(
                    graphScope: plan.baseState.graphScope,
                    chatScope: plan.baseState.chatScope,
                    payload: .clarificationRequested(pendingClarification)
                )
            )
        }
        let candidate = try await transaction.finalizedState(
            requestID: requestID,
            completedAt: referenceDate(),
            validatedEvidenceIDs: plan.answer.evidenceIDs
        )
        try Task.checkCancellation()
        guard conversationState == plan.expectedCommittedState else {
            throw CancellationError()
        }
        conversationState = candidate
        continuation.yield(.completed(plan.answer))
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

    private func validatedArtifactIDs(
        from rawValues: [String],
        artifactsByID: [GraphChatAnswerArtifactID: GraphChatAnswerArtifact]
    ) -> [GraphChatAnswerArtifactID] {
        var seen = Set<GraphChatAnswerArtifactID>()
        return rawValues.compactMap { rawValue in
            guard let uuid = UUID(uuidString: rawValue) else {
                return nil
            }
            let id = GraphChatAnswerArtifactID(rawValue: uuid)
            guard artifactsByID[id] != nil, seen.insert(id).inserted else {
                return nil
            }
            return id
        }
    }

    private func sectionAnswerState(
        for providerState: GraphChatProviderResponseState
    ) -> GraphChatAnswerState {
        switch providerState {
        case .answer:
            return .answer
        case .noResults:
            return .noResults
        case .unsupported:
            return .unsupported(.other)
        case .clarification:
            return .answer
        }
    }

    private func mapError(_ error: Error) -> GraphChatError {
        errorMapper.map(error)
    }
}
