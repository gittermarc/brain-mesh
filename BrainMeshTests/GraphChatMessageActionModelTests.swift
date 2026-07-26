//
//  GraphChatMessageActionModelTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat message action models")
struct GraphChatMessageActionModelTests {
    @Test
    func copyBuildsReadableTextWithoutInternalEvidenceOrDiagnostics() throws {
        let secretEvidenceID = UUID(uuidString: "F1000000-0000-0000-0000-000000000001")!
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: secretEvidenceID,
            summary: "INTERNAL-SOURCE-PAYLOAD"
        )
        let answer = GraphChatAnswer(
            directAnswer: "Projekt Atlas ist offen. Interne Referenzen: \(evidence.id.rawValue.uuidString) und \(secretEvidenceID.uuidString).",
            sections: [
                GraphChatAnswerSection(
                    title: "Details",
                    text: "Die Frist endet am Freitag.",
                    evidenceIDs: [evidence.id]
                )
            ],
            evidence: [evidence],
            appliedFilters: [
                GraphChatAppliedFilter(
                    fieldName: "Status",
                    operationDescription: "entspricht",
                    valueDescription: "Offen"
                )
            ],
            followUpSuggestions: [],
            hasInsufficientEvidence: false,
            presentationContext: GraphChatPresentationContext(
                registry: GraphChatValidatedPresentationRegistry(
                    evidence: [evidence],
                    language: .german
                ),
                language: .german
            )
        )
        let state = Self.completedState(answer: answer)

