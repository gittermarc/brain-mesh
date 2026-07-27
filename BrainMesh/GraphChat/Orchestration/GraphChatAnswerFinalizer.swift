//
//  GraphChatAnswerFinalizer.swift
//  BrainMesh
//
//  Final trust boundary for provider and local graph-chat answers.
//

import Foundation

nonisolated struct GraphChatProviderAnswerFinalizationInput: Sendable {
    let requestID: UUID
    let completedAt: Date
    let providerAnswer: GraphChatProviderFinalAnswer
    let conversationContext: GraphChatConversationContextSnapshot
    let responseLanguage: GraphChatResponseLanguage
    let continuationOperation: GraphChatConversationContinuationOperation?
    let requestQuestion: String
    let expectedCommittedState: GraphChatConversationState
    let primaryResult: GraphChatToolExecutionLedgerEntry?
    let authoritativeFactExpectation:
        GraphChatAuthoritativeFactExpectation?
    let artifactContext: GraphChatArtifactCommitContext
    let presentationRegistry: GraphChatPresentationRegistry
}

nonisolated struct GraphChatLocalAnswerFinalizationInput: Hashable, Sendable {
    let requestID: UUID
    let completedAt: Date
    let answer: GraphChatAnswer
    let baseState: GraphChatConversationState
    let expectedCommittedState: GraphChatConversationState
    let pendingClarification: GraphChatPendingClarification?
    let responseLanguage: GraphChatResponseLanguage
}

nonisolated struct GraphChatLocalIntentAnswerFinalizationInput:
    Sendable
{
    let requestID: UUID
    let completedAt: Date
    let requestQuestion: String
    let expectedCommittedState: GraphChatConversationState
    let execution: GraphChatLocalIntentPreparedExecution
}

nonisolated enum GraphChatAnswerFinalizationError:
    Error,
    Hashable,
    Sendable
{
    case missingAuthoritativeReferences
}

