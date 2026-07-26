import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph chat answer finalizer")
struct GraphChatAnswerFinalizerTests {
    @Test
    func registeredEvidenceIsRetainedInventedEvidenceIsRemovedAndDuplicatesAreStable() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(1)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let inventedID = GraphEvidenceID(rawValue: fixture.uuid(900))
        let providerAnswer = fixture.providerAnswer(
            evidenceIDs: [evidence.id, inventedID, evidence.id]
        )

        let turn = try await fixture.finalize(
            providerAnswer,
            resources: resources
        )

        #expect(turn.answer.evidence == [evidence])
        #expect(turn.answer.evidenceIDs == [evidence.id])
        #expect(turn.conversationState.turnContexts.last?.evidenceIDs == [evidence.id])
    }

    @Test
    func registeredButNoLongerRevalidatedEvidenceIsRemoved() async throws {
        let fixture = AnswerFinalizerFixture()
        let retained = fixture.makeEvidence(11)
        let invalidated = fixture.makeEvidence(12)
        let resources = try await fixture.makeResources(
            evidence: [retained, invalidated]
        )
        let invalidatedArtifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: invalidated.id
        )
        let answerFinalizer = fixture.makeFinalizer(
            evidenceValidator: AnswerFinalizerAllowListEvidenceValidator(
                allowedIDs: [retained.id]
            )
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(
                evidenceIDs: [retained.id, invalidated.id],
                artifactIDs: [invalidatedArtifactID]
            ),
            resources: resources,
            answerFinalizer: answerFinalizer
        )

        #expect(turn.answer.evidence == [retained])
        #expect(turn.answer.artifactIDs.isEmpty)
        #expect(turn.committedArtifactIDs.isEmpty)
        #expect(turn.conversationState.turnContexts.last?.evidenceIDs == [retained.id])
    }

    @Test
    func registeredArtifactsAreRetainedWhileInventedAndDuplicateIDsAreRemoved() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(2)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let artifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: evidence.id
        )
        let inventedID = GraphChatAnswerArtifactID(rawValue: fixture.uuid(901))
        let providerAnswer = fixture.providerAnswer(
            artifactIDs: [artifactID, inventedID, artifactID]
        )

        let turn = try await fixture.finalize(
            providerAnswer,
            resources: resources
        )

        #expect(turn.answer.artifactIDs == [artifactID])
        #expect(turn.committedArtifactIDs == [artifactID])
        #expect(await resources.artifactRegistry.snapshotForTesting().map(\.id) == [artifactID])
    }

    @Test
    func foreignArtifactSessionIsRejectedAndItsTransactionIsRolledBack() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(3)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let artifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: evidence.id
        )
        let foreignContext = GraphChatArtifactCommitContext(
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            sessionID: GraphChatAnswerArtifactSessionID(rawValue: fixture.uuid(902)),
            transactionID: resources.artifactContext.transactionID
        )

        await #expect(throws: GraphChatAnswerArtifactRegistryError.sessionMismatch) {
            _ = try await fixture.finalize(
                fixture.providerAnswer(artifactIDs: [artifactID]),
                resources: resources,
                artifactContext: foreignContext
            )
        }
        #expect(
            await resources.artifactRegistry.stagedSnapshotForTesting(
                transactionID: resources.artifactContext.transactionID
            ).isEmpty
        )
        #expect(await resources.artifactRegistry.snapshotForTesting().isEmpty)
    }

    @Test
    func artifactFromAnotherTransactionCannotReachTheAnswer() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(4)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let artifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: evidence.id
        )
        let foreignTransactionID = GraphChatAnswerArtifactTransactionID(
            rawValue: fixture.uuid(903)
        )
        let foreignContext = GraphChatArtifactCommitContext(
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            sessionID: resources.artifactContext.sessionID,
            transactionID: foreignTransactionID
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(artifactIDs: [artifactID]),
            resources: resources,
            artifactContext: foreignContext
        )

        #expect(turn.answer.artifactIDs.isEmpty)
        #expect(turn.committedArtifactIDs.isEmpty)
        #expect(await resources.artifactRegistry.snapshotForTesting().isEmpty)
        #expect(
            await resources.artifactRegistry.stagedSnapshotForTesting(
                transactionID: resources.artifactContext.transactionID
            ).map(\.id) == [artifactID]
        )
    }

    @Test
    func sectionEvidenceArtifactsAndQuerySummaryAreValidatedIndependently() async throws {
        let fixture = AnswerFinalizerFixture()
        let rootEvidence = fixture.makeEvidence(5)
        let sectionEvidence = fixture.makeEvidence(6)
        let artifactEvidence = fixture.makeEvidence(7)
        let resources = try await fixture.makeResources(
            evidence: [rootEvidence, sectionEvidence, artifactEvidence]
        )
        let querySummary = fixture.querySummary()
        let artifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: artifactEvidence.id,
            querySummary: querySummary
        )
        let inventedEvidenceID = GraphEvidenceID(rawValue: fixture.uuid(904))
        let inventedArtifactID = GraphChatAnswerArtifactID(rawValue: fixture.uuid(905))
        let section = GraphChatProviderAnswerSection(
            title: "Details",
            text: "Validated section",
            evidenceIDValues: [
                sectionEvidence.id.rawValue.uuidString,
                inventedEvidenceID.rawValue.uuidString,
            ],
            artifactIDValues: [
                inventedArtifactID.rawValue.uuidString,
                artifactID.rawValue.uuidString,
                artifactID.rawValue.uuidString,
            ]
        )
        let providerAnswer = fixture.providerAnswer(
            sections: [section],
            evidenceIDs: [rootEvidence.id]
        )

        let turn = try await fixture.finalize(
            providerAnswer,
            resources: resources
        )
        let finalizedSection = try #require(turn.answer.sections.first)

        #expect(finalizedSection.evidenceIDs == [sectionEvidence.id, artifactEvidence.id])
        #expect(finalizedSection.artifactIDs == [artifactID])
        #expect(finalizedSection.querySummary == querySummary)
        #expect(
            turn.answer.evidenceIDs
                == [rootEvidence.id, artifactEvidence.id, sectionEvidence.id]
        )
        #expect(turn.answer.artifactIDs == [artifactID])
    }

    @Test
    func querySummaryIsRemovedWhenNoValidatedSectionArtifactRemains() async throws {
        let fixture = AnswerFinalizerFixture()
        let resources = try await fixture.makeResources()
        let inventedArtifactID = GraphChatAnswerArtifactID(rawValue: fixture.uuid(906))
        let providerAnswer = fixture.providerAnswer(
            sections: [
                GraphChatProviderAnswerSection(
                    title: "Invented",
                    text: "No registered artifact",
                    evidenceIDValues: [],
                    artifactIDValues: [inventedArtifactID.rawValue.uuidString]
                )
            ]
        )

        let turn = try await fixture.finalize(
            providerAnswer,
            resources: resources
        )

        #expect(turn.answer.sections.first?.artifactIDs.isEmpty == true)
        #expect(turn.answer.sections.first?.querySummary == nil)
    }

    @Test
    func deterministicFiltersWinAndProviderFiltersRemainTheFallback() async throws {
        let fixture = AnswerFinalizerFixture()
        let deterministic = GraphChatAppliedFilter(
            fieldName: "Status",
            operationDescription: "equals",
            valueDescription: "Active"
        )
        let resources = try await fixture.makeResources()
        try await resources.evidenceRegistry.registerAppliedFilters([deterministic])
        let providerFilter = GraphChatProviderAppliedFilter(
            fieldName: "Priority",
            operationDescription: "equals",
            valueDescription: "High"
        )
        let providerAnswer = fixture.providerAnswer(
            appliedFilters: [providerFilter],
            followUps: [
                GraphChatProviderFollowUpSuggestion(
                    title: "First",
                    prompt: "First prompt"
                ),
                GraphChatProviderFollowUpSuggestion(
                    title: "Second",
                    prompt: "Second prompt"
                ),
            ]
        )

        let deterministicTurn = try await fixture.finalize(
            providerAnswer,
            resources: resources
        )
        #expect(deterministicTurn.answer.appliedFilters == [deterministic])

        let fallbackResources = try await fixture.makeResources()
        let fallbackTurn = try await fixture.finalize(
            providerAnswer,
            resources: fallbackResources
        )
        #expect(fallbackTurn.answer.appliedFilters.map(\.fieldName) == ["Priority"])
        #expect(
            fallbackTurn.answer.appliedFilters.map(\.operationDescription)
                == ["equals"]
        )
        #expect(fallbackTurn.answer.appliedFilters.first?.valueDescription == "High")
        #expect(fallbackTurn.answer.followUpSuggestions.map(\.title) == ["First", "Second"])
        #expect(
            fallbackTurn.answer.followUpSuggestions.map(\.prompt)
                == ["First prompt", "Second prompt"]
        )
    }

    @Test
    func noResultsRequiresTheLatestTrustedNoResultToolState() async throws {
        let fixture = AnswerFinalizerFixture()
        let trustedResources = try await fixture.makeResources()
        try await trustedResources.conversationTransaction.apply(
            GraphChatConversationTrustedEvent(
                graphScope: fixture.graphScope,
                chatScope: fixture.chatScope,
                payload: .validatedEvidence(
                    tool: .searchGraph,
                    state: .noResults,
                    evidence: []
                )
            )
        )
        let noResults = fixture.providerAnswer(
            responseState: .noResults,
            directAnswer: ""
        )

        let trustedTurn = try await fixture.finalize(
            noResults,
            resources: trustedResources
        )
        #expect(trustedTurn.answer.state == .noResults)
        #expect(
            trustedTurn.answer.directAnswer
                == GraphChatResponseLocalizer(language: .english).noResults()
        )

        let untrustedResources = try await fixture.makeResources()
        let downgradedTurn = try await fixture.finalize(
            noResults,
            resources: untrustedResources
        )
        #expect(downgradedTurn.answer.state == .answer)
        #expect(downgradedTurn.answer.hasInsufficientEvidence)
    }

    @Test
    func unsupportedStripsAllTrustedDataAndLocalizesAnEmptyAnswer() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(8)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let artifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: evidence.id
        )
        let providerAnswer = fixture.providerAnswer(
            responseState: .unsupported,
            directAnswer: "",
            sections: [
                GraphChatProviderAnswerSection(
                    title: "Must disappear",
                    text: "Must disappear",
                    evidenceIDValues: [evidence.id.rawValue.uuidString],
                    artifactIDValues: [artifactID.rawValue.uuidString]
                )
            ],
            evidenceIDs: [evidence.id],
            artifactIDs: [artifactID],
            appliedFilters: [
                GraphChatProviderAppliedFilter(
                    fieldName: "Status",
                    operationDescription: "equals",
                    valueDescription: "Active"
                )
            ],
            followUps: [
                GraphChatProviderFollowUpSuggestion(
                    title: "Next",
                    prompt: "Continue"
                )
            ],
            unsupportedCapability: .attachmentContent
        )

        let turn = try await fixture.finalize(
            providerAnswer,
            resources: resources,
            language: .german
        )

        #expect(turn.answer.state == .unsupported(.attachmentContent))
        #expect(
            turn.answer.directAnswer
                == GraphChatResponseLocalizer(language: .german)
                    .unsupported(.attachmentContent)
        )
        #expect(turn.answer.sections.isEmpty)
        #expect(turn.answer.evidence.isEmpty)
        #expect(turn.answer.artifactIDs.isEmpty)
        #expect(turn.answer.appliedFilters.isEmpty)
        #expect(turn.answer.followUpSuggestions.isEmpty)
    }

    @Test
    func validReferenceProposalKeepsTheAnswerAndMissingContextCannotReplaceUsableText() async throws {
        let fixture = AnswerFinalizerFixture()
        let alias = fixture.makeEntityAlias(index: 1)
        let context = fixture.makeContext(aliases: [alias])
        let validResources = try await fixture.makeResources(context: context)
        let validTurn = try await fixture.finalize(
            fixture.providerAnswer(
                directAnswer: "Usable answer",
                referenceProposal: .alias(alias.alias)
            ),
            resources: validResources,
            context: context
        )
        #expect(validTurn.answer.state == .answer)
        #expect(validTurn.answer.directAnswer == "Usable answer")

        let missingContext = fixture.makeContext()
        let missingResources = try await fixture.makeResources(context: missingContext)
        let missingTurn = try await fixture.finalize(
            fixture.providerAnswer(
                directAnswer: "Still usable",
                referenceProposal: .latestResults
            ),
            resources: missingResources,
            context: missingContext
        )
        #expect(missingTurn.answer.state == .answer)
        #expect(missingTurn.answer.directAnswer == "Still usable")
        #expect(missingTurn.conversationState.pendingClarification == nil)
    }

    @Test
    func clarificationAcceptsOnlyRevalidatedAliasesDeduplicatesAndCapsAtEight() async throws {
        let fixture = AnswerFinalizerFixture()
        let aliases = (1...10).map {
            fixture.makeEntityAlias(index: $0)
        }
        let context = fixture.makeContext(aliases: aliases)
        let resources = try await fixture.makeResources(context: context)
        let rawAliases = [
            "INVENTED",
            aliases[0].alias,
            aliases[0].alias.lowercased(),
        ] + aliases.dropFirst().map(\.alias)
        let providerAnswer = fixture.providerAnswer(
            responseState: .clarification,
            directAnswer: "",
            referenceProposal: .alias("INVENTED"),
            clarificationQuestion: "Which one?",
            clarificationOptionAliases: rawAliases
        )

        let turn = try await fixture.finalize(
            providerAnswer,
            resources: resources,
            context: context
        )
        guard case .clarification(let clarification) = turn.answer.state else {
            Issue.record("Expected a clarification answer.")
            return
        }

        let pendingOptionIDs =
            turn.conversationState.pendingClarification?.options.map(\.id)
            ?? []
        #expect(clarification.options.count == 8)
        #expect(clarification.options.map(\.id) == Array(aliases.prefix(8)).map(\.alias))
        #expect(pendingOptionIDs == Array(aliases.prefix(8)).map(\.alias))
        #expect(pendingOptionIDs.contains("INVENTED") == false)
    }

    @Test
    func clarificationFallsBackToRevalidatedOptionsFromReferenceProposal() async throws {
        let fixture = AnswerFinalizerFixture()
        let aliases = (1...3).map {
            fixture.makeEntityAlias(index: $0)
        }
        let context = fixture.makeContext(aliases: aliases)
        let resources = try await fixture.makeResources(context: context)
        let providerAnswer = fixture.providerAnswer(
            responseState: .clarification,
            referenceProposal: .alias("UNKNOWN"),
            clarificationQuestion: "Which entity?",
            clarificationOptionAliases: []
        )

        let turn = try await fixture.finalize(
            providerAnswer,
            resources: resources,
            context: context
        )

        guard case .clarification(let clarification) = turn.answer.state else {
            Issue.record("Expected a clarification answer.")
            return
        }
        let pendingOptionIDs =
            turn.conversationState.pendingClarification?.options.map(\.id)
            ?? []
        #expect(clarification.options.map(\.id) == aliases.map(\.alias))
        #expect(pendingOptionIDs == aliases.map(\.alias))
    }

    @Test
    func inventedClarificationAliasesNeverEnterConversationState() async throws {
        let fixture = AnswerFinalizerFixture()
        let context = fixture.makeContext()
        let resources = try await fixture.makeResources(context: context)
        let providerAnswer = fixture.providerAnswer(
            responseState: .clarification,
            clarificationQuestion: "",
            clarificationOptionAliases: ["INVENTED", "ALSO_INVENTED"]
        )

        let turn = try await fixture.finalize(
            providerAnswer,
            resources: resources,
            context: context,
            language: .german
        )

        guard case .clarification(let clarification) = turn.answer.state else {
            Issue.record("Expected a clarification answer.")
            return
        }
        #expect(clarification.options.isEmpty)
        #expect(
            clarification.question
                == GraphChatResponseLocalizer(language: .german)
                    .clarificationQuestion(reason: .ambiguous)
        )
        #expect(turn.conversationState.pendingClarification == nil)
    }

    @Test
    func primaryEvidenceIsRetainedWhenModelOmitsAllEvidenceIDs() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(40)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let primary = try await fixture.makePrimaryResult(
            in: resources,
            evidence: [evidence]
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(),
            resources: resources,
            primaryResult: primary
        )

        #expect(turn.answer.evidence == [evidence])
        #expect(turn.answer.hasInsufficientEvidence == false)
        #expect(turn.conversationState.turnContexts.last?.evidenceIDs == [evidence.id])
    }

    @Test
    func primaryArtifactIsRetainedWhenModelOmitsAllArtifactIDs() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(41)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let artifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: evidence.id
        )
        let primary = try await fixture.makePrimaryResult(
            in: resources,
            evidence: [evidence],
            artifactIDs: [artifactID]
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(),
            resources: resources,
            primaryResult: primary
        )

        #expect(turn.answer.evidenceIDs == [evidence.id])
        #expect(turn.answer.artifactIDs == [artifactID])
        #expect(turn.committedArtifactIDs == [artifactID])
    }

    @Test
    func hallucinatedModelUUIDsCannotReplaceThePrimaryResult() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(42)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let artifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: evidence.id
        )
        let primary = try await fixture.makePrimaryResult(
            in: resources,
            evidence: [evidence],
            artifactIDs: [artifactID]
        )
        let inventedEvidenceID = GraphEvidenceID(rawValue: fixture.uuid(942))
        let inventedArtifactID = GraphChatAnswerArtifactID(
            rawValue: fixture.uuid(943)
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(
                evidenceIDs: [inventedEvidenceID],
                artifactIDs: [inventedArtifactID]
            ),
            resources: resources,
            primaryResult: primary
        )

        #expect(turn.answer.evidenceIDs == [evidence.id])
        #expect(turn.answer.artifactIDs == [artifactID])
    }

    @Test
    func foreignValidLookingEvidenceIDIsDiscardedWhilePrimaryEvidenceRemains() async throws {
        let fixture = AnswerFinalizerFixture()
        let primaryEvidence = fixture.makeEvidence(43)
        let foreignEvidence = fixture.makeEvidence(44)
        let resources = try await fixture.makeResources(
            evidence: [primaryEvidence]
        )
        let primary = try await fixture.makePrimaryResult(
            in: resources,
            evidence: [primaryEvidence]
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(evidenceIDs: [foreignEvidence.id]),
            resources: resources,
            primaryResult: primary
        )

        #expect(turn.answer.evidenceIDs == [primaryEvidence.id])
        #expect(turn.answer.evidenceIDs.contains(foreignEvidence.id) == false)
    }

    @Test
    func additionalCurrentTurnEvidenceSupplementsWithoutRemovingPrimaryEvidence() async throws {
        let fixture = AnswerFinalizerFixture()
        let primaryEvidence = fixture.makeEvidence(45)
        let supplementalEvidence = fixture.makeEvidence(46)
        let resources = try await fixture.makeResources(
            evidence: [primaryEvidence, supplementalEvidence]
        )
        let primary = try await fixture.makePrimaryResult(
            in: resources,
            evidence: [primaryEvidence]
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(evidenceIDs: [supplementalEvidence.id]),
            resources: resources,
            primaryResult: primary
        )

        #expect(
            turn.answer.evidenceIDs
                == [primaryEvidence.id, supplementalEvidence.id]
        )
    }

    @Test
    func primaryResultFromAnEarlierTurnIsIgnored() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(47)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let foreignTurn = try await fixture.makePrimaryResult(
            in: resources,
            evidence: [evidence],
            requestID: fixture.uuid(947)
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(),
            resources: resources,
            primaryResult: foreignTurn
        )

        #expect(turn.answer.evidence.isEmpty)
        #expect(turn.answer.artifactIDs.isEmpty)
    }

    @Test
    func primaryEmptyQueryForcesTypedNoResultsEvenWhenModelClaimsAnswer() async throws {
        let fixture = AnswerFinalizerFixture()
        let resources = try await fixture.makeResources()
        let primary = try await fixture.makePrimaryResult(
            in: resources,
            state: .noResults,
            evidence: []
        )

        let turn = try await fixture.finalize(
            fixture.providerAnswer(
                responseState: .answer,
                directAnswer: "There are no matching projects."
            ),
            resources: resources,
            primaryResult: primary
        )

        #expect(turn.answer.state == .noResults)
        #expect(turn.answer.evidence.isEmpty)
        #expect(turn.answer.artifactIDs.isEmpty)
    }

    @Test
    func presentationFallbackNeverDropsPrimaryReferencesOrShowsTechnicalIDs() async throws {
        let fixture = AnswerFinalizerFixture()
        let evidence = fixture.makeEvidence(48)
        let resources = try await fixture.makeResources(evidence: [evidence])
        let artifactID = try await fixture.stageArtifact(
            in: resources,
            evidenceID: evidence.id
        )
        let primary = try await fixture.makePrimaryResult(
            in: resources,
            evidence: [evidence],
            artifactIDs: [artifactID]
        )
        let technicalID = fixture.uuid(948).uuidString

        let turn = try await fixture.finalize(
            fixture.providerAnswer(
                directAnswer: "Internal reference: \(technicalID)"
            ),
            resources: resources,
            primaryResult: primary
        )

        #expect(turn.answer.directAnswer.contains(technicalID) == false)
        #expect(turn.answer.evidenceIDs == [evidence.id])
        #expect(turn.answer.artifactIDs == [artifactID])
    }

    @Test
    func localAnswerUsesTheFinalizerAndAtomicallyCommitsPendingClarification() async throws {
        let fixture = AnswerFinalizerFixture()
        let option = GraphChatPendingClarificationOption(
            id: "A1",
            title: "Entity 1",
            proposal: .alias("A1")
        )
        let pending = GraphChatPendingClarification(
            id: fixture.requestID,
            decision: .conversationReference,
            options: [option],
            sourceTurnID: nil,
            graphScope: fixture.graphScope,
            chatScope: fixture.chatScope,
            continuationOperation: .answerAboutReference,
            continuationQuestion: "Continue",
            createdAt: fixture.completedAt,
            expiresAt: fixture.completedAt.addingTimeInterval(600)
        )
        let answer = GraphChatAnswer(
            state: .clarification(
                GraphChatClarification(
                    id: pending.id,
                    question: "Which one?",
                    options: [
                        GraphChatClarificationOption(
                            id: option.id,
                            title: option.title
                        )
                    ]
                )
            ),
            directAnswer: "Which one?",
            hasInsufficientEvidence: true
        )

        let turn = try await fixture.finalizer.finalizeLocalTurn(
            GraphChatLocalAnswerFinalizationInput(
                requestID: fixture.requestID,
                completedAt: fixture.completedAt,
                answer: answer,
                baseState: fixture.baseState,
                expectedCommittedState: fixture.baseState,
                pendingClarification: pending,
                responseLanguage: .english
            ),
            currentCommittedState: fixture.baseState
        )

        #expect(turn.answer.state == answer.state)
        #expect(turn.answer.directAnswer == answer.directAnswer)
        #expect(turn.answer.presentationContext?.language == .english)
        #expect(turn.completion.source == .local)
        #expect(turn.conversationState.pendingClarification == pending)
        #expect(turn.conversationState.turnContexts.last?.id == fixture.requestID)
    }
}

