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
    private struct ScopeKey: Hashable, Sendable {
        let graphScope: GraphScope
        let chatScope: GraphChatScope
    }

    private struct ArtifactSessionResources {
        let key: ScopeKey
        let sessionID: GraphChatAnswerArtifactSessionID
        let registry: GraphChatAnswerArtifactRegistry
    }

    private struct SessionResources {
        let key: ScopeKey
        let sessionID: GraphChatModelSessionID
        let schemaContext: GraphSchemaContext
        let budget: GraphChatToolBudget
        let evidenceRegistry: GraphChatEvidenceRegistry
        let artifactRegistry: GraphChatAnswerArtifactRegistry
        let artifactSessionID: GraphChatAnswerArtifactSessionID
        let artifactTransactionID: GraphChatAnswerArtifactTransactionID
        let conversationBaseState: GraphChatConversationState
        let conversationContext: GraphChatConversationContextSnapshot
        let responseLanguage: GraphChatResponseLanguage
        let conversationTransaction: GraphChatConversationStateTransaction
        let toolRunner: any GraphChatModelToolRunning
    }

    private struct ActiveGeneration {
        let requestID: UUID
        let task: Task<Void, Never>
        var sessionID: GraphChatModelSessionID?
        var evidenceRegistry: GraphChatEvidenceRegistry?
        var artifactRegistry: GraphChatAnswerArtifactRegistry?
        var artifactTransactionID: GraphChatAnswerArtifactTransactionID?
    }

    private let provider: any GraphChatModelProvider
    private let schemaProvider: any GraphSchemaSnapshotProviding
    private let toolRunnerFactory: any GraphChatModelToolRunnerFactory
    private let toolBudgetPolicy: GraphChatToolBudgetPolicy
    private let concurrentRequestPolicy: GraphChatConcurrentRequestPolicy
    private let conversationStateReducer: GraphChatConversationStateReducer
    private let conversationContextBuilder: GraphChatConversationContextBuilder
    private let referenceResolver: GraphChatConversationReferenceResolver
    private let referenceInterpreter: GraphChatConversationReferenceInterpreter
    private let unsupportedRequestDetector: GraphChatUnsupportedRequestDetector
    private let responseLanguageSelector: GraphChatResponseLanguageSelector
    private let artifactRevalidator: any GraphChatAnswerArtifactRevalidating
    private let evidenceValidator: any GraphEvidenceValidating
    private let referenceDate: @Sendable () -> Date
    private let calendar: Calendar
    private let timeZone: TimeZone

    private var preparedSession: SessionResources?
    private var artifactSession: ArtifactSessionResources?
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
        self.provider = provider
        self.schemaProvider = schemaProvider
        self.toolRunnerFactory = toolRunnerFactory
        self.toolBudgetPolicy = toolBudgetPolicy
        self.concurrentRequestPolicy = concurrentRequestPolicy
        self.conversationStateReducer = GraphChatConversationStateReducer(
            policy: conversationStatePolicy
        )
        self.conversationContextBuilder = GraphChatConversationContextBuilder(
            budget: conversationContextBudget
        )
        self.referenceResolver = referenceResolver
        self.referenceInterpreter = GraphChatConversationReferenceInterpreter()
        self.unsupportedRequestDetector = GraphChatUnsupportedRequestDetector()
        self.responseLanguageSelector = responseLanguageSelector
        self.artifactRevalidator = artifactRevalidator
        self.evidenceValidator = evidenceValidator
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.timeZone = timeZone
    }

    func prepare(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async throws {
        let key = try validatedKey(graphScope: graphScope, chatScope: chatScope)
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
            try await provider.prewarm(
                sessionID: resources.sessionID,
                promptPrefix: preparationLanguage == .german
                    ? "Es folgt eine read-only Frage zum aktiven Graphen."
                    : "A read-only question about the active graph will follow."
            )
            preparedSession = resources
        } catch {
            await resources.artifactRegistry.rollback(
                transactionID: resources.artifactTransactionID
            )
            await provider.discardSession(sessionID: resources.sessionID)
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
            let key = try validatedKey(graphScope: graphScope, chatScope: chatScope)
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
                sessionID: nil,
                evidenceRegistry: nil,
                artifactRegistry: nil,
                artifactTransactionID: nil
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
        let evidenceRegistry = activeGeneration.evidenceRegistry
        let artifactRegistry = activeGeneration.artifactRegistry
        let artifactTransactionID = activeGeneration.artifactTransactionID
        activeGeneration.task.cancel()
        if let sessionID = activeGeneration.sessionID {
            await provider.cancelGeneration(sessionID: sessionID)
        }
        await activeGeneration.task.value
        await evidenceRegistry?.removeAll()
        if let artifactRegistry, let artifactTransactionID {
            await artifactRegistry.rollback(transactionID: artifactTransactionID)
        }
    }

    func discardSession() async {
        await discardSession(reason: .sessionDiscarded)
    }

    func discardSession(
        reason: GraphChatConversationResetReason
    ) async {
        await cancelCurrentGeneration()
        if let preparedSession {
            await preparedSession.evidenceRegistry.removeAll()
            await preparedSession.artifactRegistry.rollback(
                transactionID: preparedSession.artifactTransactionID
            )
            await provider.discardSession(sessionID: preparedSession.sessionID)
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

        let expectedKey = ScopeKey(
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
        let key = try validatedKey(
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
            await preparedSession.evidenceRegistry.removeAll()
            await preparedSession.artifactRegistry.rollback(
                transactionID: preparedSession.artifactTransactionID
            )
            await provider.discardSession(sessionID: preparedSession.sessionID)
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
        key: ScopeKey,
        turnStateSnapshot: GraphChatConversationState,
        continuation: GraphChatEventStream.Continuation
    ) async {
        continuation.yield(.started(requestID: requestID))
        var artifactCommitContext: (
            registry: GraphChatAnswerArtifactRegistry,
            transactionID: GraphChatAnswerArtifactTransactionID
        )?
        defer {
            continuation.finish()
            clearActiveGeneration(requestID: requestID)
        }

        do {
            let normalizedQuestion = try validateQuestion(question)
            let language = responseLanguageSelector.language(for: normalizedQuestion)
            let localizer = GraphChatResponseLocalizer(language: language)

            if turnStateSnapshot.pendingClarification == nil,
                let unsupportedCapability = unsupportedRequestDetector.capability(
                    for: normalizedQuestion
                )
            {
                let answer = GraphChatAnswer(
                    state: .unsupported(unsupportedCapability),
                    directAnswer: localizer.unsupported(unsupportedCapability),
                    hasInsufficientEvidence: false
                )
                try await completeLocalAnswer(
                    answer,
                    requestID: requestID,
                    baseState: turnStateSnapshot,
                    expectedCommittedState: turnStateSnapshot,
                    pendingClarification: nil,
                    continuation: continuation
                )
                return
            }

            var requestBaseState = turnStateSnapshot
            var currentReference: GraphChatResolvedConversationReference?
            var continuationOperation: GraphChatConversationContinuationOperation?
            var providerQuestion = normalizedQuestion
            var context = conversationContextBuilder.makeSnapshot(
                from: requestBaseState.snapshot
            )

            if let pending = requestBaseState.pendingClarification {
                guard
                    pending.isValid(
                        at: referenceDate(),
                        graphScope: key.graphScope,
                        chatScope: key.chatScope
                    )
                else {
                    requestBaseState = try clearedClarification(in: requestBaseState)
                    context = conversationContextBuilder.makeSnapshot(
                        from: requestBaseState.snapshot
                    )
                    let answer = GraphChatAnswer(
                        state: .clarification(
                            GraphChatClarification(
                                id: UUID(),
                                question: localizer.clarificationQuestion(reason: .staleResults),
                                options: []
                            )
                        ),
                        directAnswer: localizer.clarificationQuestion(reason: .staleResults),
                        hasInsufficientEvidence: true
                    )
                    try await completeLocalAnswer(
                        answer,
                        requestID: requestID,
                        baseState: requestBaseState,
                        expectedCommittedState: turnStateSnapshot,
                        pendingClarification: nil,
                        continuation: continuation
                    )
                    return
                }

                guard
                    let selectedOption = referenceInterpreter.clarificationSelection(
                        for: normalizedQuestion,
                        pending: pending
                    )
                else {
                    let answer = clarificationAnswer(
                        pending: pending,
                        question: localizer.clarificationQuestion(reason: .ambiguous)
                    )
                    try await completeLocalAnswer(
                        answer,
                        requestID: requestID,
                        baseState: requestBaseState,
                        expectedCommittedState: turnStateSnapshot,
                        pendingClarification: nil,
                        continuation: continuation
                    )
                    return
                }

                let resolution = try await referenceResolver.resolve(
                    selectedOption.proposal,
                    in: context,
                    expectedGraphScope: key.graphScope,
                    expectedChatScope: key.chatScope
                )
                requestBaseState = try clearedClarification(in: requestBaseState)
                guard case .resolved(let resolved) = resolution else {
                    let answer = answer(
                        for: resolution,
                        language: language,
                        operation: pending.continuationOperation,
                        state: requestBaseState,
                        sourceTurnID: pending.sourceTurnID,
                        continuationQuestion: pending.continuationQuestion
                    )
                    try await completeLocalAnswer(
                        answer.value,
                        requestID: requestID,
                        baseState: requestBaseState,
                        expectedCommittedState: turnStateSnapshot,
                        pendingClarification: answer.pending,
                        continuation: continuation
                    )
                    return
                }
                currentReference = resolved
                continuationOperation = pending.continuationOperation
                providerQuestion = pending.continuationQuestion
            } else if let interpretation = referenceInterpreter.interpretation(
                for: normalizedQuestion
            ) {
                let resolution = try await referenceResolver.resolve(
                    interpretation.proposal,
                    in: context,
                    expectedGraphScope: key.graphScope,
                    expectedChatScope: key.chatScope
                )
                switch resolution {
                case .resolved(let resolved):
                    currentReference = resolved
                    continuationOperation = interpretation.operation
                case .clarification, .noResults, .rejected:
                    let answer = answer(
                        for: resolution,
                        language: language,
                        operation: interpretation.operation,
                        state: requestBaseState,
                        sourceTurnID: requestBaseState.turnContexts.last?.id,
                        continuationQuestion: normalizedQuestion
                    )
                    try await completeLocalAnswer(
                        answer.value,
                        requestID: requestID,
                        baseState: requestBaseState,
                        expectedCommittedState: turnStateSnapshot,
                        pendingClarification: answer.pending,
                        continuation: continuation
                    )
                    return
                }
            }

            context = conversationContextBuilder.makeSnapshot(
                from: requestBaseState.snapshot,
                currentReference: currentReference
            )
            let initialResources = try await takeOrCreateSessionResources(
                for: key,
                conversationBaseState: requestBaseState,
                conversationContext: context,
                responseLanguage: language
            )
            artifactCommitContext = (
                registry: initialResources.artifactRegistry,
                transactionID: initialResources.artifactTransactionID
            )
            setActiveResources(initialResources, requestID: requestID)
            var answer = try await generateWithSingleContextRetry(
                resources: initialResources,
                question: providerQuestion,
                conversationContext: context,
                responseLanguage: language,
                continuationOperation: continuationOperation,
                requestID: requestID,
                continuation: continuation
            )
            try Task.checkCancellation()
            let candidateState = try await initialResources.conversationTransaction.finalizedState(
                requestID: requestID,
                completedAt: referenceDate(),
                validatedEvidenceIDs: answer.evidenceIDs
            )
            try Task.checkCancellation()
            guard conversationState == turnStateSnapshot else {
                throw CancellationError()
            }
            let committedArtifactIDs = try await initialResources.artifactRegistry.commit(
                transactionID: initialResources.artifactTransactionID,
                retaining: answer.artifactIDs
            )
            answer = answer.retainingArtifactIDs(Set(committedArtifactIDs))
            artifactCommitContext = nil
            conversationState = candidateState
            continuation.yield(.completed(answer))
        } catch is CancellationError {
            await rollbackArtifactContext(artifactCommitContext)
            continuation.yield(.cancelled)
        } catch let error as GraphChatProviderError where error.code == .cancelled {
            await rollbackArtifactContext(artifactCommitContext)
            continuation.yield(.cancelled)
        } catch let error as GraphChatToolError where error.code == .cancelled {
            await rollbackArtifactContext(artifactCommitContext)
            continuation.yield(.cancelled)
        } catch {
            await rollbackArtifactContext(artifactCommitContext)
            continuation.yield(.failure(mapError(error)))
        }
    }

    private func generateWithSingleContextRetry(
        resources initialResources: SessionResources,
        question: String,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage,
        continuationOperation: GraphChatConversationContinuationOperation?,
        requestID: UUID,
        continuation: GraphChatEventStream.Continuation
    ) async throws -> GraphChatAnswer {
        var resources = initialResources
        var retryCount = 0

        while true {
            do {
                let context =
                    retryCount == 0
                    ? conversationContext
                    : compactRetryContext(conversationContext)
                let answer = try await consumeProviderStream(
                    resources: resources,
                    question: question,
                    conversationContext: context,
                    responseLanguage: responseLanguage,
                    continuationOperation: continuationOperation,
                    continuation: continuation
                )
                await resources.evidenceRegistry.removeAll()
                await provider.discardSession(sessionID: resources.sessionID)
                return answer
            } catch let error as GraphChatProviderError
                where error.code == .contextWindowExceeded && retryCount == 0
            {
                await resources.evidenceRegistry.removeAll()
                await resources.artifactRegistry.rollback(
                    transactionID: resources.artifactTransactionID
                )
                await provider.discardSession(sessionID: resources.sessionID)
                await resources.conversationTransaction.resetToBase()
                retryCount += 1
                resources = try await replaceSession(in: resources)
                setActiveResources(resources, requestID: requestID)
            } catch {
                if Task.isCancelled {
                    await provider.cancelGeneration(sessionID: resources.sessionID)
                }
                await resources.evidenceRegistry.removeAll()
                await resources.artifactRegistry.rollback(
                    transactionID: resources.artifactTransactionID
                )
                await provider.discardSession(sessionID: resources.sessionID)
                throw error
            }
        }
    }

    private func consumeProviderStream(
        resources: SessionResources,
        question: String,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage,
        continuationOperation: GraphChatConversationContinuationOperation?,
        continuation: GraphChatEventStream.Continuation
    ) async throws -> GraphChatAnswer {
        let request = GraphChatModelRequest(
            question: question,
            schemaPrompt: schemaPrompt(
                from: resources.schemaContext,
                chatScope: resources.key.chatScope,
                language: responseLanguage
            ),
            conversationContext: conversationContext,
            responseLanguage: responseLanguage,
            continuationOperation: continuationOperation
        )
        let providerStream = try await provider.streamResponse(
            sessionID: resources.sessionID,
            request: request
        )
        var finalAnswer: GraphChatProviderFinalAnswer?

        do {
            for try await event in providerStream {
                try Task.checkCancellation()
                switch event {
                case .toolActivity(let activity):
                    continuation.yield(.toolActivity(activity))
                case .partialAnswer(let partial):
                    let text = partial.directAnswer.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    if text.isEmpty == false {
                        continuation.yield(.partialAnswer(text))
                    }
                case .completed(let answer):
                    finalAnswer = answer
                }
            }
        } catch {
            if Task.isCancelled {
                await provider.cancelGeneration(sessionID: resources.sessionID)
                throw CancellationError()
            }
            throw error
        }

        try Task.checkCancellation()
        guard let finalAnswer else {
            throw GraphChatProviderError(
                code: .unexpected,
                message: "Das Modell hat keine vollständige strukturierte Antwort geliefert."
            )
        }
        return try await validatedAnswer(
            from: finalAnswer,
            registry: resources.evidenceRegistry,
            artifactRegistry: resources.artifactRegistry,
            artifactSessionID: resources.artifactSessionID,
            artifactTransactionID: resources.artifactTransactionID,
            transaction: resources.conversationTransaction,
            context: conversationContext,
            language: responseLanguage,
            continuationOperation: continuationOperation,
            requestQuestion: question
        )
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
                } else {
                    let fallback = answer(
                        for: resolution,
                        language: language,
                        operation: continuationOperation ?? .answerAboutReference,
                        state: candidateState,
                        sourceTurnID: candidateState.turnContexts.last?.id,
                        continuationQuestion: requestQuestion
                    )
                    if let pending = fallback.pending {
                        try await transaction.apply(
                            GraphChatConversationTrustedEvent(
                                graphScope: context.graphScope,
                                chatScope: context.chatScope,
                                payload: .clarificationRequested(pending)
                            )
                        )
                    }
                    return fallback.value
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
            let pending = makePendingClarification(
                options: options,
                operation: continuationOperation ?? .answerAboutReference,
                state: candidateState,
                continuationQuestion: requestQuestion
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
        _ answer: GraphChatAnswer,
        requestID: UUID,
        baseState: GraphChatConversationState,
        expectedCommittedState: GraphChatConversationState,
        pendingClarification: GraphChatPendingClarification?,
        continuation: GraphChatEventStream.Continuation
    ) async throws {
        let transaction = GraphChatConversationStateTransaction(
            baseState: baseState,
            reducer: conversationStateReducer
        )
        if let pendingClarification {
            try await transaction.apply(
                GraphChatConversationTrustedEvent(
                    graphScope: baseState.graphScope,
                    chatScope: baseState.chatScope,
                    payload: .clarificationRequested(pendingClarification)
                )
            )
        }
        let candidate = try await transaction.finalizedState(
            requestID: requestID,
            completedAt: referenceDate(),
            validatedEvidenceIDs: answer.evidenceIDs
        )
        try Task.checkCancellation()
        guard conversationState == expectedCommittedState else {
            throw CancellationError()
        }
        conversationState = candidate
        continuation.yield(.completed(answer))
    }

    private func answer(
        for resolution: GraphChatConversationReferenceResolution,
        language: GraphChatResponseLanguage,
        operation: GraphChatConversationContinuationOperation,
        state: GraphChatConversationState,
        sourceTurnID: UUID?,
        continuationQuestion: String
    ) -> (value: GraphChatAnswer, pending: GraphChatPendingClarification?) {
        let localizer = GraphChatResponseLocalizer(language: language)
        switch resolution {
        case .resolved:
            return (
                GraphChatAnswer(
                    state: .answer,
                    directAnswer: "",
                    hasInsufficientEvidence: false
                ),
                nil
            )
        case .noResults(let issue):
            let text =
                issue == .emptyResults
                ? localizer.noResults()
                : localizer.clarificationQuestion(reason: issue)
            return (
                GraphChatAnswer(
                    state: .noResults,
                    directAnswer: text,
                    hasInsufficientEvidence: true
                ),
                nil
            )
        case .rejected(let issue):
            let question = localizer.clarificationQuestion(reason: issue)
            return (
                GraphChatAnswer(
                    state: .clarification(
                        GraphChatClarification(
                            id: UUID(),
                            question: question,
                            options: []
                        )
                    ),
                    directAnswer: question,
                    hasInsufficientEvidence: true
                ),
                nil
            )
        case .clarification(let clarification):
            let question = localizer.clarificationQuestion(reason: clarification.issue)
            let pending = makePendingClarification(
                options: clarification.options,
                operation: operation,
                state: state,
                sourceTurnID: sourceTurnID,
                continuationQuestion: continuationQuestion
            )
            return (
                GraphChatAnswer(
                    state: .clarification(
                        GraphChatClarification(
                            id: pending?.id ?? UUID(),
                            question: question,
                            options: clarification.options.map {
                                GraphChatClarificationOption(id: $0.id, title: $0.title)
                            }
                        )
                    ),
                    directAnswer: question,
                    hasInsufficientEvidence: true
                ),
                pending
            )
        }
    }

    private func clarificationAnswer(
        pending: GraphChatPendingClarification,
        question: String
    ) -> GraphChatAnswer {
        GraphChatAnswer(
            state: .clarification(
                GraphChatClarification(
                    id: pending.id,
                    question: question,
                    options: pending.options.map {
                        GraphChatClarificationOption(id: $0.id, title: $0.title)
                    }
                )
            ),
            directAnswer: question,
            hasInsufficientEvidence: true
        )
    }

    private func makePendingClarification(
        options: [GraphChatPendingClarificationOption],
        operation: GraphChatConversationContinuationOperation,
        state: GraphChatConversationState,
        sourceTurnID: UUID? = nil,
        continuationQuestion: String
    ) -> GraphChatPendingClarification? {
        guard options.isEmpty == false else {
            return nil
        }
        let now = referenceDate()
        return GraphChatPendingClarification(
            id: UUID(),
            decision: .conversationReference,
            options: Array(options.prefix(8)),
            sourceTurnID: sourceTurnID ?? state.turnContexts.last?.id,
            graphScope: state.graphScope,
            chatScope: state.chatScope,
            continuationOperation: operation,
            continuationQuestion: bounded(continuationQuestion, limit: 500),
            createdAt: now,
            expiresAt: now.addingTimeInterval(10 * 60)
        )
    }

    private func clearedClarification(
        in state: GraphChatConversationState
    ) throws -> GraphChatConversationState {
        try conversationStateReducer.reduce(
            state,
            event: GraphChatConversationTrustedEvent(
                graphScope: state.graphScope,
                chatScope: state.chatScope,
                payload: .clarificationResolved
            )
        ).state
    }

    private func compactRetryContext(
        _ context: GraphChatConversationContextSnapshot
    ) -> GraphChatConversationContextSnapshot {
        GraphChatConversationContextSnapshot(
            conversationID: context.conversationID,
            graphScope: context.graphScope,
            chatScope: context.chatScope,
            aliases: context.aliases,
            results: Array(context.results.suffix(1)),
            turns: [],
            latestResultAlias: context.latestResultAlias,
            lastEntityAlias: context.lastEntityAlias,
            lastFieldAlias: context.lastFieldAlias,
            lastGroupAlias: context.lastGroupAlias,
            lastNodeAlias: context.lastNodeAlias,
            lastComparisonAlias: context.lastComparisonAlias,
            currentReferenceAlias: context.currentReferenceAlias,
            lastValidatedQuery: context.lastValidatedQuery,
            resultRevalidations: context.resultRevalidations,
            pendingClarificationID: context.pendingClarificationID
        )
    }

    private func takeOrCreateSessionResources(
        for key: ScopeKey,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage
    ) async throws -> SessionResources {
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
            await preparedSession.evidenceRegistry.removeAll()
            await preparedSession.artifactRegistry.rollback(
                transactionID: preparedSession.artifactTransactionID
            )
            await provider.discardSession(sessionID: preparedSession.sessionID)
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
        for key: ScopeKey,
        conversationBaseState: GraphChatConversationState,
        conversationContext: GraphChatConversationContextSnapshot,
        responseLanguage: GraphChatResponseLanguage
    ) async throws -> SessionResources {
        let availability = await provider.availability()
        guard availability.isAvailable else {
            throw availabilityError(availability)
        }

        let schemaContext: GraphSchemaContext
        do {
            schemaContext = try await schemaProvider.makeSnapshot(
                in: key.graphScope,
                exampleFieldIDs: []
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Das Schema des aktiven Graphen konnte nicht geladen werden.",
                recoverySuggestion: "Öffne den Graphen erneut und versuche es noch einmal."
            )
        }
        guard schemaContext.graphScope == key.graphScope else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Das geladene Schema gehört nicht zum aktiven Graphen."
            )
        }

        let budget = GraphChatToolBudget(policy: toolBudgetPolicy)
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: key.chatScope)
        let artifactResources = await artifactSessionResources(for: key)
        let artifactTransactionID = GraphChatAnswerArtifactTransactionID()
        let conversationTransaction = GraphChatConversationStateTransaction(
            baseState: conversationBaseState,
            reducer: conversationStateReducer
        )
        let toolRunner = toolRunnerFactory.makeRunner(
            scope: key.chatScope,
            schemaContext: schemaContext,
            budget: budget,
            evidenceRegistry: evidenceRegistry,
            artifactRegistry: artifactResources.registry,
            artifactTransactionID: artifactTransactionID,
            conversationTransaction: conversationTransaction,
            conversationContext: conversationContext,
            referenceResolver: referenceResolver,
            responseLanguage: responseLanguage,
            referenceDate: referenceDate(),
            calendar: calendar,
            timeZone: timeZone
        )
        let registeredKinds = await toolRunner.registeredToolKinds()
        guard registeredKinds == Set(GraphChatToolKind.allCases) else {
            throw GraphChatError(
                code: .invalidRequest,
                message:
                    "Für den Graph-Chat sind nicht exakt die kontrollierten read-only Tools registriert."
            )
        }

        let configuration = GraphChatModelSessionConfiguration(
            graphScope: key.graphScope,
            chatScope: key.chatScope,
            schemaContext: schemaContext,
            instructions: systemInstructions(
                for: key.chatScope,
                language: responseLanguage
            ),
            toolRunner: toolRunner
        )
        do {
            let sessionID = try await provider.createSession(configuration: configuration)
            return SessionResources(
                key: key,
                sessionID: sessionID,
                schemaContext: schemaContext,
                budget: budget,
                evidenceRegistry: evidenceRegistry,
                artifactRegistry: artifactResources.registry,
                artifactSessionID: artifactResources.sessionID,
                artifactTransactionID: artifactTransactionID,
                conversationBaseState: conversationBaseState,
                conversationContext: conversationContext,
                responseLanguage: responseLanguage,
                conversationTransaction: conversationTransaction,
                toolRunner: toolRunner
            )
        } catch {
            await artifactResources.registry.rollback(
                transactionID: artifactTransactionID
            )
            throw mapError(error)
        }
    }

    private func replaceSession(
        in resources: SessionResources
    ) async throws -> SessionResources {
        let configuration = GraphChatModelSessionConfiguration(
            graphScope: resources.key.graphScope,
            chatScope: resources.key.chatScope,
            schemaContext: resources.schemaContext,
            instructions: systemInstructions(
                for: resources.key.chatScope,
                language: resources.responseLanguage
            ),
            toolRunner: resources.toolRunner
        )
        let sessionID = try await provider.createSession(configuration: configuration)
        return SessionResources(
            key: resources.key,
            sessionID: sessionID,
            schemaContext: resources.schemaContext,
            budget: resources.budget,
            evidenceRegistry: resources.evidenceRegistry,
            artifactRegistry: resources.artifactRegistry,
            artifactSessionID: resources.artifactSessionID,
            artifactTransactionID: resources.artifactTransactionID,
            conversationBaseState: resources.conversationBaseState,
            conversationContext: resources.conversationContext,
            responseLanguage: resources.responseLanguage,
            conversationTransaction: resources.conversationTransaction,
            toolRunner: resources.toolRunner
        )
    }

    private func cancelActiveGenerationForNewRequest() async throws {
        guard let activeGeneration else {
            return
        }
        switch concurrentRequestPolicy {
        case .cancelPrevious:
            let evidenceRegistry = activeGeneration.evidenceRegistry
            let artifactRegistry = activeGeneration.artifactRegistry
            let artifactTransactionID = activeGeneration.artifactTransactionID
            activeGeneration.task.cancel()
            if let sessionID = activeGeneration.sessionID {
                await provider.cancelGeneration(sessionID: sessionID)
            }
            await activeGeneration.task.value
            await evidenceRegistry?.removeAll()
            if let artifactRegistry, let artifactTransactionID {
                await artifactRegistry.rollback(transactionID: artifactTransactionID)
            }
        }
    }

    private func cancel(requestID: UUID) async {
        guard let activeGeneration, activeGeneration.requestID == requestID else {
            return
        }
        activeGeneration.task.cancel()
        if let sessionID = activeGeneration.sessionID {
            await provider.cancelGeneration(sessionID: sessionID)
        }
    }

    private func setActiveResources(
        _ resources: SessionResources,
        requestID: UUID
    ) {
        guard var activeGeneration, activeGeneration.requestID == requestID else {
            return
        }
        activeGeneration.sessionID = resources.sessionID
        activeGeneration.evidenceRegistry = resources.evidenceRegistry
        activeGeneration.artifactRegistry = resources.artifactRegistry
        activeGeneration.artifactTransactionID = resources.artifactTransactionID
        self.activeGeneration = activeGeneration
    }

    private func clearActiveGeneration(requestID: UUID) {
        guard activeGeneration?.requestID == requestID else {
            return
        }
        activeGeneration = nil
    }

    private func discardPreparedSession(
        unlessMatching key: ScopeKey,
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
        await preparedSession.evidenceRegistry.removeAll()
        await preparedSession.artifactRegistry.rollback(
            transactionID: preparedSession.artifactTransactionID
        )
        await provider.discardSession(sessionID: preparedSession.sessionID)
        self.preparedSession = nil
    }

    private func artifactSessionResources(
        for key: ScopeKey
    ) async -> ArtifactSessionResources {
        if let artifactSession, artifactSession.key == key {
            return artifactSession
        }
        if let artifactSession {
            await artifactSession.registry.removeAll(reason: .scopeChanged)
        }
        let sessionID = GraphChatAnswerArtifactSessionID()
        let resources = ArtifactSessionResources(
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

    private func rollbackArtifactContext(
        _ context: (
            registry: GraphChatAnswerArtifactRegistry,
            transactionID: GraphChatAnswerArtifactTransactionID
        )?
    ) async {
        guard let context else {
            return
        }
        await context.registry.rollback(transactionID: context.transactionID)
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

    private func validatedKey(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) throws -> ScopeKey {
        guard graphScope == chatScope.graphScope else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Der Chat-Scope gehört nicht zum aktiven Graphen."
            )
        }
        return ScopeKey(graphScope: graphScope, chatScope: chatScope)
    }

    private func validateQuestion(_ question: String) throws -> String {
        let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Die Graph-Chat-Frage darf nicht leer sein."
            )
        }
        return String(normalized.prefix(4_000))
    }

    private func conversationStateForTurn(
        for key: ScopeKey
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

    private func schemaPrompt(
        from context: GraphSchemaContext,
        chatScope: GraphChatScope,
        language: GraphChatResponseLanguage
    ) -> String {
        var lines: [String]
        switch language {
        case .german:
            lines = [
                "Graph: \(context.snapshot.graphName)",
                "Schema-Version: \(context.snapshot.version)",
                "Aktiver Scope: \(scopeDescription(chatScope.target, language: language))",
            ]
        case .english:
            lines = [
                "Graph: \(context.snapshot.graphName)",
                "Schema version: \(context.snapshot.version)",
                "Active scope: \(scopeDescription(chatScope.target, language: language))",
            ]
        }
        for entity in context.snapshot.entities {
            lines.append("\(entity.alias.rawValue): \(entity.name)")
            for field in entity.fields {
                var details = "  \(field.alias.rawValue): \(field.name) [\(field.type.rawValue)]"
                if let unit = field.unit, unit.isEmpty == false {
                    details += " unit=\(unit)"
                }
                if field.choiceOptions.isEmpty == false {
                    details += " choices=\(field.choiceOptions.joined(separator: ", "))"
                }
                lines.append(details)
            }
        }
        if context.snapshot.truncation.isTruncated {
            switch language {
            case .german:
                lines.append(
                    "Der Schema-Snapshot ist absichtlich begrenzt; nutze describeGraphSchema für weiteren kontrollierten Kontext."
                )
            case .english:
                lines.append(
                    "The schema snapshot is intentionally truncated; use describeGraphSchema for more bounded context."
                )
            }
        }
        return bounded(lines.joined(separator: "\n"), limit: 10_000)
    }

    private func scopeDescription(
        _ target: GraphChatScopeTarget,
        language: GraphChatResponseLanguage
    ) -> String {
        switch (language, target) {
        case (.german, .graph):
            return "gesamter Graph"
        case (.english, .graph):
            return "entire graph"
        case (.german, .entity):
            return "einzelne Entity"
        case (.english, .entity):
            return "single entity"
        case (.german, .node):
            return "einzelner Node"
        case (.english, .node):
            return "single node"
        case (.german, .selection(let nodes)):
            return "Auswahl aus \(nodes.count) Nodes"
        case (.english, .selection(let nodes)):
            return "selection of \(nodes.count) nodes"
        }
    }

    private func systemInstructions(
        for scope: GraphChatScope,
        language: GraphChatResponseLanguage
    ) -> String {
        switch language {
        case .german:
            return """
                \(GraphChatResponseLocalizer(language: language).providerInstruction())
                Beantworte Fragen ausschließlich zum aktiven BrainMesh-Graphen über die registrierten read-only Tools.
                Verwende nur Fakten, die Tools in dieser Session geliefert haben. Ergänze niemals Graph-Fakten aus Weltwissen oder Annahmen.
                Benenne unbekannte, fehlende, mehrdeutige oder unzureichende Daten ausdrücklich.
                Verwende nur Evidence-UUIDs aus tatsächlichen Tool-Ergebnissen. Erfinde, verändere oder leite niemals eine Evidence-UUID ab.
                Übernimm nur artifactID-UUIDs, die ein Tool in dieser Anfrage ausdrücklich geliefert hat, unverändert in artifactIDs. Ordne eine Artifact-ID dem passenden Abschnitt zu, wenn der Abschnitt dieses Ergebnis einordnet. Erfinde keine Artifact-ID und erzeuge, verändere oder rekonstruiere niemals Artifact-Payloads.
                Tabellen, Rankings, Gruppen, Kennzahlen, Timelines und Ergebniszeilen stammen ausschließlich aus Artifacts. Wiederhole bei vorhandenem Artifact nicht sämtliche Zeilen im Fließtext und erfinde keine strukturierten Werte.
                Arbeite ausschließlich im aktiven Graphen und aktiven Chat-Scope. Fordere oder behaupte niemals Daten aus einem anderen Graphen oder Scope.
                Biete keine Schreib-, Änderungs-, Lösch-, Erstellungs-, Import-, Upload- oder Mutationsaktion an und simuliere oder behaupte sie nicht.
                Attachment-Tools liefern nur Metadaten. Behaupte niemals, Inhalte von Dateien, Bildern, PDFs oder Binärdaten gelesen zu haben.
                Tool-Aliase sind opak. Nutze ausschließlich E-, F-, N-, CURRENT-, CI-, CR-, CG-, CE-, CF- und CN-Aliase aus Schema, vertrauenswürdigem Konversations-Snapshot oder Tool-Ergebnissen.
                Konversationsreferenzen sind nur Vorschläge. Jeder Alias wird von der App aufgelöst und revalidiert, bevor ein Tool oder eine Query Daten nutzen darf.
                Nutze queryDetailValues.conversationReferenceAlias für Filter, Gruppierung, Statistik, Sortierung oder Limits über eine validierte frühere Ergebnismenge.
                Gib bei einer mehrdeutigen Referenz responseKind clarification und nur Aliase aus dem vertrauenswürdigen Snapshot als clarificationOptionAliases zurück.
                Gib responseKind noResults nur zurück, nachdem ein gültiger Tool-Aufruf noResults gemeldet hat. Gib unsupported für Graph-Mutationen, Attachment-Inhalte, Multi-Hop-Pfade oder Query-Plan-v2-Funktionen zurück.
                Behandle Tool-Fehler und leere Ergebnisse als Evidence-Grenzen und niemals als Erlaubnis zu raten.
                Halte die direkte Antwort knapp. Setze hasInsufficientEvidence auf true, wenn verlässliche Tool-Evidence fehlt.
                Führe für interpretative Begriffe wie wichtig, dringend, relevant oder offen die konkret verwendeten Filter auf.
                Folgefragen dürfen nur optionale read-only Fragen zum selben aktiven Scope sein.
                Aktiver Scope: \(scopeDescription(scope.target, language: language)).
                """
        case .english:
            return """
                \(GraphChatResponseLocalizer(language: language).providerInstruction())
                Answer questions only about the active BrainMesh graph through the registered read-only tools.
                Use only facts returned by tools in this session. Never add graph facts from world knowledge or assumptions.
                State unknown, missing, ambiguous, or insufficient data explicitly.
                Use only Evidence UUIDs that appeared in actual tool results. Never invent, alter, or infer an Evidence UUID.
                Copy only artifactID UUIDs explicitly returned by a tool in this request, unchanged, into artifactIDs. Associate an Artifact ID with the section that interprets that result when applicable. Never invent an Artifact ID or create, modify, or reconstruct an Artifact payload.
                Tables, rankings, groups, metrics, timelines, and result rows come only from Artifacts. When an Artifact exists, do not repeat every row in prose and never invent structured values.
                Work only inside the active graph and the active chat scope. Never request or claim data from another graph or scope.
                Never offer, simulate, or claim a write, edit, delete, create, import, upload, or mutation action.
                Attachment tools expose metadata only. Never claim to have read attachment contents, files, images, PDFs, or binary data.
                Tool aliases are opaque. Use only E, F, N, CURRENT, CI, CR, CG, CE, CF, and CN aliases supplied by the schema, trusted conversation snapshot, or tool results.
                Conversation references are proposals only. Every alias is resolved and revalidated by the app before a tool or query can access data.
                Use queryDetailValues.conversationReferenceAlias for filters, grouping, statistics, sorting, or limits over a validated previous result set.
                When a reference is ambiguous, return responseKind clarification and only aliases from the trusted snapshot as clarificationOptionAliases.
                Return responseKind noResults only after a valid tool call reports noResults. Return unsupported for graph mutations, attachment contents, multi-hop paths, or Query Plan v2 features.
                Treat tool errors and empty results as evidence limitations, not as permission to guess.
                Keep the direct answer concise. Mark hasInsufficientEvidence true whenever reliable tool evidence is missing.
                For interpretive terms such as important, urgent, relevant, open, or similar concepts, include the concrete applied filters used for the interpretation.
                Follow-up suggestions must be optional read-only questions about the same active scope.
                Active scope: \(scopeDescription(scope.target, language: language)).
                """
        }
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

    private func availabilityError(
        _ availability: GraphChatModelAvailability
    ) -> GraphChatError {
        guard case .unavailable(let reason) = availability else {
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Foundation Model ist nicht verfügbar."
            )
        }
        switch reason {
        case .deviceNotEligible:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Dieses Gerät unterstützt das lokale Foundation Model nicht.",
                recoverySuggestion:
                    "Verwende ein Gerät, das Apple Intelligence und Foundation Models unterstützt."
            )
        case .appleIntelligenceNotEnabled:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Apple Intelligence ist deaktiviert.",
                recoverySuggestion: "Aktiviere Apple Intelligence in den Systemeinstellungen."
            )
        case .modelNotReady:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Modell ist noch nicht bereit.",
                recoverySuggestion:
                    "Warte, bis das Systemmodell vollständig geladen wurde, und versuche es erneut."
            )
        case .unknown:
            return GraphChatError(
                code: .modelUnavailable,
                message: "Das lokale Foundation Model ist aus einem unbekannten Grund nicht verfügbar."
            )
        }
    }

    private func mapError(_ error: Error) -> GraphChatError {
        if let graphChatError = error as? GraphChatError {
            return graphChatError
        }
        if error is CancellationError {
            return GraphChatError(
                code: .cancelled,
                message: "Die Graph-Chat-Anfrage wurde abgebrochen."
            )
        }
        if let providerError = error as? GraphChatProviderError {
            switch providerError.code {
            case .unavailable:
                return GraphChatError(
                    code: .modelUnavailable,
                    message: providerError.message
                )
            case .invalidSession:
                return GraphChatError(
                    code: .invalidRequest,
                    message: providerError.message
                )
            case .concurrentRequest:
                return GraphChatError(
                    code: .concurrentRequest,
                    message: providerError.message
                )
            case .contextWindowExceeded:
                return GraphChatError(
                    code: .contextWindowExceeded,
                    message: providerError.message,
                    recoverySuggestion: "Stelle eine kürzere oder konkretere Frage."
                )
            case .cancelled:
                return GraphChatError(
                    code: .cancelled,
                    message: providerError.message
                )
            case .toolBudgetExceeded:
                return GraphChatError(
                    code: .toolBudgetExceeded,
                    message: providerError.message,
                    recoverySuggestion: "Stelle eine engere Frage mit weniger Teilaspekten."
                )
            case .toolFailure:
                return GraphChatError(
                    code: .toolFailure,
                    message: providerError.message
                )
            case .unsupportedLanguage:
                return GraphChatError(
                    code: .unavailable,
                    message: providerError.message,
                    recoverySuggestion: "Formuliere die Frage in einer vom Gerät unterstützten Sprache."
                )
            case .safetyGuardrail:
                return GraphChatError(
                    code: .unavailable,
                    message: providerError.message
                )
            case .unexpected:
                return GraphChatError(
                    code: .unexpected,
                    message: providerError.message
                )
            }
        }
        if let toolError = error as? GraphChatToolError {
            switch toolError.code {
            case .cancelled:
                return GraphChatError(code: .cancelled, message: toolError.message)
            case .budgetExceeded:
                return GraphChatError(
                    code: .toolBudgetExceeded,
                    message: toolError.message,
                    recoverySuggestion: "Stelle eine engere Frage mit weniger Teilaspekten."
                )
            case .invalidInput, .graphScopeMismatch:
                return GraphChatError(code: .invalidQueryPlan, message: toolError.message)
            case .indexUnavailable, .sourceUnavailable, .unavailable:
                return GraphChatError(code: .toolFailure, message: toolError.message)
            }
        }
        return GraphChatError(
            code: .unexpected,
            message: "Die Graph-Chat-Anfrage konnte nicht abgeschlossen werden."
        )
    }

    private func bounded(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit))
    }
}