nonisolated struct GraphChatAnswerFinalizer: Sendable {
    private let conversationStateReducer: GraphChatConversationStateReducer
    private let referenceResolver: GraphChatConversationReferenceResolver
    private let missingContextPolicy: GraphChatReferenceMissingContextDeferPolicy
    private let localAnswerBuilder: GraphChatLocalAnswerBuilder
    private let evidenceValidator: any GraphEvidenceValidating
    private let commitCoordinator: GraphChatTurnCommitCoordinator
    private let presentationFirewall: GraphChatPresentationFirewall
    private let fallbackPolicy: GraphChatDeterministicAnswerFallbackPolicy
    private let fallbackRenderer: GraphChatDeterministicAnswerFallbackRenderer
    private let authoritativeFactExtractor:
        GraphChatAuthoritativeFactExtractor
    private let authoritativeFactRenderer:
        GraphChatAuthoritativeFactRenderer
    private let observability: any GraphChatObservabilityRecording

    init(
        conversationStateReducer: GraphChatConversationStateReducer =
            GraphChatConversationStateReducer(),
        referenceResolver: GraphChatConversationReferenceResolver =
            GraphChatConversationReferenceResolver(),
        missingContextPolicy: GraphChatReferenceMissingContextDeferPolicy =
            GraphChatReferenceMissingContextDeferPolicy(),
        localAnswerBuilder: GraphChatLocalAnswerBuilder =
            GraphChatLocalAnswerBuilder(),
        evidenceValidator: any GraphEvidenceValidating =
            GraphEvidenceSourceValidator.shared,
        commitCoordinator: GraphChatTurnCommitCoordinator =
            GraphChatTurnCommitCoordinator(),
        presentationFirewall: GraphChatPresentationFirewall =
            GraphChatPresentationFirewall(),
        fallbackPolicy: GraphChatDeterministicAnswerFallbackPolicy =
            GraphChatDeterministicAnswerFallbackPolicy(),
        fallbackRenderer: GraphChatDeterministicAnswerFallbackRenderer =
            GraphChatDeterministicAnswerFallbackRenderer(),
        authoritativeFactExtractor:
            GraphChatAuthoritativeFactExtractor =
                GraphChatAuthoritativeFactExtractor(),
        authoritativeFactRenderer:
            GraphChatAuthoritativeFactRenderer =
                GraphChatAuthoritativeFactRenderer(),
        observability: any GraphChatObservabilityRecording =
            NoOpGraphChatObservabilityRecorder()
    ) {
        self.conversationStateReducer = conversationStateReducer
        self.referenceResolver = referenceResolver
        self.missingContextPolicy = missingContextPolicy
        self.localAnswerBuilder = localAnswerBuilder
        self.evidenceValidator = evidenceValidator
        self.commitCoordinator = commitCoordinator
        self.presentationFirewall = presentationFirewall
        self.fallbackPolicy = fallbackPolicy
        self.fallbackRenderer = fallbackRenderer
        self.authoritativeFactExtractor =
            authoritativeFactExtractor
        self.authoritativeFactRenderer =
            authoritativeFactRenderer
        self.observability = observability
    }

    func finalizeProviderTurn(
        _ input: GraphChatProviderAnswerFinalizationInput,
        evidenceRegistry: GraphChatEvidenceRegistry,
        artifactRegistry: any GraphChatAnswerArtifactFinalizationRegistry,
        conversationTransaction: GraphChatConversationStateTransaction,
        currentCommittedState: GraphChatConversationState
    ) async throws -> GraphChatFinalizedTurn {
        let answer: GraphChatAnswer
        do {
            answer = try await validatedProviderAnswer(
                input,
                evidenceRegistry: evidenceRegistry,
                artifactRegistry: artifactRegistry,
                conversationTransaction: conversationTransaction
            )
        } catch {
            await commitCoordinator.rollback(
                input.artifactContext,
                artifactRegistry: artifactRegistry
            )
            throw error
        }
        return try await commitCoordinator.commit(
            GraphChatTurnCommitInput(
                requestID: input.requestID,
                completedAt: input.completedAt,
                source: .provider,
                answer: answer,
                expectedCommittedState: input.expectedCommittedState,
                artifactContext: input.artifactContext
            ),
            conversationTransaction: conversationTransaction,
            currentCommittedState: currentCommittedState,
            artifactRegistry: artifactRegistry
        )
    }

    func finalizeLocalTurn(
        _ input: GraphChatLocalAnswerFinalizationInput,
        currentCommittedState: GraphChatConversationState
    ) async throws -> GraphChatFinalizedTurn {
        let transaction = GraphChatConversationStateTransaction(
            baseState: input.baseState,
            reducer: conversationStateReducer
        )
        if let pendingClarification = input.pendingClarification {
            try await transaction.apply(
                GraphChatConversationTrustedEvent(
                    graphScope: input.baseState.graphScope,
                    chatScope: input.baseState.chatScope,
                    payload: .clarificationRequested(pendingClarification)
                )
            )
        }
        let validatedAnswer = try await validatedLocalAnswer(
            input.answer,
            in: input.baseState.chatScope
        )
        let registry = GraphChatValidatedPresentationRegistry(
            language: input.responseLanguage
        )
        let presentationContext = GraphChatPresentationContext(
            registry: registry,
            language: input.responseLanguage
        )
        let answer = try finalizedPresentation(
            for: validatedAnswer,
            source: nil,
            context: presentationContext
        )
        return try await commitCoordinator.commit(
            GraphChatTurnCommitInput(
                requestID: input.requestID,
                completedAt: input.completedAt,
                source: .local,
                answer: answer,
                expectedCommittedState: input.expectedCommittedState,
                artifactContext: nil
            ),
            conversationTransaction: transaction,
            currentCommittedState: currentCommittedState
        )
    }

    func finalizeLocalIntentTurn(
        _ input: GraphChatLocalIntentAnswerFinalizationInput,
        currentCommittedState: GraphChatConversationState
    ) async throws -> GraphChatFinalizedTurn {
        let execution = input.execution
        let providerInput = GraphChatProviderAnswerFinalizationInput(
            requestID: input.requestID,
            completedAt: input.completedAt,
            providerAnswer: GraphChatProviderFinalAnswer(
                responseState: .answer,
                directAnswer: "",
                sections: [],
                evidenceIDValues: execution.primaryResult.evidenceIDs.map {
                    $0.rawValue.uuidString
                },
                artifactIDValues:
                    execution.primaryResult.artifactIDs.map {
                        $0.rawValue.uuidString
                    },
                appliedFilters: [],
                followUpSuggestions: [],
                hasInsufficientEvidence: false
            ),
            conversationContext: execution.conversationContext,
            responseLanguage:
                execution.intent.responseLanguage,
            continuationOperation: nil,
            requestQuestion: input.requestQuestion,
            expectedCommittedState: input.expectedCommittedState,
            primaryResult: execution.primaryResult,
            authoritativeFactExpectation:
                execution.authoritativeFactExpectation,
            artifactContext: execution.artifactContext,
            presentationRegistry: execution.presentationRegistry
        )
        let answer: GraphChatAnswer
        do {
            answer = try await validatedProviderAnswer(
                providerInput,
                evidenceRegistry: execution.evidenceRegistry,
                artifactRegistry: execution.artifactRegistry,
                conversationTransaction:
                    execution.conversationTransaction
            )
        } catch {
            await commitCoordinator.rollback(
                execution.artifactContext,
                artifactRegistry: execution.artifactRegistry
            )
            throw error
        }
        return try await commitCoordinator.commit(
            GraphChatTurnCommitInput(
                requestID: input.requestID,
                completedAt: input.completedAt,
                source: .local,
                answer: answer,
                expectedCommittedState:
                    input.expectedCommittedState,
                artifactContext: execution.artifactContext
            ),
            conversationTransaction: execution.conversationTransaction,
            currentCommittedState: currentCommittedState,
            artifactRegistry: execution.artifactRegistry
        )
    }

    private func validatedProviderAnswer(
        _ input: GraphChatProviderAnswerFinalizationInput,
        evidenceRegistry: GraphChatEvidenceRegistry,
        artifactRegistry: any GraphChatAnswerArtifactFinalizationRegistry,
        conversationTransaction: GraphChatConversationStateTransaction
    ) async throws -> GraphChatAnswer {
        let answer = try await rawValidatedProviderAnswer(
            input,
            evidenceRegistry: evidenceRegistry,
            artifactRegistry: artifactRegistry,
            conversationTransaction: conversationTransaction
        )
        let registry = await input.presentationRegistry.snapshot()
        let presentationContext = GraphChatPresentationContext(
            registry: registry,
            language: input.responseLanguage
        )
        let primaryResult = validatedPrimaryResult(
            input.primaryResult,
            input: input
        )
        let source = GraphChatDeterministicAnswerFallbackSource(
            primaryResult: primaryResult,
            retaining: answer
        )
        if let expectation = input.authoritativeFactExpectation {
            return try await finalizedAuthoritativeFactPresentation(
                replacing: answer,
                expectation: expectation,
                primaryResult: primaryResult,
                source: source,
                context: presentationContext
            )
        }
        return try finalizedPresentation(
            for: answer,
            source: source,
            context: presentationContext
        )
    }

    private func finalizedAuthoritativeFactPresentation(
        replacing answer: GraphChatAnswer,
        expectation: GraphChatAuthoritativeFactExpectation,
        primaryResult: GraphChatToolExecutionLedgerEntry?,
        source: GraphChatDeterministicAnswerFallbackSource?,
        context: GraphChatPresentationContext
    ) async throws -> GraphChatAnswer {
        try Task.checkCancellation()
        let resolution = authoritativeFactExtractor.resolve(
            expectation: expectation,
            primaryResult: primaryResult,
            source: source
        )
        switch resolution {
        case .fact(let fact):
            await observability.record(
                .authoritativeFact(.recognized)
            )
            let text = authoritativeFactRenderer.render(
                fact,
                language: context.language
            )
            let candidate = GraphChatAnswer(
                state: .answer,
                directAnswer: text,
                sections: [],
                evidence: answer.evidence,
                artifactIDs: answer.artifactIDs,
                appliedFilters: source?.appliedFilters ?? [],
                followUpSuggestions: [],
                hasInsufficientEvidence: false,
                presentationContext: context
            )
            switch presentationFirewall.present(
                candidate,
                context: context
            ) {
            case .safe(let safeAnswer):
                await observability.record(
                    .authoritativeFact(.rendered)
                )
                if answer.directAnswer != safeAnswer.directAnswer
                    || answer.sections.isEmpty == false
                    || answer.followUpSuggestions.isEmpty == false {
                    await observability.record(
                        .authoritativeFact(.replacedModelText)
                    )
                }
                return safeAnswer
            case .unsafe:
                await observability.record(
                    .authoritativeFact(.rejectedRevalidation)
                )
                return insufficientFactAnswer(
                    replacing: answer,
                    source: source,
                    context: context
                )
            }

        case .rejected(let rejection):
            await observability.record(
                .authoritativeFact(
                    observabilityMetric(for: rejection)
                )
            )
            return insufficientFactAnswer(
                replacing: answer,
                source: source,
                context: context
            )
        }
    }

    private func insufficientFactAnswer(
        replacing answer: GraphChatAnswer,
        source: GraphChatDeterministicAnswerFallbackSource?,
        context: GraphChatPresentationContext
    ) -> GraphChatAnswer {
        GraphChatAnswer(
            state: .noResults,
            directAnswer: GraphChatResponseLocalizer(
                language: context.language
            ).authoritativeFactUnavailable(),
            sections: [],
            evidence: answer.evidence,
            artifactIDs: answer.artifactIDs,
            appliedFilters: source?.appliedFilters ?? [],
            followUpSuggestions: [],
            hasInsufficientEvidence: true,
            presentationContext: context
        )
    }

    private func observabilityMetric(
        for rejection: GraphChatAuthoritativeFactRejection
    ) -> GraphChatAuthoritativeFactMetric {
        switch rejection {
        case .missingValue:
            return .rejectedMissingValue
        case .ambiguousCardinality:
            return .rejectedAmbiguousCardinality
        case .integrityConflict:
            return .rejectedIntegrityConflict
        case .revalidationRejected:
            return .rejectedRevalidation
        case .searchOnlyResult:
            return .blockedSearchOnlyClaim
        }
    }

    private func finalizedPresentation(
        for answer: GraphChatAnswer,
        source: GraphChatDeterministicAnswerFallbackSource?,
        context: GraphChatPresentationContext
    ) throws -> GraphChatAnswer {
        try Task.checkCancellation()
        switch presentationFirewall.present(
            answer,
            context: context
        ) {
        case .safe(let safeAnswer):
            return try finalizedSafeAnswer(
                safeAnswer,
                source: source,
                context: context
            )
        case .unsafe:
            return try typedFallbackAnswer(
                replacing: answer,
                source: source,
                context: context,
                unsafePresentation: true
            )
        }
    }

    private func finalizedSafeAnswer(
        _ answer: GraphChatAnswer,
        source: GraphChatDeterministicAnswerFallbackSource?,
        context: GraphChatPresentationContext
    ) throws -> GraphChatAnswer {
        guard answer.state == .answer else {
            return answer
        }

        if let source, source.completionStatus == .succeeded {
            guard source.hasAuthoritativeReferences,
                  (
                    answer.evidence.isEmpty == false
                        || answer.artifactIDs.isEmpty == false
                  ) else {
                throw GraphChatAnswerFinalizationError
                    .missingAuthoritativeReferences
            }
            if fallbackPolicy.fallbackReason(
                for: answer,
                source: source
            ) != nil {
                return try typedFallbackAnswer(
                    replacing: answer,
                    source: source,
                    context: context,
                    unsafePresentation: false
                )
            }
            return answer
        }

        guard answer.directAnswer.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return answer
        }
        return try typedFallbackAnswer(
            replacing: answer,
            source: nil,
            context: context,
            unsafePresentation: false
        )
    }

    private func typedFallbackAnswer(
        replacing answer: GraphChatAnswer,
        source: GraphChatDeterministicAnswerFallbackSource?,
        context: GraphChatPresentationContext,
        unsafePresentation: Bool
    ) throws -> GraphChatAnswer {
        try Task.checkCancellation()
        let localizer = GraphChatResponseLocalizer(
            language: context.language
        )

        switch answer.state {
        case .answer:
            let text: String
            if let source, source.completionStatus == .succeeded {
                guard source.hasAuthoritativeReferences,
                      (
                        answer.evidence.isEmpty == false
                            || answer.artifactIDs.isEmpty == false
                      ) else {
                    throw GraphChatAnswerFinalizationError
                        .missingAuthoritativeReferences
                }
                let rendered = fallbackRenderer.render(
                    source: source,
                    language: context.language
                )
                text = fallbackPolicy.containsTechnicalPresentation(rendered)
                    ? fallbackRenderer.genericValidatedResult(
                        language: context.language
                    )
                    : rendered
            } else {
                text = unsafePresentation
                    ? localizer.unsafePresentation()
                    : localizer.answerUnavailable()
            }
            return presentationSafeFallbackAnswer(
                text: text,
                replacing: answer,
                source: source,
                context: context
            )

        case .noResults:
            return GraphChatAnswer(
                state: .noResults,
                directAnswer: localizer.noResults(),
                evidence: answer.evidence,
                artifactIDs: answer.artifactIDs,
                hasInsufficientEvidence: true,
                presentationContext: context
            )

        case .unsupported(let capability):
            return GraphChatAnswer(
                state: .unsupported(capability),
                directAnswer: localizer.unsupported(capability),
                hasInsufficientEvidence: false,
                presentationContext: context
            )

        case .clarification(let clarification):
            let options = clarification.options.compactMap { option in
                switch presentationFirewall.present(
                    option.title,
                    using: context.registry
                ) {
                case .safe(let title):
                    return GraphChatClarificationOption(
                        id: option.id,
                        title: title
                    )
                case .unsafe:
                    return nil
                }
            }
            let question = localizer.clarificationQuestion(
                reason: .ambiguous
            )
            return GraphChatAnswer(
                state: .clarification(
                    GraphChatClarification(
                        id: clarification.id,
                        question: question,
                        options: options
                    )
                ),
                directAnswer: question,
                hasInsufficientEvidence: true,
                presentationContext: context
            )
        }
    }

    private func presentationSafeFallbackAnswer(
        text: String,
        replacing answer: GraphChatAnswer,
        source: GraphChatDeterministicAnswerFallbackSource?,
        context: GraphChatPresentationContext
    ) -> GraphChatAnswer {
        let candidate = GraphChatAnswer(
            state: .answer,
            directAnswer: text,
            evidence: answer.evidence,
            artifactIDs: answer.artifactIDs,
            appliedFilters: source?.appliedFilters ?? [],
            hasInsufficientEvidence: answer.evidence.isEmpty
                && answer.artifactIDs.isEmpty,
            presentationContext: context
        )
        switch presentationFirewall.present(
            candidate,
            context: context
        ) {
        case .safe(let safeAnswer):
            return safeAnswer
        case .unsafe:
            let genericText: String
            if source?.hasAuthoritativeReferences == true {
                genericText = fallbackRenderer.genericValidatedResult(
                    language: context.language
                )
            } else {
                genericText = GraphChatResponseLocalizer(
                    language: context.language
                ).unsafePresentation()
            }
            return GraphChatAnswer(
                state: .answer,
                directAnswer: genericText,
                evidence: answer.evidence,
                artifactIDs: answer.artifactIDs,
                hasInsufficientEvidence: answer.evidence.isEmpty
                    && answer.artifactIDs.isEmpty,
                presentationContext: context
            )
        }
    }

    private func rawValidatedProviderAnswer(
        _ input: GraphChatProviderAnswerFinalizationInput,
        evidenceRegistry: GraphChatEvidenceRegistry,
        artifactRegistry: any GraphChatAnswerArtifactFinalizationRegistry,
        conversationTransaction: GraphChatConversationStateTransaction
    ) async throws -> GraphChatAnswer {
        try validateInputScopes(input)
        let providerAnswer = input.providerAnswer
        let primaryResult = validatedPrimaryResult(input.primaryResult, input: input)
        let responseState = authoritativeResponseState(
            providerState: providerAnswer.responseState,
            primaryResult: primaryResult
        )
        let primaryArtifactIDValues = primaryResult.map {
            $0.artifactIDs.map { $0.rawValue.uuidString }
        } ?? []
        let requestedArtifactIDValues = primaryArtifactIDValues
            + providerAnswer.artifactIDValues
            + providerAnswer.sections.flatMap(\.artifactIDValues)
        let registryArtifacts = try await artifactRegistry.validatedArtifacts(
            for: requestedArtifactIDValues,
            graphScope: input.artifactContext.graphScope,
            sessionID: input.artifactContext.sessionID,
            transactionID: input.artifactContext.transactionID
        )

        let primaryEvidenceIDValues = primaryResult.map {
            $0.evidenceIDs.map { $0.rawValue.uuidString }
        } ?? []
        let rootRegisteredEvidence = await evidenceRegistry.validatedEvidence(
            for: primaryEvidenceIDValues + providerAnswer.evidenceIDValues
        )
        let artifactRegisteredEvidence = await evidenceRegistry.evidence(
            for: registryArtifacts.flatMap(\.allEvidenceIDs)
        )
        var sectionRegisteredEvidence: [[GraphEvidence]] = []
        sectionRegisteredEvidence.reserveCapacity(providerAnswer.sections.count)
        for section in providerAnswer.sections {
            sectionRegisteredEvidence.append(
                await evidenceRegistry.validatedEvidence(
                    for: section.evidenceIDValues
                )
            )
        }

        let liveEvidence = try await evidenceValidator.validatedEvidence(
            GraphEvidenceCollection(
                rootRegisteredEvidence
                    + artifactRegisteredEvidence
                    + sectionRegisteredEvidence.flatMap { $0 }
            ).values,
            in: input.conversationContext.chatScope
        )
        let liveEvidenceIDs = Set(liveEvidence.map(\.id))
        let liveEvidenceByID = Dictionary(
            uniqueKeysWithValues: liveEvidence.map { ($0.id, $0) }
        )
        let artifacts = registryArtifacts.filter {
            Set($0.allEvidenceIDs).isSubset(of: liveEvidenceIDs)
        }
        await input.presentationRegistry.registerValidatedArtifacts(
            artifacts
        )
        let artifactsByID = Dictionary(
            uniqueKeysWithValues: artifacts.map { ($0.id, $0) }
        )

        var finalEvidenceCandidates = rootRegisteredEvidence
        finalEvidenceCandidates.append(
            contentsOf: await artifactEvidence(
                artifacts,
                evidenceRegistry: evidenceRegistry
            )
        )
        var sections: [GraphChatAnswerSection] = []
        sections.reserveCapacity(providerAnswer.sections.count)

        for (index, section) in providerAnswer.sections.enumerated() {
            let sectionArtifactIDs = validatedArtifactIDs(
                from: section.artifactIDValues,
                artifactsByID: artifactsByID
            )
            let sectionArtifactEvidence = await evidenceRegistry.evidence(
                for: sectionArtifactIDs.flatMap {
                    artifactsByID[$0]?.allEvidenceIDs ?? []
                }
            )
            let sectionEvidenceCandidates = GraphEvidenceCollection(
                sectionRegisteredEvidence[index] + sectionArtifactEvidence
            ).values
            let sectionEvidence = sectionEvidenceCandidates.compactMap {
                liveEvidenceByID[$0.id]
            }
            finalEvidenceCandidates.append(contentsOf: sectionEvidence)
            sections.append(
                GraphChatAnswerSection(
                    title: section.title,
                    text: section.text,
                    evidenceIDs: sectionEvidence.map(\.id),
                    artifactIDs: sectionArtifactIDs,
                    querySummary: sectionArtifactIDs.compactMap {
                        artifactsByID[$0]?.querySummary
                    }.first,
                    state: sectionAnswerState(for: responseState)
                )
            )
        }

        let finalEvidence = GraphEvidenceCollection(
            finalEvidenceCandidates.compactMap {
                liveEvidenceByID[$0.id]
            }
        ).values
        await input.presentationRegistry.registerValidatedEvidence(
            finalEvidence
        )
        let deterministicFilters = await evidenceRegistry.filtersForAnswer()
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
        let localizer = GraphChatResponseLocalizer(
            language: input.responseLanguage
        )
        let candidateState = await conversationTransaction.snapshot()
        let latestToolState = candidateState.resultContexts.last?.state

        switch responseState {
        case .answer:
            if primaryResult == nil,
               let proposal = providerAnswer.referenceProposal {
                let resolution = try await referenceResolver.resolve(
                    proposal,
                    in: input.conversationContext,
                    expectedGraphScope: input.conversationContext.graphScope,
                    expectedChatScope: input.conversationContext.chatScope
                )
                if case .resolved = resolution {
                    // The app-side resolver has revalidated the proposal.
                } else if missingContextPolicy.shouldIgnoreUnresolvedProviderProposal(
                    resolution,
                    directAnswer: providerAnswer.directAnswer
                ) {
                    // A usable direct answer wins over a non-binding missing-context proposal.
                } else {
                    let fallback = localAnswerBuilder.referenceResolution(
                        resolution,
                        language: input.responseLanguage,
                        operation: input.continuationOperation ?? .answerAboutReference,
                        state: candidateState,
                        sourceTurnID: candidateState.turnContexts.last?.id,
                        continuationQuestion: input.requestQuestion,
                        clarificationID: input.requestID,
                        referenceDate: input.completedAt
                    )
                    try await applyPendingClarification(
                        fallback.pendingClarification,
                        transaction: conversationTransaction,
                        context: input.conversationContext
                    )
                    return fallback.answer
                }
            }
            return GraphChatAnswer(
                state: .answer,
                directAnswer: providerAnswer.directAnswer,
                sections: sections,
                evidence: finalEvidence,
                artifactIDs: artifacts.map(\.id),
                appliedFilters: filters,
                followUpSuggestions: followUps,
                hasInsufficientEvidence: providerAnswer.hasInsufficientEvidence
                    || finalEvidence.isEmpty
            )

        case .noResults:
            guard primaryResult?.completionStatus == .noResults
                    || latestToolState == .noResults else {
                return GraphChatAnswer(
                    state: .answer,
                    directAnswer: providerAnswer.directAnswer,
                    sections: sections,
                    evidence: finalEvidence,
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
                evidence: finalEvidence,
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
                artifactIDs: [],
                appliedFilters: [],
                followUpSuggestions: [],
                hasInsufficientEvidence: false
            )

        case .clarification:
            let options = try await validatedClarificationOptions(
                providerAnswer: providerAnswer,
                context: input.conversationContext
            )
            let normalizedQuestion = providerAnswer.clarificationQuestion?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let question =
                normalizedQuestion?.isEmpty == false
                ? normalizedQuestion!
                : localizer.clarificationQuestion(reason: .ambiguous)
            let pending = localAnswerBuilder.makePendingClarification(
                id: input.requestID,
                options: options,
                operation: input.continuationOperation ?? .answerAboutReference,
                state: candidateState,
                continuationQuestion: input.requestQuestion,
                referenceDate: input.completedAt
            )
            try await applyPendingClarification(
                pending,
                transaction: conversationTransaction,
                context: input.conversationContext
            )
            return GraphChatAnswer(
                state: .clarification(
                    GraphChatClarification(
                        id: pending?.id ?? input.requestID,
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
                sections: [],
                evidence: [],
                artifactIDs: [],
                appliedFilters: [],
                followUpSuggestions: [],
                hasInsufficientEvidence: true
            )
        }
    }

    private func validatedLocalAnswer(
        _ answer: GraphChatAnswer,
        in scope: GraphChatScope
    ) async throws -> GraphChatAnswer {
        if case .unsupported(let capability) = answer.state {
            let text = answer.directAnswer.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return GraphChatAnswer(
                state: .unsupported(capability),
                directAnswer: text,
                hasInsufficientEvidence: false
            )
        }

        let evidence = try await evidenceValidator.validatedEvidence(
            answer.evidence,
            in: scope
        )
        let evidenceIDs = Set(evidence.map(\.id))
        let sections = answer.sections.map { section in
            GraphChatAnswerSection(
                id: section.id,
                title: section.title,
                text: section.text,
                evidenceIDs: section.evidenceIDs.filter {
                    evidenceIDs.contains($0)
                },
                artifactIDs: [],
                querySummary: nil,
                state: section.state
            )
        }
        return GraphChatAnswer(
            state: answer.state,
            directAnswer: answer.directAnswer,
            sections: sections,
            evidence: evidence,
            artifactIDs: [],
            appliedFilters: answer.appliedFilters,
            followUpSuggestions: answer.followUpSuggestions,
            hasInsufficientEvidence: answer.hasInsufficientEvidence
                || (answer.evidence.isEmpty == false && evidence.isEmpty)
        )
    }

    private func validatedClarificationOptions(
        providerAnswer: GraphChatProviderFinalAnswer,
        context: GraphChatConversationContextSnapshot
    ) async throws -> [GraphChatPendingClarificationOption] {
        var options: [GraphChatPendingClarificationOption] = []
        var seen = Set<String>()

        for rawAlias in providerAnswer.clarificationOptionAliases {
            guard options.count < 8,
                  let alias = context.alias(rawAlias) else {
                continue
            }
            let resolution = try await referenceResolver.resolve(
                .alias(alias.alias),
                in: context,
                expectedGraphScope: context.graphScope,
                expectedChatScope: context.chatScope
            )
            guard case .resolved = resolution,
                  seen.insert(alias.alias).inserted else {
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
                options = try await revalidatedClarificationOptions(
                    clarification.options,
                    context: context
                )
            }
        }
        return Array(options.prefix(8))
    }

    private func revalidatedClarificationOptions(
        _ candidates: [GraphChatPendingClarificationOption],
        context: GraphChatConversationContextSnapshot
    ) async throws -> [GraphChatPendingClarificationOption] {
        var result: [GraphChatPendingClarificationOption] = []
        var seen = Set<String>()
        for candidate in candidates {
            guard result.count < 8,
                  seen.insert(candidate.id).inserted else {
                continue
            }
            let resolution = try await referenceResolver.resolve(
                candidate.proposal,
                in: context,
                expectedGraphScope: context.graphScope,
                expectedChatScope: context.chatScope
            )
            guard case .resolved = resolution else {
                continue
            }
            result.append(candidate)
        }
        return result
    }

    private func artifactEvidence(
        _ artifacts: [GraphChatAnswerArtifact],
        evidenceRegistry: GraphChatEvidenceRegistry
    ) async -> [GraphEvidence] {
        await evidenceRegistry.evidence(
            for: artifacts.flatMap(\.allEvidenceIDs)
        )
    }

    private func applyPendingClarification(
        _ pending: GraphChatPendingClarification?,
        transaction: GraphChatConversationStateTransaction,
        context: GraphChatConversationContextSnapshot
    ) async throws {
        guard let pending else {
            return
        }
        try await transaction.apply(
            GraphChatConversationTrustedEvent(
                graphScope: context.graphScope,
                chatScope: context.chatScope,
                payload: .clarificationRequested(pending)
            )
        )
    }

    private func validateInputScopes(
        _ input: GraphChatProviderAnswerFinalizationInput
    ) throws {
        guard input.conversationContext.graphScope == input.artifactContext.graphScope,
              input.conversationContext.chatScope == input.artifactContext.chatScope,
              input.expectedCommittedState.graphScope == input.artifactContext.graphScope,
              input.expectedCommittedState.chatScope == input.artifactContext.chatScope else {
            throw GraphChatTurnCommitError.artifactContextMismatch
        }
    }

    private func validatedPrimaryResult(
        _ candidate: GraphChatToolExecutionLedgerEntry?,
        input: GraphChatProviderAnswerFinalizationInput
    ) -> GraphChatToolExecutionLedgerEntry? {
        guard let candidate,
              candidate.isEligibleAsPrimary,
              candidate.kind == GraphChatPrimaryResultKind(tool: candidate.tool),
              candidate.belongsTo(
                requestID: input.requestID,
                graphScope: input.artifactContext.graphScope,
                chatScope: input.artifactContext.chatScope,
                artifactSessionID: input.artifactContext.sessionID,
                transactionID: input.artifactContext.transactionID
              ),
              candidate.evidence.allSatisfy({
                  $0.sourceReference.graphID
                      == input.artifactContext.graphScope.graphID
              }),
              candidate.artifacts.allSatisfy({
                  $0.graphScope == input.artifactContext.graphScope
                      && $0.sessionID == input.artifactContext.sessionID
              }) else {
            return nil
        }

        switch candidate.completionStatus {
        case .succeeded:
            guard candidate.metadata.resultState == .success,
                  candidate.hasAuthoritativeReferences else {
                return nil
            }
        case .noResults:
            guard candidate.metadata.resultState == .noResults else {
                return nil
            }
        case .unverified:
            return nil
        }
        return candidate
    }

    private func authoritativeResponseState(
        providerState: GraphChatProviderResponseState,
        primaryResult: GraphChatToolExecutionLedgerEntry?
    ) -> GraphChatProviderResponseState {
        guard let primaryResult else {
            return providerState
        }
        switch primaryResult.completionStatus {
        case .succeeded:
            return .answer
        case .noResults:
            return .noResults
        case .unverified:
            return providerState
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
            guard artifactsByID[id] != nil,
                  seen.insert(id).inserted else {
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
}