private struct AnswerFinalizerFixture {
    struct Resources {
        let evidenceRegistry: GraphChatEvidenceRegistry
        let presentationRegistry: GraphChatPresentationRegistry
        let artifactRegistry: GraphChatAnswerArtifactRegistry
        let conversationTransaction: GraphChatConversationStateTransaction
        let artifactContext: GraphChatArtifactCommitContext
        let context: GraphChatConversationContextSnapshot
    }

    let graphScope = GraphScope(
        graphID: UUID(uuidString: "F1000000-0000-0000-0000-000000000001")!
    )
    let requestID = UUID(
        uuidString: "F1000000-0000-0000-0000-000000000002"
    )!
    let completedAt = Date(timeIntervalSince1970: 1_800_000_000)

    var chatScope: GraphChatScope {
        .entireGraph(graphScope)
    }

    var baseState: GraphChatConversationState {
        .initial(
            graphScope: graphScope,
            chatScope: chatScope,
            conversationID: uuid(3)
        )
    }

    var finalizer: GraphChatAnswerFinalizer {
        makeFinalizer(
            evidenceValidator: PassthroughGraphEvidenceValidator()
        )
    }

    func makeFinalizer(
        evidenceValidator: any GraphEvidenceValidating
    ) -> GraphChatAnswerFinalizer {
        GraphChatAnswerFinalizer(
            referenceResolver: GraphChatConversationReferenceResolver(
                revalidator: AnswerFinalizerReferenceRevalidator()
            ),
            evidenceValidator: evidenceValidator
        )
    }

