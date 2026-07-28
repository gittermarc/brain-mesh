//
//  GraphChatRequestPreflight.swift
//  BrainMesh
//
//  Deterministic, provider-free preparation of graph-chat turns.
//

import Foundation

nonisolated struct GraphChatOrchestrationScopeKey: Hashable, Sendable {
    let graphScope: GraphScope
    let chatScope: GraphChatScope
}

nonisolated struct GraphChatRequestPreflightInput: Hashable, Sendable {
    let requestID: UUID
    let requestedAt: Date
    let question: String
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let conversationState: GraphChatConversationState
}

nonisolated struct GraphChatLocalTurnPlan: Hashable, Sendable {
    let scopeKey: GraphChatOrchestrationScopeKey
    let normalizedQuestion: String
    let responseLanguage: GraphChatResponseLanguage
    let answer: GraphChatAnswer
    let baseState: GraphChatConversationState
    let expectedCommittedState: GraphChatConversationState
    let pendingClarification: GraphChatPendingClarification?
}

nonisolated struct GraphChatProviderTurnPlan: Hashable, Sendable {
    let scopeKey: GraphChatOrchestrationScopeKey
    let normalizedQuestion: String
    let providerQuestion: String
    let responseLanguage: GraphChatResponseLanguage
    let requestBaseState: GraphChatConversationState
    let expectedCommittedState: GraphChatConversationState
    let conversationContext: GraphChatConversationContextSnapshot
    let currentReference: GraphChatResolvedConversationReference?
    let currentResolvedScope: GraphChatResolvedConversationScope?
    let continuationOperation: GraphChatConversationContinuationOperation?
    let foundationalContinuation: GraphChatFoundationalIntentContinuation?
    let semanticContinuation: GraphChatSemanticIntentContinuation?

    init(
        scopeKey: GraphChatOrchestrationScopeKey,
        normalizedQuestion: String,
        providerQuestion: String,
        responseLanguage: GraphChatResponseLanguage,
        requestBaseState: GraphChatConversationState,
        expectedCommittedState: GraphChatConversationState,
        conversationContext:
            GraphChatConversationContextSnapshot,
        currentReference:
            GraphChatResolvedConversationReference?,
        currentResolvedScope:
            GraphChatResolvedConversationScope?,
        continuationOperation:
            GraphChatConversationContinuationOperation?,
        foundationalContinuation:
            GraphChatFoundationalIntentContinuation?,
        semanticContinuation:
            GraphChatSemanticIntentContinuation? = nil
    ) {
        self.scopeKey = scopeKey
        self.normalizedQuestion = normalizedQuestion
        self.providerQuestion = providerQuestion
        self.responseLanguage = responseLanguage
        self.requestBaseState = requestBaseState
        self.expectedCommittedState =
            expectedCommittedState
        self.conversationContext = conversationContext
        self.currentReference = currentReference
        self.currentResolvedScope = currentResolvedScope
        self.continuationOperation =
            continuationOperation
        self.foundationalContinuation =
            foundationalContinuation
        self.semanticContinuation =
            semanticContinuation
    }
}

nonisolated enum GraphChatRequestPreflightResult: Hashable, Sendable {
    case local(GraphChatLocalTurnPlan)
    case provider(GraphChatProviderTurnPlan)
}

nonisolated struct GraphChatLocalReferenceAnswerPlan: Hashable, Sendable {
    let answer: GraphChatAnswer
    let pendingClarification: GraphChatPendingClarification?
}

/// Pure routing policy for the one reference-resolution outcome that should
/// remain a normal provider question instead of becoming a local clarification.
nonisolated struct GraphChatReferenceMissingContextDeferPolicy: Hashable, Sendable {
    func shouldDeferToProvider(
        _ resolution: GraphChatConversationReferenceResolution
    ) -> Bool {
        switch resolution {
        case .clarification(let clarification):
            return clarification.issue == .missingContext
                && clarification.options.isEmpty
        case .noResults(let issue), .rejected(let issue):
            return issue == .missingContext
        case .resolved:
            return false
        }
    }

    func shouldIgnoreUnresolvedProviderProposal(
        _ resolution: GraphChatConversationReferenceResolution,
        directAnswer: String
    ) -> Bool {
        guard
            directAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                == false
        else {
            return false
        }
        return shouldDeferToProvider(resolution)
    }
}

