//
//  GraphChatAnswerFinalizer.swift
//  BrainMesh
//
//  Final trust boundary for provider and local graph-chat answers.
//

import Foundation

nonisolated struct GraphChatProviderAnswerFinalizationInput: Hashable, Sendable {
    let requestID: UUID
    let completedAt: Date
    let providerAnswer: GraphChatProviderFinalAnswer
    let conversationContext: GraphChatConversationContextSnapshot
    let responseLanguage: GraphChatResponseLanguage
    let continuationOperation: GraphChatConversationContinuationOperation?
    let requestQuestion: String
    let expectedCommittedState: GraphChatConversationState
    let artifactContext: GraphChatArtifactCommitContext
}

nonisolated struct GraphChatLocalAnswerFinalizationInput: Hashable, Sendable {
    let requestID: UUID
    let completedAt: Date
    let answer: GraphChatAnswer
    let baseState: GraphChatConversationState
    let expectedCommittedState: GraphChatConversationState
    let pendingClarification: GraphChatPendingClarification?
}

nonisolated struct GraphChatAnswerFinalizer: Sendable {
    private let conversationStateReducer: GraphChatConversationStateReducer
    private let referenceResolver: GraphChatConversationReferenceResolver
    private let missingContextPolicy: GraphChatReferenceMissingContextDeferPolicy
    private let localAnswerBuilder: GraphChatLocalAnswerBuilder
    private let evidenceValidator: any GraphEvidenceValidating
    private let commitCoordinator: GraphChatTurnCommitCoordinator

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
            GraphChatTurnCommitCoordinator()
    ) {
        self.conversationStateReducer = conversationStateReducer
        self.referenceResolver = referenceResolver
        self.missingContextPolicy = missingContextPolicy
        self.localAnswerBuilder = localAnswerBuilder
        self.evidenceValidator = evidenceValidator
        self.commitCoordinator = commitCoordinator
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
        let answer = try await validatedLocalAnswer(
            input.answer,
            in: input.baseState.chatScope
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

    private func validatedProviderAnswer(
        _ input: GraphChatProviderAnswerFinalizationInput,
        evidenceRegistry: GraphChatEvidenceRegistry,
        artifactRegistry: any GraphChatAnswerArtifactFinalizationRegistry,
        conversationTransaction: GraphChatConversationStateTransaction
    ) async throws -> GraphChatAnswer {
        try validateInputScopes(input)
        let providerAnswer = input.providerAnswer
        let requestedArtifactIDValues = providerAnswer.artifactIDValues
            + providerAnswer.sections.flatMap(\.artifactIDValues)
        let registryArtifacts = try await artifactRegistry.validatedArtifacts(
            for: requestedArtifactIDValues,
            graphScope: input.artifactContext.graphScope,
            sessionID: input.artifactContext.sessionID,
            transactionID: input.artifactContext.transactionID
        )

        let rootRegisteredEvidence = await evidenceRegistry.validatedEvidence(
            for: providerAnswer.evidenceIDValues
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
                    state: sectionAnswerState(for: providerAnswer.responseState)
                )
            )
        }

        let finalEvidence = GraphEvidenceCollection(
            finalEvidenceCandidates.compactMap {
                liveEvidenceByID[$0.id]
            }
        ).values
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

        switch providerAnswer.responseState {
        case .answer:
            if let proposal = providerAnswer.referenceProposal {
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
            guard latestToolState == .noResults else {
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
