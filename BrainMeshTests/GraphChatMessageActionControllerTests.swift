//
//  GraphChatMessageActionControllerTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

private actor GraphChatActionFailingRestoreOrchestrator: GraphChatOrchestrating {
    private let base: GraphChatUIFakeOrchestrator

    init(scripts: [GraphChatUIFakeScript]) {
        self.base = GraphChatUIFakeOrchestrator(scripts: scripts)
    }

    func streamAnswer(
        question: String,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> GraphChatEventStream {
        await base.streamAnswer(
            question: question,
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    func cancelCurrentGeneration() async {
        await base.cancelCurrentGeneration()
    }

    func discardSession() async {
        await base.discardSession()
    }

    func discardSession(
        reason: GraphChatConversationResetReason
    ) async {
        await base.discardSession(reason: reason)
    }

    func conversationStateSnapshot() async -> GraphChatConversationState? {
        await base.conversationStateSnapshot()
    }

    func restoreConversationState(
        from checkpoint: GraphChatConversationCheckpoint
    ) async throws {
        throw GraphChatError(
            code: .invalidRequest,
            message: "Restore failed"
        )
    }
}

private actor GraphChatActionOrderedFeedbackStore: GraphChatFeedbackStoring {
    private var recordsByScope: [GraphChatScope: [UUID: GraphChatFeedbackRecord]] = [:]
    private var writeOrder: [GraphChatFeedbackCategory?] = []

    func records(
        for scope: GraphChatScope
    ) -> [GraphChatFeedbackRecord] {
        recordsByScope[scope, default: [:]]
            .values
            .sorted {
                $0.createdAt < $1.createdAt
            }
    }

    func save(
        _ record: GraphChatFeedbackRecord,
        for scope: GraphChatScope
    ) async {
        if record.category == .helpful {
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        writeOrder.append(record.category)
        recordsByScope[scope, default: [:]][record.localMessageID] = record
    }

    func remove(
        messageID: UUID,
        for scope: GraphChatScope
    ) {
        writeOrder.append(nil)
        recordsByScope[scope]?[messageID] = nil
    }

    func remove(
        messageIDs: [UUID],
        for scope: GraphChatScope
    ) {
        for messageID in messageIDs {
            recordsByScope[scope]?[messageID] = nil
        }
    }

    func removeAll(
        for scope: GraphChatScope
    ) {
        recordsByScope[scope] = nil
    }

    func categoriesInWriteOrder() -> [GraphChatFeedbackCategory?] {
        writeOrder
    }
}

@MainActor
final class GraphChatMessageActionControllerHarness {
    let graphScope: GraphScope
    let chatScope: GraphChatScope
    let orchestrator: any GraphChatOrchestrating
    let historyStore: any GraphChatHistoryStoring
    let feedbackStore: any GraphChatFeedbackStoring
    let clipboardWriter = GraphChatUITestClipboardWriter()
    let checkpointController: GraphChatConversationCheckpointController

    var messages: [GraphChatTranscriptMessage]
    var composerText = ""
    var editingState: GraphChatEditingState?
    var feedbackByMessageID: [UUID: GraphChatFeedbackCategory] = [:]
    var isPerformingSessionMutation = false
    var accessDecision: GraphChatAccessDecision
    private(set) var notices: [GraphChatActionNotice] = []
    private(set) var sessionDerivedStateClearCount = 0

    lazy var generationController: GraphChatGenerationController = GraphChatGenerationController(
        graphScope: graphScope,
        chatScope: chatScope,
        orchestrator: orchestrator,
        historyStore: historyStore,
        observability: NoOpGraphChatObservabilityRecorder(),
        callbacks: GraphChatGenerationCallbacks(
            messageSnapshot: { [weak self] in
                self?.messages ?? []
            },
            operationWillCancel: { [weak self] _, assistantMessageID in
                self?.markAssistantCancelled(
                    messageID: assistantMessageID
                )
            },
            publicationDidArrive: { [weak self] publication, _, assistantMessageID in
                for event in publication.events {
                    self?.apply(
                        event,
                        toAssistantMessageID: assistantMessageID
                    )
                }
            },
            completedTurnDidArrive: { [weak self] operationID, assistantMessageID in
                guard let self,
                      self.generationController.isActive(operationID),
                      let state = await self.orchestrator.conversationStateSnapshot(),
                      let checkpoint = self.checkpointController.captureCommittedCheckpoint(
                        state: state,
                        outcome: .completed
                      ),
                      let index = self.messages.firstIndex(where: {
                        $0.id == assistantMessageID
                      }) else {
                    return
                }
                self.messages[index].conversationCheckpointAfterTurn = checkpoint
            },
            generationStateDidChange: { _ in }
        )
    )

    lazy var controller = GraphChatMessageActionController(
        graphScope: graphScope,
        chatScope: chatScope,
        orchestrator: orchestrator,
        historyStore: historyStore,
        feedbackStore: feedbackStore,
        clipboardWriter: clipboardWriter,
        checkpointController: checkpointController,
        generation: GraphChatMessageActionGenerationBridge(
            controller: generationController
        ),
        accessDecisionProvider: { [weak self] in
            self?.accessDecision ?? Self.deniedDecision
        },
        resultHandler: { [weak self] result in
            self?.apply(result)
        }
    )

    init(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        orchestrator: any GraphChatOrchestrating,
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore(),
        feedbackStore: any GraphChatFeedbackStoring = InMemoryGraphChatFeedbackStore(),
        messages: [GraphChatTranscriptMessage] = [],
        accessDecision: GraphChatAccessDecision = GraphChatMessageActionControllerHarness.readyDecision
    ) {
        self.graphScope = graphScope
        self.chatScope = chatScope
        self.orchestrator = orchestrator
        self.historyStore = historyStore
        self.feedbackStore = feedbackStore
        self.messages = messages
        self.accessDecision = accessDecision
        self.checkpointController = GraphChatConversationCheckpointController(
            graphScope: graphScope,
            chatScope: chatScope
        )
    }

    var snapshot: GraphChatMessageActionSnapshot {
        GraphChatMessageActionSnapshot(
            messages: messages,
            composerText: composerText,
            editingState: editingState,
            feedbackByMessageID: feedbackByMessageID,
            isPerformingSessionMutation: isPerformingSessionMutation
        )
    }

    func startNormalGeneration(
        question: String
    ) {
        let checkpoint = checkpointController.checkpointBeforeNextTurn()
        let assistantID = UUID()
        messages.append(
            GraphChatTranscriptMessage(
                state: .userQuestion(question),
                conversationCheckpointBeforeTurn: checkpoint
            )
        )
        messages.append(
            GraphChatTranscriptMessage(
                id: assistantID,
                state: .assistant(
                    GraphChatAssistantMessageState(
                        question: question
                    )
                ),
                conversationCheckpointBeforeTurn: checkpoint
            )
        )
        generationController.start(
            GraphChatGenerationRequest(
                question: question,
                assistantMessageID: assistantID,
                mode: .newTurn,
                usedIndexFallback: false
            )
        )
    }

    private func apply(
        _ result: GraphChatMessageActionControllerResult
    ) {
        switch result {
        case .notice(let notice):
            notices.append(notice)
        case .editingBegan(let editingState, let composerText):
            self.editingState = editingState
            self.composerText = composerText
        case .feedbackChanged(let feedbackByMessageID, let notice):
            self.feedbackByMessageID = feedbackByMessageID
            notices.append(notice)
        case .sessionMutationBegan:
            isPerformingSessionMutation = true
        case .branchCommitted(
            let messages,
            let feedbackByMessageID,
            let composerText,
            let clearsEditing
        ):
            self.messages = messages
            self.feedbackByMessageID = feedbackByMessageID
            self.composerText = composerText
            if clearsEditing {
                editingState = nil
            }
        case .newChatBegan:
            messages = []
            composerText = ""
            editingState = nil
            feedbackByMessageID = [:]
            isPerformingSessionMutation = true
            sessionDerivedStateClearCount += 1
        case .interpretationCorrectionCommitted:
            break
        case .interpretationCorrectionFailed(
            _,
            let notice
        ):
            notices.append(notice)
        case .interpretationCorrectionCancelled:
            break
        case .sessionMutationFinished(let notice):
            isPerformingSessionMutation = false
            if let notice {
                notices.append(notice)
            }
        }
    }

    private func apply(
        _ event: GraphChatStreamEvent,
        toAssistantMessageID messageID: UUID
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              case .assistant(var state) = messages[index].state else {
            return
        }
        state.apply(event)
        messages[index].state = .assistant(state)
    }

    private func markAssistantCancelled(
        messageID: UUID
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              case .assistant(var state) = messages[index].state,
              state.isTerminal == false else {
            return
        }
        state.markCancelled()
        messages[index].state = .assistant(state)
    }

    nonisolated static var readyDecision: GraphChatAccessDecision {
        GraphChatAccessDecision(
            route: .ready,
            canPresentChat: true,
            canStartGeneration: true,
            canCancelGeneration: true,
            usesIndexFallback: false
        )
    }

    nonisolated static var deniedDecision: GraphChatAccessDecision {
        GraphChatAccessDecision(
            route: .proRequired,
            canPresentChat: false,
            canStartGeneration: false,
            canCancelGeneration: true,
            usesIndexFallback: false
        )
    }
}

@Suite("Graph chat message action controller")
@MainActor
struct GraphChatMessageActionControllerTests {
    @Test
    func copyUsesOnlyReadableText() {
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(),
            summary: "Private evidence payload"
        )
        let setup = Self.makeSetup(
            scripts: [],
            messages: Self.singleCompletedTurn(
                question: "Private question",
                directAnswer: "Readable answer",
                evidence: [evidence]
            ).messages
        )
        guard let assistantID = setup.messages.last?.id else {
            Issue.record("Expected an assistant message.")
            return
        }

        setup.controller.perform(
            .copy,
            messageID: assistantID,
            snapshot: setup.snapshot
        )

        let copied = setup.clipboardWriter.values.last ?? ""
        #expect(copied.contains("Readable answer"))
        #expect(copied.contains("Quellenhinweis: 1 validierte Graphquelle"))
        #expect(copied.contains("Private evidence payload") == false)
        #expect(copied.contains(evidence.sourceReference.sourceID.uuidString) == false)
        #expect(setup.notices.last?.message == "Antwort kopiert")
    }

    @Test
    func feedbackSetChangeAndRemovalRemainSerial() async throws {
        let feedbackStore = GraphChatActionOrderedFeedbackStore()
        let turn = Self.singleCompletedTurn(
            question: "Question",
            directAnswer: "Answer"
        )
        let setup = Self.makeSetup(
            scripts: [],
            feedbackStore: feedbackStore,
            messages: turn.messages
        )

        setup.controller.perform(
            .feedback(.helpful),
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        setup.controller.perform(
            .feedback(.incomplete),
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        await GraphChatProviderTestSupport.waitUntil {
            await feedbackStore.records(for: setup.chatScope).first?.category
                == .incomplete
        }
        setup.controller.perform(
            .removeFeedback,
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        await GraphChatProviderTestSupport.waitUntil {
            await feedbackStore.records(for: setup.chatScope).isEmpty
        }

        #expect(
            await feedbackStore.categoriesInWriteOrder()
                == [.helpful, .incomplete, nil]
        )
        #expect(setup.feedbackByMessageID[turn.assistantID] == nil)
    }

    @Test
    func olderFeedbackWriteCannotOverwriteTheNewerCategory() async {
        let feedbackStore = GraphChatActionOrderedFeedbackStore()
        let turn = Self.singleCompletedTurn(
            question: "Question",
            directAnswer: "Answer"
        )
        let setup = Self.makeSetup(
            scripts: [],
            feedbackStore: feedbackStore,
            messages: turn.messages
        )

        setup.controller.perform(
            .feedback(.helpful),
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        setup.controller.perform(
            .feedback(.wrongSource),
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        await GraphChatProviderTestSupport.waitUntil {
            await feedbackStore.records(for: setup.chatScope).first?.category
                == .wrongSource
        }

        #expect(
            await feedbackStore.records(for: setup.chatScope).first?.category
                == .wrongSource
        )
        #expect(
            await feedbackStore.categoriesInWriteOrder()
                == [.helpful, .wrongSource]
        )
    }

    @Test
    func editAndResendKeepsPriorHistoryAndRemovesTheWholeFollowingBranch()
        async throws
    {
        let history = Self.twoCompletedTurns()
        let interpretation = try
            GraphChatIntentInterpretationTestFixture()
                .filteredCollection(
                    language: .english
                )
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatAnswer(
                                directAnswer:
                                    "Replacement answer",
                                hasInsufficientEvidence:
                                    false,
                                interpretation:
                                    interpretation
                            )
                        )
                    ]
                )
            ]
        )
        let setup = Self.makeSetup(
            orchestrator: orchestrator,
            messages: history.messages
        )
        let retainedIDs = history.messages.prefix(2).map(\.id)

        setup.controller.perform(
            .editAndResend,
            messageID: history.secondUserID,
            snapshot: setup.snapshot
        )
        setup.composerText = "Replacement question"
        setup.controller.submitEditedQuestion(
            snapshot: setup.snapshot,
            replacementQuestion: setup.composerText
        )
        await Self.waitForTerminalGeneration(setup)

        #expect(setup.messages.prefix(2).map(\.id) == retainedIDs)
        #expect(setup.messages.count == 4)
        #expect(
            setup.messages.contains(where: {
                $0.id == history.secondUserID
                    || $0.id == history.secondAssistantID
            }) == false
        )
        guard case .userQuestion(let question) = setup.messages[2].state,
              case .assistant(let answer) = setup.messages[3].state else {
            Issue.record("Expected a replacement branch.")
            return
        }
        #expect(question == "Replacement question")
        #expect(answer.text == "Replacement answer")
        #expect(
            answer.answer?.interpretation
                == interpretation
        )
    }

    @Test
    func editAndResendCommitsOnlyAfterRestoreSucceeds() async {
        let history = Self.twoCompletedTurns()
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Replacement answer"
                            )
                        )
                    ]
                )
            ],
            restoreDelayNanoseconds: 60_000_000
        )
        let setup = Self.makeSetup(
            orchestrator: orchestrator,
            messages: history.messages
        )

        setup.controller.perform(
            .editAndResend,
            messageID: history.secondUserID,
            snapshot: setup.snapshot
        )
        setup.controller.submitEditedQuestion(
            snapshot: setup.snapshot,
            replacementQuestion: "Replacement question"
        )
        await Task.yield()

        #expect(setup.messages == history.messages)
        #expect(await orchestrator.snapshot().questions.isEmpty)

        await Self.waitForTerminalGeneration(setup)
        #expect(await orchestrator.snapshot().restoredCheckpoints.count == 1)
        #expect(await orchestrator.snapshot().questions == ["Replacement question"])
    }

    @Test
    func restoreFailureLeavesTheOldBranchUntouched() async {
        let history = Self.twoCompletedTurns()
        let orchestrator = GraphChatActionFailingRestoreOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Must not run"
                            )
                        )
                    ]
                )
            ]
        )
        let setup = Self.makeSetup(
            orchestrator: orchestrator,
            messages: history.messages
        )

        setup.controller.perform(
            .editAndResend,
            messageID: history.secondUserID,
            snapshot: setup.snapshot
        )
        setup.controller.submitEditedQuestion(
            snapshot: setup.snapshot,
            replacementQuestion: "Replacement question"
        )
        await GraphChatUITestSupport.waitUntil {
            setup.generationController.isGenerating == false
                && setup.isPerformingSessionMutation == false
        }

        #expect(setup.messages == history.messages)
        #expect(setup.notices.last?.message == "Restore failed")
    }

    @Test
    func regenerationKeepsUserAssistantIdentityAndCreationDate()
        async throws
    {
        let turn = Self.singleCompletedTurn(
            question: "Same question",
            directAnswer: "Old answer"
        )
        let interpretation = try
            GraphChatIntentInterpretationTestFixture()
                .filteredCollection(
                    language: .english
                )
        let originalCreatedAt = turn.messages[1].createdAt
        let setup = Self.makeSetup(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatAnswer(
                                directAnswer:
                                    "New answer",
                                hasInsufficientEvidence:
                                    false,
                                interpretation:
                                    interpretation
                            )
                        )
                    ]
                )
            ],
            messages: turn.messages
        )

        setup.controller.perform(
            .regenerate,
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        await Self.waitForTerminalGeneration(setup)

        #expect(setup.messages.count == 2)
        #expect(setup.messages[0].id == turn.userID)
        #expect(setup.messages[1].id == turn.assistantID)
        #expect(setup.messages[1].createdAt == originalCreatedAt)
        guard case .assistant(let answer) = setup.messages[1].state else {
            Issue.record("Expected a regenerated assistant answer.")
            return
        }
        #expect(answer.text == "New answer")
        #expect(
            answer.answer?.interpretation
                == interpretation
        )
    }

    @Test
    func rapidRegenerateTapsStartOnlyOneRequest() async {
        let turn = Self.singleCompletedTurn(
            question: "Same question",
            directAnswer: "Old answer"
        )
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "New answer"
                            )
                        )
                    ]
                )
            ],
            restoreDelayNanoseconds: 40_000_000
        )
        let setup = Self.makeSetup(
            orchestrator: orchestrator,
            messages: turn.messages
        )

        setup.controller.perform(
            .regenerate,
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        setup.controller.perform(
            .regenerate,
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        await Self.waitForTerminalGeneration(setup)

        #expect(await orchestrator.snapshot().questions == ["Same question"])
        #expect(setup.messages.count == 2)
    }

    @Test
    func accessChangePreventsAStaleRegenerationCommit() async {
        let turn = Self.singleCompletedTurn(
            question: "Question",
            directAnswer: "Trusted old answer"
        )
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Stale answer"
                            )
                        )
                    ]
                )
            ],
            restoreDelayNanoseconds: 50_000_000
        )
        let setup = Self.makeSetup(
            orchestrator: orchestrator,
            messages: turn.messages
        )

        setup.controller.perform(
            .regenerate,
            messageID: turn.assistantID,
            snapshot: setup.snapshot
        )
        setup.accessDecision = GraphChatMessageActionControllerHarness.deniedDecision
        await GraphChatUITestSupport.waitUntil(maximumYields: 20_000) {
            setup.generationController.isGenerating == false
                && setup.isPerformingSessionMutation == false
        }

        #expect(setup.messages == turn.messages)
        #expect(await orchestrator.snapshot().questions.isEmpty)
    }

    @Test
    func newChatClearsSessionStateKeepsScopeAndSignalsOnce() async {
        let turn = Self.singleCompletedTurn(
            question: "Question",
            directAnswer: "Answer"
        )
        let historyStore = InMemoryGraphChatHistoryStore()
        let feedbackStore = InMemoryGraphChatFeedbackStore()
        let setup = Self.makeSetup(
            scripts: [],
            historyStore: historyStore,
            feedbackStore: feedbackStore,
            messages: turn.messages
        )
        await historyStore.save(
            turn.messages,
            for: setup.chatScope
        )
        setup.composerText = "Draft"
        setup.editingState = GraphChatEditingState(
            userMessageID: turn.userID,
            originalQuestion: "Question"
        )
        setup.feedbackByMessageID[turn.assistantID] = .helpful
        await feedbackStore.save(
            GraphChatFeedbackRecord(
                localMessageID: turn.assistantID,
                category: .helpful,
                answerState: .answer,
                scopeType: .graph,
                toolCategories: []
            ),
            for: setup.chatScope
        )
        if let state = setup.messages.last?
            .conversationCheckpointAfterTurn?
            .state {
            _ = setup.checkpointController.captureCommittedCheckpoint(
                state: state,
                outcome: .completed
            )
        }
        let originalGraphScope = setup.graphScope
        let originalChatScope = setup.chatScope

        setup.controller.perform(
            .startNewChat,
            messageID: nil,
            snapshot: setup.snapshot
        )
        await GraphChatUITestSupport.waitUntil {
            setup.isPerformingSessionMutation == false
        }

        #expect(setup.messages.isEmpty)
        #expect(setup.graphScope == originalGraphScope)
        #expect(setup.chatScope == originalChatScope)
        #expect(setup.sessionDerivedStateClearCount == 1)
        #expect(setup.composerText.isEmpty)
        #expect(setup.editingState == nil)
        #expect(setup.feedbackByMessageID.isEmpty)
        #expect(await feedbackStore.records(for: originalChatScope).isEmpty)
        #expect(await historyStore.messages(for: originalChatScope).isEmpty)
        #expect(setup.checkpointController.committedCheckpoint == nil)
    }

    @Test
    func newChatDuringToolExecutionWaitsForCancellation() async {
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .toolActivity(
                            GraphChatToolActivity(
                                tool: .searchGraph,
                                state: .started
                            )
                        ),
                    ],
                    waitsForCancellation: true
                )
            ]
        )
        let setup = Self.makeSetup(
            orchestrator: orchestrator,
            messages: []
        )
        setup.startNormalGeneration(
            question: "Running tool question"
        )
        await GraphChatUITestSupport.waitUntil {
            guard case .assistant(let state) = setup.messages.last?.state else {
                return false
            }
            return state.toolActivities.isEmpty == false
        }

        setup.controller.perform(
            .startNewChat,
            messageID: nil,
            snapshot: setup.snapshot
        )
        await GraphChatUITestSupport.waitUntil {
            setup.isPerformingSessionMutation == false
                && setup.generationController.isGenerating == false
        }

        let snapshot = await orchestrator.snapshot()
        #expect(snapshot.cancellationCount >= 1)
        #expect(snapshot.discardReasons.last == .newConversation)
        #expect(setup.messages.isEmpty)
    }

    @Test
    func newChatDoesNotChangeOrBypassTheAccessGate() async {
        let turn = Self.singleCompletedTurn(
            question: "Question",
            directAnswer: "Answer"
        )
        let setup = Self.makeSetup(
            scripts: [],
            messages: turn.messages,
            accessDecision: GraphChatMessageActionControllerHarness.deniedDecision
        )

        setup.controller.perform(
            .startNewChat,
            messageID: nil,
            snapshot: setup.snapshot
        )
        await GraphChatUITestSupport.waitUntil {
            setup.isPerformingSessionMutation == false
        }

        #expect(setup.accessDecision.route == .proRequired)
        #expect(setup.accessDecision.canStartGeneration == false)
        #expect(setup.messages.isEmpty)
    }

    private static func makeSetup(
        scripts: [GraphChatUIFakeScript],
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore(),
        feedbackStore: any GraphChatFeedbackStoring = InMemoryGraphChatFeedbackStore(),
        messages: [GraphChatTranscriptMessage],
        accessDecision: GraphChatAccessDecision = GraphChatMessageActionControllerHarness.readyDecision
    ) -> GraphChatMessageActionControllerHarness {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        return GraphChatMessageActionControllerHarness(
            graphScope: graphScope,
            chatScope: chatScope,
            orchestrator: GraphChatUIFakeOrchestrator(
                scripts: scripts
            ),
            historyStore: historyStore,
            feedbackStore: feedbackStore,
            messages: Self.reScoped(
                messages,
                graphScope: graphScope,
                chatScope: chatScope
            ),
            accessDecision: accessDecision
        )
    }

    private static func makeSetup(
        orchestrator: any GraphChatOrchestrating,
        historyStore: any GraphChatHistoryStoring = InMemoryGraphChatHistoryStore(),
        feedbackStore: any GraphChatFeedbackStoring = InMemoryGraphChatFeedbackStore(),
        messages: [GraphChatTranscriptMessage]
    ) -> GraphChatMessageActionControllerHarness {
        guard let checkpoint = messages.compactMap(
            \.conversationCheckpointBeforeTurn
        ).first else {
            let graphScope = GraphScope(graphID: UUID())
            let chatScope = GraphChatScope.entireGraph(graphScope)
            return GraphChatMessageActionControllerHarness(
                graphScope: graphScope,
                chatScope: chatScope,
                orchestrator: orchestrator,
                historyStore: historyStore,
                feedbackStore: feedbackStore,
                messages: messages
            )
        }
        return GraphChatMessageActionControllerHarness(
            graphScope: checkpoint.graphScope,
            chatScope: checkpoint.chatScope,
            orchestrator: orchestrator,
            historyStore: historyStore,
            feedbackStore: feedbackStore,
            messages: messages
        )
    }

    private static func singleCompletedTurn(
        question: String,
        directAnswer: String,
        evidence: [GraphEvidence] = []
    ) -> (
        messages: [GraphChatTranscriptMessage],
        userID: UUID,
        assistantID: UUID
    ) {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let initial = GraphChatConversationCheckpoint.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        let committed = GraphChatConversationCheckpoint.committed(
            Self.conversationState(
                graphScope: graphScope,
                chatScope: chatScope,
                turnCount: 1
            )
        )
        let userID = UUID()
        let assistantID = UUID()
        var assistantState = GraphChatAssistantMessageState(
            question: question
        )
        assistantState.apply(
            .completed(
                GraphChatUITestSupport.finalAnswer(
                    directAnswer: directAnswer,
                    evidence: evidence
                )
            )
        )
        return (
            [
                GraphChatTranscriptMessage(
                    id: userID,
                    state: .userQuestion(question),
                    conversationCheckpointBeforeTurn: initial
                ),
                GraphChatTranscriptMessage(
                    id: assistantID,
                    createdAt: Date(timeIntervalSince1970: 100),
                    state: .assistant(assistantState),
                    conversationCheckpointBeforeTurn: initial,
                    conversationCheckpointAfterTurn: committed
                ),
            ],
            userID,
            assistantID
        )
    }

    private static func twoCompletedTurns() -> (
        messages: [GraphChatTranscriptMessage],
        secondUserID: UUID,
        secondAssistantID: UUID
    ) {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let initial = GraphChatConversationCheckpoint.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        let firstCommitted = GraphChatConversationCheckpoint.committed(
            Self.conversationState(
                graphScope: graphScope,
                chatScope: chatScope,
                turnCount: 1
            )
        )
        let secondCommitted = GraphChatConversationCheckpoint.committed(
            Self.conversationState(
                graphScope: graphScope,
                chatScope: chatScope,
                turnCount: 2
            )
        )
        let first = Self.completedMessagePair(
            question: "First question",
            answer: "First answer",
            before: initial,
            after: firstCommitted
        )
        let second = Self.completedMessagePair(
            question: "Second question",
            answer: "Second answer",
            before: firstCommitted,
            after: secondCommitted
        )
        return (
            first.messages + second.messages,
            second.userID,
            second.assistantID
        )
    }

    private static func completedMessagePair(
        question: String,
        answer: String,
        before: GraphChatConversationCheckpoint,
        after: GraphChatConversationCheckpoint
    ) -> (
        messages: [GraphChatTranscriptMessage],
        userID: UUID,
        assistantID: UUID
    ) {
        let userID = UUID()
        let assistantID = UUID()
        var assistantState = GraphChatAssistantMessageState(
            question: question
        )
        assistantState.apply(
            .completed(
                GraphChatUITestSupport.finalAnswer(
                    directAnswer: answer
                )
            )
        )
        return (
            [
                GraphChatTranscriptMessage(
                    id: userID,
                    state: .userQuestion(question),
                    conversationCheckpointBeforeTurn: before
                ),
                GraphChatTranscriptMessage(
                    id: assistantID,
                    state: .assistant(assistantState),
                    conversationCheckpointBeforeTurn: before,
                    conversationCheckpointAfterTurn: after
                ),
            ],
            userID,
            assistantID
        )
    }

    private static func conversationState(
        graphScope: GraphScope,
        chatScope: GraphChatScope,
        turnCount: Int
    ) -> GraphChatConversationState {
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.turnContexts = (0..<turnCount).map { index in
            GraphChatConversationTurnContext(
                id: UUID(),
                completedAt: Date(timeIntervalSince1970: Double(index + 1)),
                toolKinds: [],
                resultContextIDs: [],
                evidenceIDs: [],
                technicalDescription: "Turn \(index + 1)"
            )
        }
        return state
    }

    private static func reScoped(
        _ messages: [GraphChatTranscriptMessage],
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) -> [GraphChatTranscriptMessage] {
        guard messages.isEmpty == false else {
            return []
        }
        let initial = GraphChatConversationCheckpoint.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        var latest = initial
        return messages.map { message in
            var result = message
            result.conversationCheckpointBeforeTurn = latest
            if message.conversationCheckpointAfterTurn != nil {
                let restoredTurnCount =
                    message.conversationCheckpointAfterTurn?
                    .state?
                    .turnContexts.count ?? 1
                let turnCount = max(1, restoredTurnCount)
                latest = GraphChatConversationCheckpoint.committed(
                    Self.conversationState(
                        graphScope: graphScope,
                        chatScope: chatScope,
                        turnCount: turnCount
                    )
                )
                result.conversationCheckpointAfterTurn = latest
            } else {
                result.conversationCheckpointAfterTurn = nil
            }
            return result
        }
    }

    private static func waitForTerminalGeneration(
        _ setup: GraphChatMessageActionControllerHarness
    ) async {
        await GraphChatUITestSupport.waitUntil(maximumYields: 20_000) {
            guard setup.generationController.isGenerating == false,
                  setup.isPerformingSessionMutation == false,
                  case .assistant(let state) = setup.messages.last?.state else {
                return false
            }
            return state.isTerminal
        }
    }
}