/// Provider-free builders shared by request preflight and the existing answer
/// finalization path. IDs and time are supplied by the caller so preflight
/// stays deterministic for identical inputs.
nonisolated struct GraphChatLocalAnswerBuilder: Hashable, Sendable {
    func unsupported(
        _ capability: GraphChatUnsupportedCapability,
        language: GraphChatResponseLanguage
    ) -> GraphChatAnswer {
        let localizer = GraphChatResponseLocalizer(language: language)
        return GraphChatAnswer(
            state: .unsupported(capability),
            directAnswer: localizer.unsupported(capability),
            hasInsufficientEvidence: false
        )
    }

    func staleClarification(
        language: GraphChatResponseLanguage,
        clarificationID: UUID
    ) -> GraphChatAnswer {
        let question = GraphChatResponseLocalizer(language: language)
            .clarificationQuestion(reason: .staleResults)
        return GraphChatAnswer(
            state: .clarification(
                GraphChatClarification(
                    id: clarificationID,
                    question: question,
                    options: []
                )
            ),
            directAnswer: question,
            hasInsufficientEvidence: true
        )
    }

    func repeatedClarification(
        pending: GraphChatPendingClarification,
        language: GraphChatResponseLanguage
    ) -> GraphChatAnswer {
        let question = GraphChatResponseLocalizer(language: language)
            .clarificationQuestion(reason: .ambiguous)
        return GraphChatAnswer(
            state: .clarification(
                GraphChatClarification(
                    id: pending.id,
                    question: question,
                    options: pending.options.prefix(8).map {
                        GraphChatClarificationOption(id: $0.id, title: $0.title)
                    }
                )
            ),
            directAnswer: question,
            hasInsufficientEvidence: true
        )
    }

    func referenceResolution(
        _ resolution: GraphChatConversationReferenceResolution,
        language: GraphChatResponseLanguage,
        operation: GraphChatConversationContinuationOperation,
        state: GraphChatConversationState,
        sourceTurnID: UUID?,
        continuationQuestion: String,
        clarificationID: UUID,
        referenceDate: Date
    ) -> GraphChatLocalReferenceAnswerPlan {
        let localizer = GraphChatResponseLocalizer(language: language)
        switch resolution {
        case .resolved:
            return GraphChatLocalReferenceAnswerPlan(
                answer: GraphChatAnswer(
                    state: .answer,
                    directAnswer: "",
                    hasInsufficientEvidence: false
                ),
                pendingClarification: nil
            )

        case .noResults(let issue):
            let text =
                issue == .emptyResults
                ? localizer.noResults()
                : localizer.clarificationQuestion(reason: issue)
            return GraphChatLocalReferenceAnswerPlan(
                answer: GraphChatAnswer(
                    state: .noResults,
                    directAnswer: text,
                    hasInsufficientEvidence: true
                ),
                pendingClarification: nil
            )

        case .rejected(let issue):
            let question = localizer.clarificationQuestion(reason: issue)
            return GraphChatLocalReferenceAnswerPlan(
                answer: GraphChatAnswer(
                    state: .clarification(
                        GraphChatClarification(
                            id: clarificationID,
                            question: question,
                            options: []
                        )
                    ),
                    directAnswer: question,
                    hasInsufficientEvidence: true
                ),
                pendingClarification: nil
            )

        case .clarification(let clarification):
            let options = Array(clarification.options.prefix(8))
            let question =
                clarification.issue == .mixedEntities
                ? localizer.mixedEntityClarification(
                    optionTitles: options.map(\.title)
                )
                : localizer.clarificationQuestion(reason: clarification.issue)
            let pending = makePendingClarification(
                id: clarificationID,
                options: options,
                operation: operation,
                state: state,
                sourceTurnID: sourceTurnID,
                continuationQuestion: continuationQuestion,
                referenceDate: referenceDate
            )
            return GraphChatLocalReferenceAnswerPlan(
                answer: GraphChatAnswer(
                    state: .clarification(
                        GraphChatClarification(
                            id: pending?.id ?? clarificationID,
                            question: question,
                            options: options.map {
                                GraphChatClarificationOption(
                                    id: $0.id,
                                    title: $0.title
                                )
                            }
                        )
                    ),
                    directAnswer: question,
                    hasInsufficientEvidence: true
                ),
                pendingClarification: pending
            )
        }
    }

    func makePendingClarification(
        id: UUID,
        options: [GraphChatPendingClarificationOption],
        operation: GraphChatConversationContinuationOperation,
        state: GraphChatConversationState,
        sourceTurnID: UUID? = nil,
        continuationQuestion: String,
        referenceDate: Date
    ) -> GraphChatPendingClarification? {
        let boundedOptions = Array(options.prefix(8))
        guard boundedOptions.isEmpty == false else {
            return nil
        }
        return GraphChatPendingClarification(
            id: id,
            decision: .conversationReference,
            options: boundedOptions,
            sourceTurnID: sourceTurnID ?? state.turnContexts.last?.id,
            graphScope: state.graphScope,
            chatScope: state.chatScope,
            continuationOperation: operation,
            continuationQuestion: bounded(continuationQuestion, limit: 500),
            createdAt: referenceDate,
            expiresAt: referenceDate.addingTimeInterval(10 * 60)
        )
    }

    private func bounded(_ value: String, limit: Int) -> String {
        value.count <= limit ? value : String(value.prefix(limit))
    }
}