        let payload = try #require(
            GraphChatCopyContentBuilder.payload(for: state)
        )

        #expect(payload.text.contains("Projekt Atlas ist offen."))
        #expect(payload.text.contains("Graphquelle"))
        #expect(payload.text.contains("Details\nDie Frist endet am Freitag."))
        #expect(payload.text.contains("Status: entspricht Offen"))
        #expect(payload.text.contains("Quellenhinweis: 1 validierte Graphquelle"))
        #expect(payload.text.contains(secretEvidenceID.uuidString) == false)
        #expect(payload.text.contains(evidence.id.rawValue.uuidString) == false)
        #expect(payload.text.contains("INTERNAL-SOURCE-PAYLOAD") == false)
        #expect(payload.includesCompactSourceMetadata)
    }

    @Test
    func copyIncludesSourcesOnlyAccordingToTheExplicitPolicy() throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence()
        let state = Self.completedState(
            answer: GraphChatUITestSupport.finalAnswer(
                directAnswer: "Antwort",
                evidence: [evidence]
            )
        )

        let withoutSources = try #require(
            GraphChatCopyContentBuilder.payload(
                for: state,
                sourcePolicy: .none
            )
        )
        let withSources = try #require(
            GraphChatCopyContentBuilder.payload(
                for: state,
                sourcePolicy: .compactValidatedCount
            )
        )

        #expect(withoutSources.text == "Antwort")
        #expect(withoutSources.includesCompactSourceMetadata == false)
        #expect(withSources.text.contains("Quellenhinweis"))
        #expect(withSources.includesCompactSourceMetadata)
    }

    @Test
    func copyRejectsEmptyAndStreamingAssistantStates() {
        let streaming = GraphChatAssistantMessageState(question: "Frage")
        var empty = GraphChatAssistantMessageState(question: "Frage")
        empty.apply(
            .completed(
                GraphChatUITestSupport.finalAnswer(
                    directAnswer: ""
                )
            )
        )

        #expect(GraphChatCopyContentBuilder.payload(for: streaming) == nil)
        #expect(GraphChatCopyContentBuilder.payload(for: empty) == nil)
    }

    @Test
    func actionAvailabilityMatchesMessageTypeAndTerminalState() {
        let userID = UUID()
        let assistantID = UUID()
        let streamingID = UUID()
        let finalState = Self.completedState(
            answer: GraphChatUITestSupport.finalAnswer(
                directAnswer: "Antwort"
            )
        )
        let messages = [
            GraphChatTranscriptMessage(
                id: userID,
                state: .userQuestion("Frage")
            ),
            GraphChatTranscriptMessage(
                id: assistantID,
                state: .assistant(finalState)
            ),
            GraphChatTranscriptMessage(
                id: streamingID,
                state: .assistant(
                    GraphChatAssistantMessageState(question: "Noch eine Frage")
                )
            )
        ]

        let userAvailability = GraphChatMessageActionPolicy.availability(
            for: userID,
            in: messages,
            isGenerating: true
        )
        let oldAssistantAvailability = GraphChatMessageActionPolicy.availability(
            for: assistantID,
            in: messages,
            isGenerating: true
        )
        let streamingAvailability = GraphChatMessageActionPolicy.availability(
            for: streamingID,
            in: messages,
            isGenerating: true
        )

        #expect(userAvailability.canEditAndResend)
        #expect(userAvailability.canCopy == false)
        #expect(oldAssistantAvailability.canCopy)
        #expect(oldAssistantAvailability.canRegenerate == false)
        #expect(oldAssistantAvailability.canGiveFeedback)
        #expect(streamingAvailability == .unavailable)
    }

    @Test
    func feedbackAvailabilityCoversProductAnswerStatesAndRejectsErrors() {
        let clarification = GraphChatClarification(
            id: UUID(),
            question: "Welchen Eintrag meinst du?",
            options: [
                GraphChatClarificationOption(id: "one", title: "Eintrag 1")
            ]
        )
        let eligibleStates = [
            Self.completedState(),
            Self.completedState(
                answer: GraphChatUITestSupport.finalAnswer(
                    state: .clarification(clarification),
                    directAnswer: clarification.question
                )
            ),
            Self.completedState(
                answer: GraphChatUITestSupport.finalAnswer(
                    state: .noResults,
                    directAnswer: "Keine Ergebnisse"
                )
            ),
            Self.completedState(
                answer: GraphChatUITestSupport.finalAnswer(
                    state: .unsupported(.attachmentContent),
                    directAnswer: "Nicht unterstützt"
                )
            ),
        ]

        for state in eligibleStates {
            let message = GraphChatTranscriptMessage(state: .assistant(state))
            let availability = GraphChatMessageActionPolicy.availability(
                for: message.id,
                in: [message],
                isGenerating: false
            )
            #expect(availability.canCopy)
            #expect(availability.canGiveFeedback)
        }

        var technicalError = GraphChatAssistantMessageState(question: "Frage")
        technicalError.apply(
            .failure(
                GraphChatError(
                    code: .unexpected,
                    message: "Technischer Fehler"
                )
            )
        )
        let errorMessage = GraphChatTranscriptMessage(
            state: .assistant(technicalError)
        )
        #expect(
            GraphChatMessageActionPolicy.availability(
                for: errorMessage.id,
                in: [errorMessage],
                isGenerating: false
            ) == .unavailable
        )
    }

    @Test
    func editPlanRemovesTheOldBranchAndRestoresTheTrustedCheckpoint() throws {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let initial = GraphChatConversationCheckpoint.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        var retainedState = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        let retainedNode = NodeRefKey(kind: .attribute, id: UUID())
        retainedState.nodeReferences = [
            GraphChatConversationNodeReference(
                node: retainedNode,
                label: "Retained",
                ownerEntityID: nil,
                evidenceIDs: []
            )
        ]
        let retainedCheckpoint = GraphChatConversationCheckpoint.committed(retainedState)
        var staleBranchState = retainedState
        let staleNode = NodeRefKey(kind: .attribute, id: UUID())
        staleBranchState.nodeReferences.append(
            GraphChatConversationNodeReference(
                node: staleNode,
                label: "Stale branch",
                ownerEntityID: nil,
                evidenceIDs: []
            )
        )
        let staleCheckpoint = GraphChatConversationCheckpoint.committed(staleBranchState)

        let firstUser = GraphChatTranscriptMessage(
            state: .userQuestion("Erste Frage"),
            conversationCheckpointBeforeTurn: initial
        )
        let firstAssistant = GraphChatTranscriptMessage(
            state: .assistant(Self.completedState()),
            conversationCheckpointBeforeTurn: initial,
            conversationCheckpointAfterTurn: retainedCheckpoint
        )
        let editedUser = GraphChatTranscriptMessage(
            state: .userQuestion("Alte zweite Frage"),
            conversationCheckpointBeforeTurn: retainedCheckpoint
        )
        let staleAssistant = GraphChatTranscriptMessage(
            state: .assistant(Self.completedState()),
            conversationCheckpointBeforeTurn: retainedCheckpoint,
            conversationCheckpointAfterTurn: staleCheckpoint
        )
        let messages = [firstUser, firstAssistant, editedUser, staleAssistant]

        let plan = try #require(
            GraphChatMessageActionPlanner.editResendPlan(
                messages: messages,
                userMessageID: editedUser.id,
                replacementQuestion: "  Neue zweite Frage  ",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )

        #expect(plan.replacementQuestion == "Neue zweite Frage")
        #expect(plan.retainedMessages.map(\.id) == [firstUser.id, firstAssistant.id])
        #expect(plan.removedMessageIDs == [editedUser.id, staleAssistant.id])
        #expect(plan.restoreCheckpoint == retainedCheckpoint)
        #expect(plan.restoreCheckpoint.state?.nodeReferences.map(\.node) == [retainedNode])
        #expect(plan.restoreCheckpoint.state?.nodeReferences.contains(where: { $0.node == staleNode }) == false)
    }

    @Test
    func editingTheFirstQuestionDropsClarificationFromTheDiscardedBranch() throws {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let initial = GraphChatConversationCheckpoint.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        var staleState = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        staleState.pendingClarification = GraphChatPendingClarification(
            id: UUID(),
            decision: .conversationReference,
            options: [
                GraphChatPendingClarificationOption(
                    id: "one",
                    title: "Erste Option",
                    proposal: .ordinal(1)
                )
            ],
            sourceTurnID: UUID(),
            graphScope: graphScope,
            chatScope: chatScope,
            continuationOperation: .answerAboutReference,
            continuationQuestion: "Welche davon?",
            createdAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 100)
        )
        let staleCheckpoint = GraphChatConversationCheckpoint.committed(staleState)
        let user = GraphChatTranscriptMessage(
            state: .userQuestion("Mehrdeutige Frage"),
            conversationCheckpointBeforeTurn: initial
        )
        let assistant = GraphChatTranscriptMessage(
            state: .assistant(Self.completedState()),
            conversationCheckpointBeforeTurn: initial,
            conversationCheckpointAfterTurn: staleCheckpoint
        )

        let plan = try #require(
            GraphChatMessageActionPlanner.editResendPlan(
                messages: [user, assistant],
                userMessageID: user.id,
                replacementQuestion: "Eindeutige Frage",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )

        #expect(plan.retainedMessages.isEmpty)
        #expect(plan.restoreCheckpoint == initial)
        #expect(plan.restoreCheckpoint.state?.pendingClarification == nil)
    }

    @Test
    func regenerationKeepsTheUserQuestionAndReplacesOnlyTheLastAssistant() throws {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let checkpoint = GraphChatConversationCheckpoint.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        let user = GraphChatTranscriptMessage(
            state: .userQuestion("Unveränderte Frage"),
            conversationCheckpointBeforeTurn: checkpoint
        )
        let assistant = GraphChatTranscriptMessage(
            state: .assistant(Self.completedState()),
            conversationCheckpointBeforeTurn: checkpoint
        )

        let plan = try #require(
            GraphChatMessageActionPlanner.regenerationPlan(
                messages: [user, assistant],
                assistantMessageID: assistant.id,
                graphScope: graphScope,
                chatScope: chatScope
            )
        )

        #expect(plan.question == "Unveränderte Frage")
        #expect(plan.assistantMessageID == assistant.id)
        #expect(plan.retainedMessages.map(\.id) == [user.id])
        #expect(plan.removedMessageIDs == [assistant.id])
    }

    @Test
    func checkpointFromAnotherGraphCannotDriveEditOrRegeneration() {
        let originalGraph = GraphScope(graphID: UUID())
        let originalScope = GraphChatScope.entireGraph(originalGraph)
        let otherGraph = GraphScope(graphID: UUID())
        let otherScope = GraphChatScope.entireGraph(otherGraph)
        let checkpoint = GraphChatConversationCheckpoint.initial(
            graphScope: originalGraph,
            chatScope: originalScope
        )
        let user = GraphChatTranscriptMessage(
            state: .userQuestion("Frage"),
            conversationCheckpointBeforeTurn: checkpoint
        )
        let assistant = GraphChatTranscriptMessage(
            state: .assistant(Self.completedState()),
            conversationCheckpointBeforeTurn: checkpoint
        )

        #expect(
            GraphChatMessageActionPlanner.editResendPlan(
                messages: [user, assistant],
                userMessageID: user.id,
                replacementQuestion: "Neu",
                graphScope: otherGraph,
                chatScope: otherScope
            ) == nil
        )
        #expect(
            GraphChatMessageActionPlanner.regenerationPlan(
                messages: [user, assistant],
                assistantMessageID: assistant.id,
                graphScope: otherGraph,
                chatScope: otherScope
            ) == nil
        )
    }

    @Test
    func explicitIncompatibleCheckpointCannotFallBackToTrustedNeighbor() {
        let currentGraph = GraphScope(graphID: UUID())
        let currentScope = GraphChatScope.entireGraph(currentGraph)
        let otherGraph = GraphScope(graphID: UUID())
        let otherScope = GraphChatScope.entireGraph(otherGraph)
        let currentCheckpoint = GraphChatConversationCheckpoint.initial(
            graphScope: currentGraph,
            chatScope: currentScope
        )
        let incompatibleCheckpoint = GraphChatConversationCheckpoint.initial(
            graphScope: otherGraph,
            chatScope: otherScope
        )

        let firstUser = GraphChatTranscriptMessage(
            state: .userQuestion("Erste Frage"),
            conversationCheckpointBeforeTurn: currentCheckpoint
        )
        let firstAssistant = GraphChatTranscriptMessage(
            state: .assistant(Self.completedState()),
            conversationCheckpointBeforeTurn: currentCheckpoint,
            conversationCheckpointAfterTurn: currentCheckpoint
        )
        let editedUser = GraphChatTranscriptMessage(
            state: .userQuestion("Zweite Frage"),
            conversationCheckpointBeforeTurn: incompatibleCheckpoint
        )

        #expect(
            GraphChatMessageActionPlanner.editResendPlan(
                messages: [firstUser, firstAssistant, editedUser],
                userMessageID: editedUser.id,
                replacementQuestion: "Neue zweite Frage",
                graphScope: currentGraph,
                chatScope: currentScope
            ) == nil
        )

        let regenerationUser = GraphChatTranscriptMessage(
            state: .userQuestion("Regenerieren"),
            conversationCheckpointBeforeTurn: currentCheckpoint
        )
        let regenerationAssistant = GraphChatTranscriptMessage(
            state: .assistant(Self.completedState()),
            conversationCheckpointBeforeTurn: incompatibleCheckpoint
        )

        #expect(
            GraphChatMessageActionPlanner.regenerationPlan(
                messages: [regenerationUser, regenerationAssistant],
                assistantMessageID: regenerationAssistant.id,
                graphScope: currentGraph,
                chatScope: currentScope
            ) == nil
        )
    }

    private static func completedState(
        answer: GraphChatAnswer = GraphChatUITestSupport.finalAnswer()
    ) -> GraphChatAssistantMessageState {
        var state = GraphChatAssistantMessageState(question: "Frage")
        state.apply(.completed(answer))
        return state
    }
}
