//
//  GraphChatSemanticIntentCoordinator.swift
//  BrainMesh
//
//  Orchestrates tool-free interpretation and app-owned semantic resolution.
//

import Foundation

nonisolated enum GraphChatLegacyProviderFallbackReason:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case unrecognized
    case openEnded
    case interpreterUnavailable
}

nonisolated enum GraphChatSemanticIntentCoordinatorResolution:
    Sendable
{
    case local(GraphChatLocalTurnPlan)
    case compiled(
        adaptation: GraphChatTypedIntentAdaptation,
        schemaContext: GraphSchemaContext
    )
    case legacyProviderFallback(
        GraphChatLegacyProviderFallbackReason
    )
}

nonisolated struct GraphChatSemanticIntentCoordinator:
    Sendable
{
    private let interpreter:
        any GraphChatIntentInterpreting
    private let requestBuilder:
        GraphChatIntentInterpreterRequestBuilder
    private let compactRetryRequestBuilder:
        GraphChatIntentInterpreterRequestBuilder
    private let draftValidator:
        GraphChatSemanticDraftValidator
    private let resolver:
        GraphChatSemanticIntentResolver
    private let referenceResolver:
        GraphChatConversationReferenceResolver
    private let localAnswerBuilder:
        GraphChatLocalAnswerBuilder
    private let cutoverPolicy:
        GraphChatTypedPlannerCutoverPolicy
    private let observability:
        any GraphChatObservabilityRecording

    init(
        interpreter:
            any GraphChatIntentInterpreting,
        requestBuilder:
            GraphChatIntentInterpreterRequestBuilder =
                GraphChatIntentInterpreterRequestBuilder(),
        compactRetryRequestBuilder:
            GraphChatIntentInterpreterRequestBuilder =
                GraphChatIntentInterpreterRequestBuilder(
                    limits: .compactRetry
                ),
        draftValidator:
            GraphChatSemanticDraftValidator =
                GraphChatSemanticDraftValidator(),
        resolver:
            GraphChatSemanticIntentResolver =
                GraphChatSemanticIntentResolver(),
        referenceResolver:
            GraphChatConversationReferenceResolver =
                GraphChatConversationReferenceResolver(),
        localAnswerBuilder:
            GraphChatLocalAnswerBuilder =
                GraphChatLocalAnswerBuilder(),
        cutoverPolicy:
            GraphChatTypedPlannerCutoverPolicy =
                .default,
        observability:
            any GraphChatObservabilityRecording =
                NoOpGraphChatObservabilityRecorder()
    ) {
        self.interpreter = interpreter
        self.requestBuilder = requestBuilder
        self.compactRetryRequestBuilder =
            compactRetryRequestBuilder
        self.draftValidator = draftValidator
        self.resolver = resolver
        self.referenceResolver = referenceResolver
        self.localAnswerBuilder = localAnswerBuilder
        self.cutoverPolicy = cutoverPolicy
        self.observability = observability
    }

    func resolve(
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext,
        requestID: UUID,
        requestedAt: Date
    ) async throws
        -> GraphChatSemanticIntentCoordinatorResolution
    {
        let request = try requestBuilder.makeRequest(
            providerPlan: providerPlan,
            schemaContext: schemaContext
        )
        let continuation =
            providerPlan.semanticContinuation
        if let sourceTurnID =
            continuation?.sourceTurnID
        {
            guard
                providerPlan.requestBaseState
                    .turnContexts.contains(
                        where: {
                            $0.id == sourceTurnID
                        }
                    )
            else {
                throw GraphChatError(
                    code: .invalidRequest,
                    message:
                        "Die ursprüngliche Semantic-Intent-Klärung ist nicht mehr im Conversation-State gebunden."
                )
            }
        }

        let draft: GraphChatUntrustedSemanticIntentDraft
        let selectedEntityID: UUID?
        let selectedFields:
            [GraphChatSemanticSelectedField]
        let selectedNodes:
            [GraphChatSemanticSelectedNode]
        if let continuation {
            do {
                draft = try draftValidator.validate(
                    continuation.selection.draft,
                    for: request
                )
                selectedEntityID =
                    continuation.selection
                        .selectedEntityID
                selectedFields =
                    continuation.selection
                        .selectedFields
                selectedNodes =
                    continuation.selection
                        .selectedNodes
            } catch {
                if isCancellation(error) {
                    await record(
                        .cancellation,
                        family: nil
                    )
                    throw CancellationError()
                }
                await record(
                    .draftRejected,
                    family: nil
                )
                await recordPlanner(
                    .draftOutcome(
                        .rejected,
                        nil
                    )
                )
                throw mappedInterpreterError(error)
            }
        } else {
            let recovery: InterpreterRecoveryResolution
            do {
                recovery = try await interpretWithRecovery(
                    request,
                    providerPlan: providerPlan,
                    schemaContext: schemaContext
                )
            } catch {
                if isCancellation(error) {
                    await record(
                        .cancellation,
                        family: nil
                    )
                    throw CancellationError()
                }
                await record(
                    .draftRejected,
                    family: nil
                )
                await recordPlanner(
                    .draftOutcome(
                        .rejected,
                        nil
                    )
                )
                throw mappedInterpreterError(error)
            }
            switch recovery {
            case .interpreterUnavailable:
                await record(
                    .legacyProviderFallback,
                    family: nil
                )
                await recordPlanner(
                    .draftOutcome(
                        .interpreterUnavailable,
                        nil
                    )
                )
                await recordPlanner(
                    .legacyProviderFallback(
                        .interpreterUnavailable
                    )
                )
                return .legacyProviderFallback(
                    .interpreterUnavailable
                )
            case .draft(let untrusted):
                do {
                    try Task.checkCancellation()
                    draft = try draftValidator.validate(
                        untrusted,
                        for: request
                    )
                } catch {
                    if isCancellation(error) {
                        await record(
                            .cancellation,
                            family: nil
                        )
                        throw CancellationError()
                    }
                    await record(
                        .draftRejected,
                        family: nil
                    )
                    await recordPlanner(
                        .draftOutcome(
                            .rejected,
                            nil
                        )
                    )
                    throw mappedInterpreterError(error)
                }
                selectedEntityID = nil
                selectedFields = []
                selectedNodes = []
            }
        }

        await record(
            .draftAccepted,
            family: draft.family
        )
        await recordPlanner(
            .draftOutcome(
                plannerDraftOutcome(
                    for: draft.family
                ),
                draft.family
            )
        )

        if let fallbackReason =
            legacyFallbackReason(
                for: draft.family
            )
        {
            await record(
                .legacyProviderFallback,
                family: draft.family
            )
            await recordPlanner(
                .legacyProviderFallback(
                    fallbackReason
                )
            )
            return .legacyProviderFallback(
                fallbackReason
            )
        }

        let currentScopeResolution:
            CurrentScopeResolution
        do {
            currentScopeResolution =
                try await currentScope(
                    for: draft,
                    providerPlan:
                        providerPlan,
                    requestID: requestID,
                    requestedAt:
                        requestedAt,
                    selectedEntityID:
                        selectedEntityID,
                    selectedFields:
                        selectedFields,
                    selectedNodes:
                        selectedNodes
                )
        } catch {
            if isCancellation(error) {
                await record(
                    .cancellation,
                    family: draft.family
                )
                throw CancellationError()
            }
            await record(
                .draftRejected,
                family: draft.family
            )
            await recordPlanner(
                .draftOutcome(
                    .rejected,
                    draft.family
                )
            )
            throw GraphChatError(
                code: .invalidRequest,
                message:
                    (error as? LocalizedError)?
                        .errorDescription
                    ?? "Die Conversation-Auswahl konnte nicht sicher revalidiert werden."
            )
        }
        switch currentScopeResolution {
        case .local(let local):
            if case .clarification =
                local.answer.state
            {
                await recordPlanner(
                    .clarification(
                        draft.family
                    )
                )
            }
            return .local(local)
        case .resolved(let currentResolvedScope):
            do {
                let resolution = try resolver.resolve(
                    draft: draft,
                    selectedEntityID:
                        selectedEntityID,
                    selectedFields:
                        selectedFields,
                    selectedNodes:
                        selectedNodes,
                    currentResolvedScope:
                        currentResolvedScope,
                    providerPlan: providerPlan,
                    schemaContext: schemaContext,
                    requestID: requestID,
                    sourceTurnID:
                        continuation?.sourceTurnID,
                    clarificationID:
                        continuation?
                            .clarificationID,
                    referenceDate:
                        requestedAt
                )
                switch resolution {
                case .legacyProviderFallback:
                    guard
                        let fallbackReason =
                            legacyFallbackReason(
                                for:
                                    draft.family
                            )
                    else {
                        throw GraphChatError(
                            code: .invalidRequest,
                            message:
                                "Ein erkannter Semantic Intent darf nicht auf die freie Provider-Ausführung zurückfallen."
                        )
                    }
                    await record(
                        .legacyProviderFallback,
                        family: draft.family
                    )
                    await recordPlanner(
                        .legacyProviderFallback(
                            fallbackReason
                        )
                    )
                    return .legacyProviderFallback(
                        fallbackReason
                    )

                case .clarification(let clarification):
                    await record(
                        .clarificationRequired,
                        family: draft.family
                    )
                    await recordPlanner(
                        .clarification(
                            draft.family
                        )
                    )
                    return .local(
                        localEntityClarification(
                            clarification,
                            providerPlan:
                                providerPlan,
                            requestID: requestID,
                            requestedAt:
                                requestedAt
                        )
                    )

                case .compiled(let adaptation):
                    await record(
                        compilationEvent(
                            for: draft.family,
                            adaptation: adaptation
                        ),
                        family: draft.family
                    )
                    await recordPlanner(
                        .localIntent(
                            adaptation
                                .intent.kind
                        )
                    )
                    let executionContext =
                        GraphSchemaContext(
                            graphScope:
                                schemaContext
                                    .graphScope,
                            snapshot:
                                schemaContext
                                    .snapshot,
                            aliases:
                                schemaContext
                                    .foundationalAliases
                        )
                    return .compiled(
                        adaptation: adaptation,
                        schemaContext:
                            executionContext
                    )
                }
            } catch {
                if isCancellation(error) {
                    await record(
                        .cancellation,
                        family: draft.family
                    )
                    throw CancellationError()
                }
                if let event =
                    compilationRejectionEvent(
                        for: error,
                        family: draft.family
                    )
                {
                    await record(
                        event,
                        family: draft.family
                    )
                }
                await record(
                    .draftRejected,
                    family: draft.family
                )
                await recordPlanner(
                    .draftOutcome(
                        .rejected,
                        draft.family
                    )
                )
                throw GraphChatError(
                    code: .invalidRequest,
                    message:
                        (error as? LocalizedError)?
                            .errorDescription
                        ?? "Der Semantic Draft konnte nicht sicher gegen Schema und Scope aufgelöst werden."
                )
            }
        }
    }

    private enum InterpreterRecoveryResolution {
        case draft(
            GraphChatUntrustedSemanticIntentDraft
        )
        case interpreterUnavailable
    }

    private func interpretWithRecovery(
        _ standardRequest:
            GraphChatIntentInterpreterRequest,
        providerPlan: GraphChatProviderTurnPlan,
        schemaContext: GraphSchemaContext
    ) async throws -> InterpreterRecoveryResolution {
        await recordPlanner(
            .semanticInterpreter
        )
        await record(
            .interpreterStarted,
            family: nil,
            interpreterCallCount: 1
        )
        do {
            let draft = try await interpreter
                .interpret(standardRequest)
            try Task.checkCancellation()
            return .draft(draft)
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }
            guard isContextWindowExceeded(error) else {
                if isTechnicalInterpreterUnavailable(
                    error
                ) {
                    return .interpreterUnavailable
                }
                throw error
            }
        }

        try Task.checkCancellation()
        let compactRequest =
            try compactRetryRequestBuilder
                .makeRequest(
                    providerPlan: providerPlan,
                    schemaContext: schemaContext
                )
        try Task.checkCancellation()
        await record(
            .interpreterRetry,
            family: nil,
            interpreterCallCount: 1
        )
        await recordPlanner(
            .interpreterRetry
        )
        do {
            let draft = try await interpreter
                .interpret(compactRequest)
            try Task.checkCancellation()
            return .draft(draft)
        } catch {
            if isCancellation(error) {
                throw CancellationError()
            }
            if isTechnicalInterpreterUnavailable(
                error
            ) {
                return .interpreterUnavailable
            }
            throw error
        }
    }

    private func legacyFallbackReason(
        for family: GraphChatSemanticIntentFamily
    ) -> GraphChatLegacyProviderFallbackReason? {
        cutoverPolicy.legacyFallbackReason(
            for: family
        )
    }

    private func plannerDraftOutcome(
        for family: GraphChatSemanticIntentFamily
    ) -> GraphChatTypedPlannerDraftOutcome {
        cutoverPolicy.draftOutcome(
            for: family
        )
    }

    private func isContextWindowExceeded(
        _ error: Error
    ) -> Bool {
        (
            error
                as? GraphChatIntentInterpreterError
        )?.code == .contextWindowExceeded
    }

    private func isTechnicalInterpreterUnavailable(
        _ error: Error
    ) -> Bool {
        guard
            let code = (
                error
                    as? GraphChatIntentInterpreterError
            )?.code
        else {
            return false
        }
        return code == .unavailable
            || code == .contextWindowExceeded
    }

    private enum CurrentScopeResolution {
        case resolved(
            GraphChatResolvedConversationScope?
        )
        case local(GraphChatLocalTurnPlan)
    }

    private func currentScope(
        for draft: GraphChatUntrustedSemanticIntentDraft,
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        requestedAt: Date,
        selectedEntityID: UUID?,
        selectedFields:
            [GraphChatSemanticSelectedField],
        selectedNodes:
            [GraphChatSemanticSelectedNode]
    ) async throws -> CurrentScopeResolution {
        if let current =
            providerPlan.currentResolvedScope
        {
            return .resolved(current)
        }
        if draft.family == .compareNodes,
           providerPlan.currentReference != nil {
            return .resolved(nil)
        }
        guard
            draft.conversationReference
                == .currentSelection
        else {
            return .resolved(nil)
        }

        let resolution = try await referenceResolver
            .resolveScope(
                .latestResults,
                in: providerPlan
                    .conversationContext,
                expectedGraphScope:
                    providerPlan.scopeKey
                        .graphScope,
                expectedChatScope:
                    providerPlan.scopeKey
                        .chatScope
            )
        if case .resolved(let scope) = resolution {
            return .resolved(scope)
        }
        switch resolution {
        case .rejected(.staleResults):
            await record(
                .staleResultSetRejected,
                family: draft.family
            )
        case .rejected(
            .graphMismatch
        ), .rejected(
            .scopeMismatch
        ), .rejected(
            .entityMismatch
        ):
            await record(
                .scopeExpansionPrevented,
                family: draft.family
            )
        case .resolved, .clarification, .noResults,
            .rejected:
            break
        }

        let local = localAnswerBuilder
            .referenceResolution(
                resolution.referenceResolution,
                language:
                    providerPlan.responseLanguage,
                operation: .filterReferenceSet,
                state:
                    providerPlan.requestBaseState,
                sourceTurnID:
                    providerPlan
                        .requestBaseState
                        .turnContexts.last?.id,
                continuationQuestion:
                    providerPlan.providerQuestion,
                clarificationID: requestID,
                referenceDate: requestedAt
            )
        let pending = local.pendingClarification
            .map { source in
                GraphChatPendingClarification(
                    id: source.id,
                    decision: .semanticIntent,
                    options: source.options.map {
                        GraphChatPendingClarificationOption(
                            id: $0.id,
                            title: $0.title,
                            proposal:
                                $0.proposal,
                            foundationalSelection:
                                nil,
                            semanticSelection:
                                GraphChatSemanticIntentSelection(
                                    draft: draft,
                                    selectedEntityID:
                                        selectedEntityID,
                                    selectedFields:
                                        selectedFields,
                                    selectedNodes:
                                        selectedNodes
                                )
                        )
                    },
                    sourceTurnID:
                        source.sourceTurnID,
                    graphScope:
                        source.graphScope,
                    chatScope:
                        source.chatScope,
                    continuationOperation:
                        source.continuationOperation,
                    continuationQuestion:
                        source.continuationQuestion,
                    createdAt: source.createdAt,
                    expiresAt: source.expiresAt
                )
            }
        await record(
            .clarificationRequired,
            family: draft.family
        )
        return .local(
            GraphChatLocalTurnPlan(
                scopeKey: providerPlan.scopeKey,
                normalizedQuestion:
                    providerPlan.normalizedQuestion,
                responseLanguage:
                    providerPlan.responseLanguage,
                answer: local.answer,
                baseState:
                    providerPlan.requestBaseState,
                expectedCommittedState:
                    providerPlan
                        .expectedCommittedState,
                pendingClarification: pending
            )
        )
    }

    private func localEntityClarification(
        _ clarification:
            GraphChatSemanticEntityClarification,
        providerPlan: GraphChatProviderTurnPlan,
        requestID: UUID,
        requestedAt: Date
    ) -> GraphChatLocalTurnPlan {
        let options = clarification.candidates
            .prefix(
                GraphChatIntentLimitPolicy
                    .default.maximumClarificationOptionCount
            )
            .enumerated()
            .map { index, candidate in
                GraphChatPendingClarificationOption(
                    id: "option-\(index + 1)",
                    title:
                        "\(candidate.displayName) · \(index + 1)",
                    proposal:
                        .latestResults,
                    foundationalSelection: nil,
                    semanticSelection:
                        GraphChatSemanticIntentSelection(
                            draft:
                                clarification.draft,
                            selectedEntityID:
                                candidate.entityID,
                            selectedFields:
                                candidate
                                    .selectedFields,
                            selectedNodes:
                                candidate
                                    .selectedNodes
                        )
                )
            }
        let pending = GraphChatPendingClarification(
            id: requestID,
            decision: .semanticIntent,
            options: options,
            sourceTurnID: requestID,
            graphScope:
                providerPlan.scopeKey.graphScope,
            chatScope:
                providerPlan.scopeKey.chatScope,
            continuationOperation:
                .answerAboutReference,
            continuationQuestion:
                providerPlan.providerQuestion,
            createdAt: requestedAt,
            expiresAt:
                requestedAt
                    .addingTimeInterval(
                        GraphChatIntentLimitPolicy
                            .default.pendingClarificationLifetime
                    )
        )
        return GraphChatLocalTurnPlan(
            scopeKey: providerPlan.scopeKey,
            normalizedQuestion:
                providerPlan.normalizedQuestion,
            responseLanguage:
                providerPlan.responseLanguage,
            answer: GraphChatAnswer(
                state: .clarification(
                    GraphChatClarification(
                        id: pending.id,
                        question:
                            clarification.question,
                        options: options.map {
                            GraphChatClarificationOption(
                                id: $0.id,
                                title: $0.title
                            )
                        }
                    )
                ),
                directAnswer:
                    clarification.question,
                hasInsufficientEvidence: true
            ),
            baseState:
                providerPlan.requestBaseState,
            expectedCommittedState:
                providerPlan.expectedCommittedState,
            pendingClarification: pending
        )
    }

    private func mappedInterpreterError(
        _ error: Error
    ) -> GraphChatError {
        if let graphError = error as? GraphChatError {
            return graphError
        }
        if let interpreterError =
            error as? GraphChatIntentInterpreterError
        {
            let code: GraphChatErrorCode
            switch interpreterError.code {
            case .unavailable:
                code = .modelUnavailable
            case .contextWindowExceeded:
                code = .contextWindowExceeded
            case .unsupportedLanguage,
                .safetyGuardrail:
                code = .unavailable
            case .invalidOutput:
                code = .invalidRequest
            case .cancelled:
                code = .cancelled
            case .unexpected:
                code = .unexpected
            }
            return GraphChatError(
                code: code,
                message: interpreterError.message
            )
        }
        if let validationError =
            error
                as? GraphChatSemanticDraftValidationError
        {
            return GraphChatError(
                code: .invalidRequest,
                message:
                    validationError
                        .errorDescription
                    ?? "Der Semantic Draft wurde abgelehnt."
            )
        }
        return GraphChatError(
            code: .unexpected,
            message:
                "Die lokale Intent-Interpretation konnte nicht abgeschlossen werden."
        )
    }

    private func isCancellation(
        _ error: Error
    ) -> Bool {
        if error is CancellationError
            || Task.isCancelled
        {
            return true
        }
        return (
            error
                as? GraphChatIntentInterpreterError
        )?.code == .cancelled
    }

    private func record(
        _ event:
            GraphChatSemanticIntentLifecycleEvent,
        family: GraphChatSemanticIntentFamily?,
        interpreterCallCount: Int = 0,
        answerProviderCallCount: Int = 0
    ) async {
        await observability.record(
            .semanticIntent(
                GraphChatSemanticIntentMetric(
                    event: event,
                    family: family,
                    interpreterCallCount:
                        interpreterCallCount,
                    answerProviderCallCount:
                        answerProviderCallCount
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

    private func compilationEvent(
        for family: GraphChatSemanticIntentFamily,
        adaptation: GraphChatTypedIntentAdaptation
    ) -> GraphChatSemanticIntentLifecycleEvent {
        if case .queryDetailValues(let action) =
            adaptation.action,
           action.resultContract == .refinement {
            return .refinementIntentCompiled
        }
        switch family {
        case .findNodes:
            return .findIntentCompiled
        case .entityList:
            return .listIntentCompiled
        case .filteredCollection:
            return .filteredCollectionCompiled
        case .count:
            return .countIntentCompiled
        case .groupCount:
            return .groupIntentCompiled
        case .refinement:
            return .refinementIntentCompiled
        case .nodeDetails:
            return .nodeDetailsCompiled
        case .compareNodes:
            if case .compareNodes(let plan) =
                adaptation.action {
                return plan.kind
                    == .sameEntityAttributes
                    ? .sameEntityComparisonCompiled
                    : .structuralComparisonCompiled
            }
            return .comparisonRejected
        case .inspectGraphState:
            if case .inspectGraphState(
                let action
            ) = adaptation.action {
                return action.aspect == .health
                    ? .graphHealthCompiled
                    : .graphOverviewCompiled
            }
            return .graphOverviewCompiled
        case .unrecognized, .openEnded:
            return .legacyProviderFallback
        }
    }

    private func compilationRejectionEvent(
        for error: Error,
        family: GraphChatSemanticIntentFamily
    ) -> GraphChatSemanticIntentLifecycleEvent? {
        if let queryError =
            error
                as? GraphChatQueryIntentCompilationError
        {
            switch queryError {
            case .typeConflict:
                return .typeConflict
            case .valueParsingRejected:
                return .valueParsingRejected
            case .scopeExpansionPrevented:
                return .scopeExpansionPrevented
            case .staleResultSet:
                return .staleResultSetRejected
            case .unsupportedFamily, .entityNotFound,
                .staleSelection, .fieldNotFound,
                .fieldEntityMismatch,
                .projectionLimitExceeded,
                .invalidCompiledPlan:
                return nil
            }
        }
        if let semanticError =
            error
                as? GraphChatSemanticIntentResolutionError {
            switch semanticError {
            case .scopeViolation,
                .graphStateRequiresEntireGraph:
                return .scopeExpansionPrevented
            case .staleNodeSelection:
                return .staleNodeDiscarded
            case .comparisonLimitExceeded,
                .featureLimitExceeded,
                .unsupportedComparison:
                return .comparisonRejected
            case .unsupportedCombination,
                .nodeNotFound:
                return family == .compareNodes
                    ? .comparisonRejected
                    : nil
            case .entityNotFound,
                .staleEntitySelection,
                .conversationSelectionUnavailable,
                .conversationSelectionMismatch,
                .invalidSchemaIdentity:
                return nil
            }
        }
        return nil
    }
}