nonisolated struct GraphChatRequestPreflight: Sendable {
    private let conversationStateReducer: GraphChatConversationStateReducer
    private let conversationContextBuilder: GraphChatConversationContextBuilder
    private let referenceResolver: GraphChatConversationReferenceResolver
    private let referenceInterpreter: GraphChatConversationReferenceInterpreter
    private let unsupportedRequestDetector: GraphChatUnsupportedRequestDetector
    private let responseLanguageSelector: GraphChatResponseLanguageSelector
    private let missingContextPolicy: GraphChatReferenceMissingContextDeferPolicy
    private let localAnswerBuilder: GraphChatLocalAnswerBuilder

    init(
        conversationStateReducer: GraphChatConversationStateReducer =
            GraphChatConversationStateReducer(),
        conversationContextBuilder: GraphChatConversationContextBuilder =
            GraphChatConversationContextBuilder(),
        referenceResolver: GraphChatConversationReferenceResolver =
            GraphChatConversationReferenceResolver(),
        responseLanguageSelector: GraphChatResponseLanguageSelector =
            GraphChatResponseLanguageSelector(),
        missingContextPolicy: GraphChatReferenceMissingContextDeferPolicy =
            GraphChatReferenceMissingContextDeferPolicy(),
        localAnswerBuilder: GraphChatLocalAnswerBuilder =
            GraphChatLocalAnswerBuilder()
    ) {
        self.conversationStateReducer = conversationStateReducer
        self.conversationContextBuilder = conversationContextBuilder
        self.referenceResolver = referenceResolver
        self.referenceInterpreter = GraphChatConversationReferenceInterpreter()
        self.unsupportedRequestDetector = GraphChatUnsupportedRequestDetector()
        self.responseLanguageSelector = responseLanguageSelector
        self.missingContextPolicy = missingContextPolicy
        self.localAnswerBuilder = localAnswerBuilder
    }

    func validatedKey(
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) throws -> GraphChatOrchestrationScopeKey {
        guard graphScope == chatScope.graphScope else {
            throw GraphChatError(
                code: .invalidRequest,
                message: "Der Chat-Scope gehört nicht zum aktiven Graphen."
            )
        }
        return GraphChatOrchestrationScopeKey(
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    func evaluate(
        _ input: GraphChatRequestPreflightInput
    ) async throws -> GraphChatRequestPreflightResult {
        let key = try validatedKey(
            graphScope: input.graphScope,
            chatScope: input.chatScope
        )
        let normalizedQuestion = try validateQuestion(input.question)
        let language = responseLanguageSelector.language(for: normalizedQuestion)
        let expectedCommittedState = input.conversationState

        if input.conversationState.pendingClarification == nil,
            let unsupportedCapability = unsupportedRequestDetector.capability(
                for: normalizedQuestion
            )
        {
            return .local(
                localPlan(
                    key: key,
                    normalizedQuestion: normalizedQuestion,
                    language: language,
                    answer: localAnswerBuilder.unsupported(
                        unsupportedCapability,
                        language: language
                    ),
                    baseState: input.conversationState,
                    expectedCommittedState: expectedCommittedState
                )
            )
        }

        var requestBaseState = input.conversationState
        var currentReference: GraphChatResolvedConversationReference?
        var currentResolvedScope: GraphChatResolvedConversationScope?
        var continuationOperation: GraphChatConversationContinuationOperation?
        var providerQuestion = normalizedQuestion
        var context = conversationContextBuilder.makeSnapshot(
            from: requestBaseState.snapshot
        )

        if let pending = requestBaseState.pendingClarification {
            guard
                pending.isValid(
                    at: input.requestedAt,
                    graphScope: key.graphScope,
                    chatScope: key.chatScope
                )
            else {
                requestBaseState = try clearedClarification(in: requestBaseState)
                return .local(
                    localPlan(
                        key: key,
                        normalizedQuestion: normalizedQuestion,
                        language: language,
                        answer: localAnswerBuilder.staleClarification(
                            language: language,
                            clarificationID: input.requestID
                        ),
                        baseState: requestBaseState,
                        expectedCommittedState: expectedCommittedState
                    )
                )
            }

            guard
                let selectedOption = referenceInterpreter.clarificationSelection(
                    for: normalizedQuestion,
                    pending: pending
                )
            else {
                return .local(
                    localPlan(
                        key: key,
                        normalizedQuestion: normalizedQuestion,
                        language: language,
                        answer: localAnswerBuilder.repeatedClarification(
                            pending: pending,
                            language: language
                        ),
                        baseState: requestBaseState,
                        expectedCommittedState: expectedCommittedState
                    )
                )
            }

            if pending.decision == .foundationalIntent {
                let continuationLanguage =
                    responseLanguageSelector.language(
                        for: pending.continuationQuestion
                    )
                guard let selection = selectedOption.foundationalSelection else {
                    return .local(
                        localPlan(
                            key: key,
                            normalizedQuestion: normalizedQuestion,
                            language: language,
                            answer: localAnswerBuilder.staleClarification(
                                language: continuationLanguage,
                                clarificationID: input.requestID
                            ),
                            baseState: try clearedClarification(
                                in: requestBaseState
                            ),
                            expectedCommittedState: expectedCommittedState
                        )
                    )
                }
                requestBaseState = try clearedClarification(
                    in: requestBaseState
                )
                context = conversationContextBuilder.makeSnapshot(
                    from: requestBaseState.snapshot
                )
                return .provider(
                    GraphChatProviderTurnPlan(
                        scopeKey: key,
                        normalizedQuestion: normalizedQuestion,
                        providerQuestion: pending.continuationQuestion,
                        responseLanguage: continuationLanguage,
                        requestBaseState: requestBaseState,
                        expectedCommittedState: expectedCommittedState,
                        conversationContext: context,
                        currentReference: nil,
                        currentResolvedScope: nil,
                        continuationOperation: nil,
                        foundationalContinuation:
                            GraphChatFoundationalIntentContinuation(
                                selection: selection,
                                sourceTurnID: pending.sourceTurnID,
                                clarificationID: pending.id
                            ),
                        semanticContinuation: nil
                    )
                )
            }

            if pending.decision == .semanticIntent {
                let continuationLanguage =
                    responseLanguageSelector.language(
                        for: pending.continuationQuestion
                    )
                guard
                    let selection =
                        selectedOption
                            .semanticSelection
                else {
                    return .local(
                        localPlan(
                            key: key,
                            normalizedQuestion:
                                normalizedQuestion,
                            language:
                                continuationLanguage,
                            answer:
                                localAnswerBuilder
                                    .staleClarification(
                                        language:
                                            continuationLanguage,
                                        clarificationID:
                                            input.requestID
                                    ),
                            baseState:
                                try clearedClarification(
                                    in: requestBaseState
                                ),
                            expectedCommittedState:
                                expectedCommittedState
                        )
                    )
                }
                requestBaseState =
                    try clearedClarification(
                        in: requestBaseState
                    )
                context = conversationContextBuilder
                    .makeSnapshot(
                        from:
                            requestBaseState
                                .snapshot
                    )

                var semanticReference:
                    GraphChatResolvedConversationReference? = nil
                var semanticScope:
                    GraphChatResolvedConversationScope? = nil
                if selection.draft
                    .conversationReference
                    == .currentSelection
                {
                    let resolution =
                        try await referenceResolver
                            .resolveScope(
                                selectedOption.proposal,
                                in: context,
                                expectedGraphScope:
                                    key.graphScope,
                                expectedChatScope:
                                    key.chatScope
                            )
                    guard
                        case .resolved(
                            let resolvedScope
                        ) = resolution
                    else {
                        let local =
                            localAnswerBuilder
                                .referenceResolution(
                                    resolution
                                        .referenceResolution,
                                    language:
                                        continuationLanguage,
                                    operation:
                                        pending
                                            .continuationOperation,
                                    state:
                                        requestBaseState,
                                    sourceTurnID:
                                        pending.sourceTurnID,
                                    continuationQuestion:
                                        pending
                                            .continuationQuestion,
                                    clarificationID:
                                        input.requestID,
                                    referenceDate:
                                        input.requestedAt
                                )
                        let semanticPending =
                            local
                                .pendingClarification
                                .map { source in
                                    GraphChatPendingClarification(
                                        id:
                                            source.id,
                                        decision:
                                            .semanticIntent,
                                        options:
                                            source.options.map {
                                                GraphChatPendingClarificationOption(
                                                    id:
                                                        $0.id,
                                                    title:
                                                        $0.title,
                                                    proposal:
                                                        $0.proposal,
                                                    foundationalSelection:
                                                        nil,
                                                    semanticSelection:
                                                        selection
                                                )
                                            },
                                        sourceTurnID:
                                            source
                                                .sourceTurnID,
                                        graphScope:
                                            source
                                                .graphScope,
                                        chatScope:
                                            source
                                                .chatScope,
                                        continuationOperation:
                                            source
                                                .continuationOperation,
                                        continuationQuestion:
                                            source
                                                .continuationQuestion,
                                        createdAt:
                                            source
                                                .createdAt,
                                        expiresAt:
                                            source
                                                .expiresAt
                                    )
                                }
                        return .local(
                            localPlan(
                                key: key,
                                normalizedQuestion:
                                    normalizedQuestion,
                                language:
                                    continuationLanguage,
                                answer:
                                    local.answer,
                                baseState:
                                    requestBaseState,
                                expectedCommittedState:
                                    expectedCommittedState,
                                pendingClarification:
                                    semanticPending
                            )
                        )
                    }
                    semanticScope = resolvedScope
                    semanticReference =
                        resolvedScope.reference
                    context =
                        conversationContextBuilder
                            .makeSnapshot(
                                from:
                                    requestBaseState
                                        .snapshot,
                                currentReference:
                                    semanticReference,
                                currentResolvedScope:
                                    semanticScope
                            )
                }

                return .provider(
                    GraphChatProviderTurnPlan(
                        scopeKey: key,
                        normalizedQuestion:
                            normalizedQuestion,
                        providerQuestion:
                            pending
                                .continuationQuestion,
                        responseLanguage:
                            continuationLanguage,
                        requestBaseState:
                            requestBaseState,
                        expectedCommittedState:
                            expectedCommittedState,
                        conversationContext:
                            context,
                        currentReference:
                            semanticReference,
                        currentResolvedScope:
                            semanticScope,
                        continuationOperation:
                            nil,
                        foundationalContinuation:
                            nil,
                        semanticContinuation:
                            GraphChatSemanticIntentContinuation(
                                selection:
                                    selection,
                                sourceTurnID:
                                    pending
                                        .sourceTurnID,
                                clarificationID:
                                    pending.id
                            )
                    )
                )
            }

            let resolution = try await referenceResolver.resolveScope(
                selectedOption.proposal,
                in: context,
                expectedGraphScope: key.graphScope,
                expectedChatScope: key.chatScope
            )
            requestBaseState = try clearedClarification(in: requestBaseState)
            guard case .resolved(let resolvedScope) = resolution else {
                let local = localAnswerBuilder.referenceResolution(
                    resolution.referenceResolution,
                    language: language,
                    operation: pending.continuationOperation,
                    state: requestBaseState,
                    sourceTurnID: pending.sourceTurnID,
                    continuationQuestion: pending.continuationQuestion,
                    clarificationID: input.requestID,
                    referenceDate: input.requestedAt
                )
                return .local(
                    localPlan(
                        key: key,
                        normalizedQuestion: normalizedQuestion,
                        language: language,
                        answer: local.answer,
                        baseState: requestBaseState,
                        expectedCommittedState: expectedCommittedState,
                        pendingClarification: local.pendingClarification
                    )
                )
            }
            currentResolvedScope = resolvedScope
            currentReference = resolvedScope.reference
            continuationOperation = pending.continuationOperation
            providerQuestion = pending.continuationQuestion
        } else if let interpretation = referenceInterpreter.interpretation(
            for: normalizedQuestion
        ) {
            if interpretation.operation
                == .compareReferences
            {
                let resolution =
                    try await referenceResolver
                        .resolve(
                            interpretation
                                .proposal,
                            in: context,
                            expectedGraphScope:
                                key.graphScope,
                            expectedChatScope:
                                key.chatScope
                        )
                switch resolution {
                case .resolved(let reference):
                    currentReference =
                        reference
                    currentResolvedScope = nil
                    continuationOperation =
                        interpretation.operation
                case .clarification, .noResults,
                    .rejected:
                    if missingContextPolicy
                        .shouldDeferToProvider(
                            resolution
                        ) == false
                    {
                        let local =
                            localAnswerBuilder
                                .referenceResolution(
                                    resolution,
                                    language:
                                        language,
                                    operation:
                                        interpretation
                                            .operation,
                                    state:
                                        requestBaseState,
                                    sourceTurnID:
                                        requestBaseState
                                            .turnContexts
                                            .last?.id,
                                    continuationQuestion:
                                        normalizedQuestion,
                                    clarificationID:
                                        input.requestID,
                                    referenceDate:
                                        input.requestedAt
                                )
                        return .local(
                            localPlan(
                                key: key,
                                normalizedQuestion:
                                    normalizedQuestion,
                                language:
                                    language,
                                answer:
                                    local.answer,
                                baseState:
                                    requestBaseState,
                                expectedCommittedState:
                                    expectedCommittedState,
                                pendingClarification:
                                    local
                                        .pendingClarification
                            )
                        )
                    }
                }
            } else {
                let resolution = try await referenceResolver.resolveScope(
                    interpretation.proposal,
                    in: context,
                    expectedGraphScope: key.graphScope,
                    expectedChatScope: key.chatScope
                )
                switch resolution {
                case .resolved(let resolvedScope):
                    currentResolvedScope = resolvedScope
                    currentReference = resolvedScope.reference
                    continuationOperation = interpretation.operation

                case .clarification, .noResults, .rejected:
                    let referenceResolution = resolution.referenceResolution
                    if missingContextPolicy
                        .shouldDeferToProvider(referenceResolution) == false
                    {
                        let local = localAnswerBuilder.referenceResolution(
                            referenceResolution,
                            language: language,
                            operation: interpretation.operation,
                            state: requestBaseState,
                            sourceTurnID: requestBaseState.turnContexts.last?.id,
                            continuationQuestion: normalizedQuestion,
                            clarificationID: input.requestID,
                            referenceDate: input.requestedAt
                        )
                        return .local(
                            localPlan(
                                key: key,
                                normalizedQuestion: normalizedQuestion,
                                language: language,
                                answer: local.answer,
                                baseState: requestBaseState,
                                expectedCommittedState: expectedCommittedState,
                                pendingClarification: local.pendingClarification
                            )
                        )
                    }
                }
            }
        }

        context = conversationContextBuilder.makeSnapshot(
            from: requestBaseState.snapshot,
            currentReference: currentReference,
            currentResolvedScope: currentResolvedScope
        )
        return .provider(
            GraphChatProviderTurnPlan(
                scopeKey: key,
                normalizedQuestion: normalizedQuestion,
                providerQuestion: providerQuestion,
                responseLanguage: language,
                requestBaseState: requestBaseState,
                expectedCommittedState: expectedCommittedState,
                conversationContext: context,
                currentReference: currentReference,
                currentResolvedScope: currentResolvedScope,
                continuationOperation: continuationOperation,
                foundationalContinuation: nil,
                semanticContinuation: nil
            )
        )
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

    private func localPlan(
        key: GraphChatOrchestrationScopeKey,
        normalizedQuestion: String,
        language: GraphChatResponseLanguage,
        answer: GraphChatAnswer,
        baseState: GraphChatConversationState,
        expectedCommittedState: GraphChatConversationState,
        pendingClarification: GraphChatPendingClarification? = nil
    ) -> GraphChatLocalTurnPlan {
        GraphChatLocalTurnPlan(
            scopeKey: key,
            normalizedQuestion: normalizedQuestion,
            responseLanguage: language,
            answer: answer,
            baseState: baseState,
            expectedCommittedState: expectedCommittedState,
            pendingClarification: pendingClarification
        )
    }
}