    func makeResources(
        evidence: [GraphEvidence] = [],
        context: GraphChatConversationContextSnapshot? = nil
    ) async throws -> Resources {
        let state = baseState
        let resolvedContext = context ?? makeContext(state: state)
        let evidenceRegistry = GraphChatEvidenceRegistry(scope: chatScope)
        try await evidenceRegistry.register(evidence)
        let presentationRegistry = GraphChatPresentationRegistry(
            schemaContext: makeEmptySchemaContext(),
            conversationContext: resolvedContext,
            language: .english
        )
        await presentationRegistry.registerValidatedEvidence(evidence)
        let sessionID = GraphChatAnswerArtifactSessionID(rawValue: UUID())
        let transactionID = GraphChatAnswerArtifactTransactionID(rawValue: UUID())
        return Resources(
            evidenceRegistry: evidenceRegistry,
            presentationRegistry: presentationRegistry,
            artifactRegistry: GraphChatAnswerArtifactRegistry(
                graphScope: graphScope,
                scope: chatScope,
                sessionID: sessionID
            ),
            conversationTransaction: GraphChatConversationStateTransaction(
                baseState: state,
                reducer: GraphChatConversationStateReducer()
            ),
            artifactContext: GraphChatArtifactCommitContext(
                graphScope: graphScope,
                chatScope: chatScope,
                sessionID: sessionID,
                transactionID: transactionID
            ),
            context: resolvedContext
        )
    }

    func finalize(
        _ providerAnswer: GraphChatProviderFinalAnswer,
        resources: Resources,
        artifactContext: GraphChatArtifactCommitContext? = nil,
        context: GraphChatConversationContextSnapshot? = nil,
        language: GraphChatResponseLanguage = .english,
        primaryResult: GraphChatToolExecutionLedgerEntry? = nil,
        answerFinalizer: GraphChatAnswerFinalizer? = nil
    ) async throws -> GraphChatFinalizedTurn {
        try await (answerFinalizer ?? finalizer).finalizeProviderTurn(
            GraphChatProviderAnswerFinalizationInput(
                requestID: requestID,
                completedAt: completedAt,
                providerAnswer: providerAnswer,
                conversationContext: context ?? resources.context,
                responseLanguage: language,
                continuationOperation: nil,
                requestQuestion: "Continue the trusted operation",
                expectedCommittedState: baseState,
                primaryResult: primaryResult,
                artifactContext: artifactContext ?? resources.artifactContext,
                presentationRegistry: resources.presentationRegistry
            ),
            evidenceRegistry: resources.evidenceRegistry,
            artifactRegistry: resources.artifactRegistry,
            conversationTransaction: resources.conversationTransaction,
            currentCommittedState: baseState
        )
    }

    func stageArtifact(
        in resources: Resources,
        evidenceID: GraphEvidenceID,
        querySummary: GraphChatAnswerArtifactQuerySummary? = nil
    ) async throws -> GraphChatAnswerArtifactID {
        let binding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [evidenceID]
        )
        return try await resources.artifactRegistry.stage(
            GraphChatAnswerArtifactDraft(
                graphScope: graphScope,
                title: "Validated artifact",
                payload: .metric(
                    GraphChatAnswerArtifactMetricPayload(
                        title: "Count",
                        value: .integer(1),
                        unit: nil,
                        contextDescription: nil,
                        evidence: binding
                    )
                ),
                evidence: binding,
                querySummary: querySummary
            ),
            transactionID: resources.artifactContext.transactionID,
            evidenceRegistry: resources.evidenceRegistry
        )
    }

    func makePrimaryResult(
        in resources: Resources,
        tool: GraphChatToolKind = .queryDetailValues,
        state: GraphChatToolResultState = .success,
        evidence: [GraphEvidence],
        artifactIDs: [GraphChatAnswerArtifactID] = [],
        requestID: UUID? = nil
    ) async throws -> GraphChatToolExecutionLedgerEntry {
        let ledger = GraphChatPrimaryResultLedger(
            graphScope: graphScope,
            chatScope: chatScope,
            artifactSessionID: resources.artifactContext.sessionID
        )
        try await ledger.bind(requestID: requestID ?? self.requestID)
        let artifacts = try await resources.artifactRegistry.validatedArtifacts(
            for: artifactIDs.map { $0.rawValue.uuidString },
            graphScope: graphScope,
            sessionID: resources.artifactContext.sessionID,
            transactionID: resources.artifactContext.transactionID
        )
        try await ledger.record(
            response: GraphChatModelToolResponse(
                tool: tool,
                state: state,
                content: "Validated primary result",
                evidenceIDs: evidence.map(\.id),
                artifactIDs: artifactIDs
            ),
            evidence: evidence,
            artifacts: artifacts,
            transactionID: resources.artifactContext.transactionID
        )
        guard let primary = await ledger.snapshotForTesting(
            transactionID: resources.artifactContext.transactionID
        ).primaryResult else {
            throw GraphChatError(
                code: .unexpected,
                message: "The primary-result fixture could not create an eligible result."
            )
        }
        return primary
    }

    func makeEvidence(_ index: Int) -> GraphEvidence {
        GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .entity,
                sourceID: uuid(100 + index)
            ),
            summary: "Evidence \(index)",
            identitySuffix: String(index)
        )
    }

    func makeEntityAlias(index: Int) -> GraphChatConversationContextAlias {
        GraphChatConversationContextAlias(
            alias: "A\(index)",
            label: "Entity \(index)",
            target: .entity(uuid(200 + index)),
            ordinal: index
        )
    }

    func makeContext(
        state: GraphChatConversationState? = nil,
        aliases: [GraphChatConversationContextAlias] = []
    ) -> GraphChatConversationContextSnapshot {
        let state = state ?? baseState
        return GraphChatConversationContextSnapshot(
            conversationID: state.conversationID,
            graphScope: graphScope,
            chatScope: chatScope,
            aliases: aliases,
            results: [],
            turns: [],
            latestResultAlias: nil,
            lastEntityAlias: aliases.last?.alias,
            lastFieldAlias: nil,
            lastGroupAlias: nil,
            lastNodeAlias: nil,
            lastComparisonAlias: nil,
            currentReferenceAlias: nil,
            lastValidatedQuery: nil,
            resultRevalidations: [],
            pendingClarificationID: nil
        )
    }

    func makeEmptySchemaContext() -> GraphSchemaContext {
        GraphSchemaContext(
            graphScope: graphScope,
            snapshot: GraphSchemaSnapshot(
                graphName: "Test",
                entities: [],
                truncation: GraphSchemaTruncation(
                    sourceEntityCount: 0,
                    includedEntityCount: 0,
                    sourceFieldCount: 0,
                    includedFieldCount: 0,
                    sourceChoiceOptionCount: 0,
                    includedChoiceOptionCount: 0,
                    sourceExampleValueCount: 0,
                    includedExampleValueCount: 0,
                    stringsWereTruncated: false
                )
            ),
            aliases: GraphSchemaAliasMap(
                graphScope: graphScope,
                entitiesByAlias: [:],
                fieldsByAlias: [:],
                nodeEntityIDs: [:]
            )
        )
    }

    func querySummary() -> GraphChatAnswerArtifactQuerySummary {
        GraphChatAnswerArtifactQuerySummary(
            language: .english,
            entityID: uuid(300),
            entityLabel: "Projects",
            filters: [],
            grouping: nil,
            sorting: [],
            projection: [],
            includesNodeIdentity: true,
            limit: 10,
            aggregation: nil,
            displayText: "Projects, limit 10"
        )
    }

    func providerAnswer(
        responseState: GraphChatProviderResponseState = .answer,
        directAnswer: String = "Validated answer",
        sections: [GraphChatProviderAnswerSection] = [],
        evidenceIDs: [GraphEvidenceID] = [],
        artifactIDs: [GraphChatAnswerArtifactID] = [],
        appliedFilters: [GraphChatProviderAppliedFilter] = [],
        followUps: [GraphChatProviderFollowUpSuggestion] = [],
        referenceProposal: GraphChatConversationReferenceProposal? = nil,
        clarificationQuestion: String? = nil,
        clarificationOptionAliases: [String] = [],
        unsupportedCapability: GraphChatUnsupportedCapability? = nil
    ) -> GraphChatProviderFinalAnswer {
        GraphChatProviderFinalAnswer(
            responseState: responseState,
            directAnswer: directAnswer,
            sections: sections,
            evidenceIDValues: evidenceIDs.map { $0.rawValue.uuidString },
            artifactIDValues: artifactIDs.map { $0.rawValue.uuidString },
            appliedFilters: appliedFilters,
            followUpSuggestions: followUps,
            hasInsufficientEvidence: false,
            referenceProposal: referenceProposal,
            clarificationQuestion: clarificationQuestion,
            clarificationOptionAliases: clarificationOptionAliases,
            unsupportedCapability: unsupportedCapability
        )
    }

    func uuid(_ suffix: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "F1000000-0000-0000-0000-%012d",
                suffix
            )
        )!
    }
}

private struct AnswerFinalizerAllowListEvidenceValidator:
    GraphEvidenceValidating
{
    let allowedIDs: Set<GraphEvidenceID>

    func validatedEvidence(
        _ evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> [GraphEvidence] {
        evidence.filter {
            $0.sourceReference.graphID == scope.graphScope.graphID
                && allowedIDs.contains($0.id)
        }
    }
}

private struct AnswerFinalizerReferenceRevalidator:
    GraphChatConversationReferenceRevalidating
{
    func node(
        _ node: NodeRefKey,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationNode? {
        GraphChatRevalidatedConversationNode(
            node: node,
            label: "Node",
            ownerEntityID: node.kind == .entity ? node.id : nil
        )
    }

    func entity(
        _ entityID: UUID,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationEntity? {
        GraphChatRevalidatedConversationEntity(
            entityID: entityID,
            label: "Entity"
        )
    }

    func field(
        _ fieldID: UUID,
        in graphScope: GraphScope
    ) async throws -> GraphChatRevalidatedConversationField? {
        GraphChatRevalidatedConversationField(
            fieldID: fieldID,
            entityID: fieldID,
            label: "Field"
        )
    }

    func queryResult(
        for plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatRevalidatedConversationQuery? {
        nil
    }
}
