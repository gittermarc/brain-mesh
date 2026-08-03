//
//  GraphChatMessageActionViewModelTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@MainActor
private final class GraphChatActionAccessDecisionBox {
    var decision: GraphChatAccessDecision

    init(decision: GraphChatAccessDecision = .readyForTests) {
        self.decision = decision
    }
}

private extension GraphChatAccessDecision {
    static let readyForTests = GraphChatAccessDecision(
        route: .ready,
        canPresentChat: true,
        canStartGeneration: true,
        canCancelGeneration: true,
        usesIndexFallback: false
    )

    static let graphLockedForTests = GraphChatAccessDecision(
        route: .graphLocked,
        canPresentChat: false,
        canStartGeneration: false,
        canCancelGeneration: true,
        usesIndexFallback: false
    )

    static let proRequiredForTests = GraphChatAccessDecision(
        route: .proRequired,
        canPresentChat: false,
        canStartGeneration: false,
        canCancelGeneration: true,
        usesIndexFallback: false
    )

    static let graphChangedForTests = GraphChatAccessDecision(
        route: .noActiveGraph,
        canPresentChat: false,
        canStartGeneration: false,
        canCancelGeneration: true,
        usesIndexFallback: false
    )
}

@Suite("Graph chat message action view model")
@MainActor
struct GraphChatMessageActionViewModelTests {
    @Test
    func starterSuggestionOnlyPrefillsComposerWithoutSending() async throws {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: []
        )
        await setup.viewModel.load()
        let suggestion = try #require(
            setup.viewModel.suggestions.first
        )

        setup.viewModel.useSuggestion(suggestion)

        let runtime = await setup.orchestrator.snapshot()
        #expect(
            setup.viewModel.composerState.text
                == suggestion.prompt
        )
        #expect(setup.viewModel.messages.isEmpty)
        #expect(runtime.questions.isEmpty)
    }

    @Test
    func copyWritesOnlyTheReadablePayloadAndAnnouncesSuccess() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "F2000000-0000-0000-0000-000000000001")!,
            summary: "Private graph source payload"
        )
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Lesbare Antwort",
                                evidence: [evidence]
                            )
                        )
                    ]
                )
            ]
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Frage")
        setup.viewModel.send()
        await Self.waitForTerminalAnswer(setup.viewModel)
        let assistantID = setup.viewModel.messages[1].id

        setup.viewModel.performMessageAction(.copy, messageID: assistantID)

        let copied = try #require(setup.clipboardWriter.values.last)
        #expect(copied.contains("Lesbare Antwort"))
        #expect(copied.contains("Quellenhinweis: 1 validierte Graphquelle"))
        #expect(copied.contains("Private graph source payload") == false)
        #expect(setup.accessibilityAnnouncer.announcements.last == "Antwort kopiert")
        #expect(setup.viewModel.actionNotice?.message == "Antwort kopiert")
    }

    @Test
    func feedbackCanBeSelectedChangedAndRemovedWithoutContentPersistence() async throws {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Antwort"
                            )
                        )
                    ]
                )
            ]
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Private Nutzerfrage")
        setup.viewModel.send()
        await Self.waitForTerminalAnswer(setup.viewModel)
        let assistantID = setup.viewModel.messages[1].id

        setup.viewModel.performMessageAction(
            .feedback(.helpful),
            messageID: assistantID
        )
        await Self.waitForFeedback(
            store: setup.feedbackStore,
            scope: setup.viewModel.chatScope,
            category: .helpful
        )
        #expect(setup.viewModel.feedbackCategory(for: assistantID) == .helpful)

        setup.viewModel.performMessageAction(
            .feedback(.incomplete),
            messageID: assistantID
        )
        await Self.waitForFeedback(
            store: setup.feedbackStore,
            scope: setup.viewModel.chatScope,
            category: .incomplete
        )
        let changedRecords = await setup.feedbackStore.records(
            for: setup.viewModel.chatScope
        )
        let changed = try #require(changedRecords.first)
        #expect(changed.localMessageID == assistantID)
        #expect(changed.category == .incomplete)
        #expect(changed.scopeType == .graph)
        #expect(changedRecords.count == 1)

        setup.viewModel.performMessageAction(
            .feedback(.incomplete),
            messageID: assistantID
        )
        await GraphChatProviderTestSupport.waitUntil {
            await setup.feedbackStore.records(for: setup.viewModel.chatScope).isEmpty
        }
        #expect(setup.viewModel.feedbackCategory(for: assistantID) == nil)
    }

    @Test
    func feedbackForAnEarlierAnswerRemainsSafeDuringAStreamingExchange() async {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Erste Antwort"
                            )
                        )
                    ]
                ),
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .partialAnswer("Zweite Antwort läuft")
                    ],
                    waitsForCancellation: true
                ),
            ]
        )
        await setup.viewModel.load()
        await Self.send("Erste Frage", through: setup.viewModel)
        let firstAssistantID = setup.viewModel.messages[1].id

        setup.viewModel.setComposerText("Zweite Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            guard setup.viewModel.messages.count == 4,
                  case .assistant(let state) = setup.viewModel.messages[3].state else {
                return false
            }
            return state.phase == .partial
        }
        setup.viewModel.performMessageAction(
            .feedback(.helpful),
            messageID: firstAssistantID
        )
        await Self.waitForFeedback(
            store: setup.feedbackStore,
            scope: setup.viewModel.chatScope,
            category: .helpful
        )

        #expect(setup.viewModel.feedbackCategory(for: firstAssistantID) == .helpful)
        #expect(setup.viewModel.isGenerating)
        #expect(setup.viewModel.messages.count == 4)
        setup.viewModel.cancelGeneration()
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isGenerating == false
                && setup.viewModel.isPerformingSessionMutation == false
        }
    }

    @Test
    func loadingHistoryRestoresTheLatestTrustedConversationCheckpoint() async {
        let graphID = UUID()
        let graphScope = GraphScope(graphID: graphID)
        let chatScope = GraphChatScope.entity(UUID(), in: graphScope)
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.turnContexts = [
            GraphChatConversationTurnContext(
                id: UUID(),
                completedAt: Date(timeIntervalSince1970: 20),
                toolKinds: [.getNode],
                resultContextIDs: [],
                evidenceIDs: [],
                technicalDescription: "Trusted restored turn"
            )
        ]
        let initial = GraphChatConversationCheckpoint.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        let committed = GraphChatConversationCheckpoint.committed(state)
        var assistantState = GraphChatAssistantMessageState(question: "Gespeicherte Frage")
        assistantState.apply(
            .completed(
                GraphChatUITestSupport.finalAnswer(
                    directAnswer: "Gespeicherte Antwort"
                )
            )
        )
        let historyStore = InMemoryGraphChatHistoryStore()
        await historyStore.save(
            [
                GraphChatTranscriptMessage(
                    state: .userQuestion("Gespeicherte Frage"),
                    conversationCheckpointBeforeTurn: initial
                ),
                GraphChatTranscriptMessage(
                    state: .assistant(assistantState),
                    conversationCheckpointBeforeTurn: initial,
                    conversationCheckpointAfterTurn: committed
                ),
            ],
            for: chatScope
        )
        let setup = GraphChatUITestSupport.makeViewModel(
            graphID: graphID,
            chatScope: chatScope,
            scripts: [],
            historyStore: historyStore
        )

        await setup.viewModel.load()

        let snapshot = await setup.orchestrator.snapshot()
        #expect(setup.viewModel.messages.count == 2)
        #expect(setup.viewModel.chatScope == chatScope)
        #expect(snapshot.restoredCheckpoints == [committed])
        #expect(snapshot.conversationState == state)
    }

    @Test
    func editAndResendRemovesTheFollowingBranchAndRestoresTrustedState() async throws {
        let historyStore = InMemoryGraphChatHistoryStore()
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Erste Antwort"
                            )
                        )
                    ]
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Veraltete zweite Antwort"
                            )
                        )
                    ]
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Neue zweite Antwort"
                            )
                        )
                    ]
                ),
            ],
            historyStore: historyStore
        )
        await setup.viewModel.load()
        await Self.send("Erste Frage", through: setup.viewModel)
        await Self.send("Alte zweite Frage", through: setup.viewModel)

        let retainedIDs = setup.viewModel.messages.prefix(2).map(\.id)
        let editedUserID = setup.viewModel.messages[2].id
        let staleAssistantID = setup.viewModel.messages[3].id
        setup.viewModel.performMessageAction(
            .feedback(.wrongSource),
            messageID: staleAssistantID
        )
        await Self.waitForFeedback(
            store: setup.feedbackStore,
            scope: setup.viewModel.chatScope,
            category: .wrongSource
        )

        setup.viewModel.performMessageAction(
            .editAndResend,
            messageID: editedUserID
        )
        #expect(setup.viewModel.editingState?.userMessageID == editedUserID)
        #expect(setup.viewModel.composerState.text == "Alte zweite Frage")
        setup.viewModel.setComposerText("Neue zweite Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isGenerating == false
                && setup.viewModel.isPerformingSessionMutation == false
                && setup.viewModel.messages.count == 4
        }

        #expect(setup.viewModel.messages.prefix(2).map(\.id) == retainedIDs)
        #expect(setup.viewModel.messages.contains(where: { $0.id == editedUserID }) == false)
        #expect(setup.viewModel.messages.contains(where: { $0.id == staleAssistantID }) == false)
        guard case .userQuestion(let replacementQuestion) = setup.viewModel.messages[2].state,
              case .assistant(let replacementAnswer) = setup.viewModel.messages[3].state else {
            Issue.record("Expected replacement branch.")
            return
        }
        #expect(replacementQuestion == "Neue zweite Frage")
        #expect(replacementAnswer.text == "Neue zweite Antwort")
        #expect(setup.viewModel.editingState == nil)
        #expect(await setup.feedbackStore.records(for: setup.viewModel.chatScope).isEmpty)
        #expect(await historyStore.messages(for: setup.viewModel.chatScope) == setup.viewModel.messages)

        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.questions == [
            "Erste Frage",
            "Alte zweite Frage",
            "Neue zweite Frage",
        ])
        #expect(snapshot.restoredCheckpoints.last?.state?.turnContexts.count == 1)
        #expect(snapshot.conversationState?.turnContexts.count == 2)
        #expect(
            snapshot.conversationState?.turnContexts.contains(where: {
                $0.technicalDescription.contains("Alte zweite Frage")
            }) == false
        )
    }

    @Test
    func editDuringStreamingCancelsBeforeExecutingTheReplacementBranch() async {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .partialAnswer("Veralteter Teil")
                    ],
                    waitsForCancellation: true
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Neue Antwort"
                            )
                        )
                    ]
                ),
            ]
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Alte Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            guard setup.viewModel.messages.count == 2,
                  case .assistant(let state) = setup.viewModel.messages[1].state else {
                return false
            }
            return state.phase == .partial
        }
        let originalUserID = setup.viewModel.messages[0].id

        setup.viewModel.performMessageAction(
            .editAndResend,
            messageID: originalUserID
        )
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isPerformingSessionMutation == false
                && setup.viewModel.isGenerating == false
        }
        setup.viewModel.setComposerText("Neue Frage")
        setup.viewModel.send()
        await Self.waitForTerminalAnswer(setup.viewModel)

        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.cancellationCount >= 1)
        #expect(snapshot.questions == ["Alte Frage", "Neue Frage"])
        #expect(setup.viewModel.messages.count == 2)
        guard case .userQuestion(let question) = setup.viewModel.messages[0].state,
              case .assistant(let answer) = setup.viewModel.messages[1].state else {
            Issue.record("Expected replacement conversation.")
            return
        }
        #expect(question == "Neue Frage")
        #expect(answer.text == "Neue Antwort")
    }

    @Test
    func regenerateReusesTheQuestionRevalidatesSourcesAndDoesNotDuplicateState() async throws {
        let oldEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "F3000000-0000-0000-0000-000000000001")!
        )
        let newEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "F3000000-0000-0000-0000-000000000002")!
        )
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Alte Antwort",
                                evidence: [oldEvidence]
                            )
                        )
                    ]
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Neue Antwort",
                                evidence: [newEvidence]
                            )
                        )
                    ]
                ),
            ]
        )
        await setup.viewModel.load()
        await Self.send("Gleiche Frage", through: setup.viewModel)
        let userID = setup.viewModel.messages[0].id
        let assistantID = setup.viewModel.messages[1].id
        setup.viewModel.performMessageAction(
            .feedback(.helpful),
            messageID: assistantID
        )
        await Self.waitForFeedback(
            store: setup.feedbackStore,
            scope: setup.viewModel.chatScope,
            category: .helpful
        )

        setup.viewModel.performMessageAction(
            .regenerate,
            messageID: assistantID
        )
        await GraphChatUITestSupport.waitUntil {
            guard setup.viewModel.isGenerating == false,
                  setup.viewModel.messages.count == 2,
                  case .assistant(let state) = setup.viewModel.messages[1].state else {
                return false
            }
            return state.text == "Neue Antwort"
        }

        #expect(setup.viewModel.messages.map(\.id) == [userID, assistantID])
        guard case .assistant(let regenerated) = setup.viewModel.messages[1].state else {
            Issue.record("Expected regenerated answer.")
            return
        }
        #expect(regenerated.answer?.evidence.map(\.id) == [newEvidence.id])
        #expect(regenerated.answer?.evidence.contains(where: { $0.id == oldEvidence.id }) == false)
        #expect(setup.viewModel.feedbackCategory(for: assistantID) == nil)
        #expect(await setup.feedbackStore.records(for: setup.viewModel.chatScope).isEmpty)

        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.questions == ["Gleiche Frage", "Gleiche Frage"])
        #expect(snapshot.restoredCheckpoints.last?.state == nil)
        #expect(snapshot.conversationState?.turnContexts.count == 1)
    }

    @Test
    func regenerateDuringStreamingCancelsTheOldRunAndRapidTapsDoNotDuplicateRequests() async {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .partialAnswer("Alter Streaming-Teil")
                    ],
                    waitsForCancellation: true
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Regenerierte Antwort"
                            )
                        )
                    ]
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Darf nicht gestartet werden"
                            )
                        )
                    ]
                ),
            ]
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Streaming-Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            guard setup.viewModel.messages.count == 2,
                  case .assistant(let state) = setup.viewModel.messages[1].state else {
                return false
            }
            return state.phase == .partial
        }
        let assistantID = setup.viewModel.messages[1].id

        setup.viewModel.performMessageAction(.regenerate, messageID: assistantID)
        setup.viewModel.performMessageAction(.regenerate, messageID: assistantID)
        await GraphChatUITestSupport.waitUntil {
            guard setup.viewModel.isGenerating == false,
                  case .assistant(let state) = setup.viewModel.messages[1].state else {
                return false
            }
            return state.text == "Regenerierte Antwort"
        }

        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.questions == ["Streaming-Frage", "Streaming-Frage"])
        #expect(snapshot.cancellationCount >= 1)
        #expect(setup.viewModel.messages.count == 2)
        #expect(setup.viewModel.messages[1].id == assistantID)
    }

    @Test
    func graphChangeDuringRegenerationPreventsAStaleReplacement() async {
        let access = GraphChatActionAccessDecisionBox()
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Gültige alte Antwort"
                            )
                        )
                    ]
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Veraltete neue Antwort"
                            )
                        )
                    ]
                ),
            ],
            restoreDelayNanoseconds: 40_000_000,
            accessDecisionProvider: { access.decision }
        )
        await setup.viewModel.load()
        await Self.send("Frage", through: setup.viewModel)
        let assistantID = setup.viewModel.messages[1].id

        setup.viewModel.performMessageAction(.regenerate, messageID: assistantID)
        access.decision = .graphChangedForTests
        setup.viewModel.notifyGenerationAccessChanged()
        try? await Task.sleep(nanoseconds: 80_000_000)
        await GraphChatUITestSupport.waitUntil(maximumYields: 20_000) {
            setup.viewModel.isGenerating == false
                && setup.viewModel.isPerformingSessionMutation == false
        }

        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.questions == ["Frage"])
        #expect(setup.viewModel.messages.count == 2)
        guard case .assistant(let state) = setup.viewModel.messages[1].state else {
            Issue.record("Expected retained assistant answer.")
            return
        }
        #expect(state.text == "Gültige alte Antwort")
    }

    @Test
    func newChatDuringToolExecutionCancelsTasksAndRetainsGraphAndScope() async {
        let graphID = UUID()
        let graphScope = GraphScope(graphID: graphID)
        let schemaContext = GraphChatTestSupport.makeSchemaContext(graphID: graphID)
        guard let entityID = schemaContext.aliases.entitiesByAlias.values.first?.entityID else {
            Issue.record("Expected a fake schema entity.")
            return
        }
        let entityScope = GraphChatScope.entity(entityID, in: graphScope)
        let historyStore = InMemoryGraphChatHistoryStore()
        let setup = GraphChatUITestSupport.makeViewModel(
            graphID: graphID,
            chatScope: entityScope,
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .toolActivity(
                            GraphChatToolActivity(
                                tool: .searchGraph,
                                state: .started
                            )
                        )
                    ],
                    waitsForCancellation: true
                )
            ],
            historyStore: historyStore,
            schemaContext: schemaContext
        )
        await setup.viewModel.load()
        let originalGraphScope = setup.viewModel.graphScope
        let originalChatScope = setup.viewModel.chatScope
        setup.viewModel.setComposerText("Laufende Tool-Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            guard setup.viewModel.messages.count == 2,
                  case .assistant(let state) = setup.viewModel.messages[1].state else {
                return false
            }
            return state.toolActivities.isEmpty == false
        }

        setup.viewModel.performChatAction(.startNewChat)
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isPerformingSessionMutation == false
                && setup.viewModel.messages.isEmpty
        }

        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.cancellationCount >= 1)
        #expect(snapshot.discardReasons.last == .newConversation)
        #expect(snapshot.conversationState == nil)
        #expect(await historyStore.messages(for: originalChatScope).isEmpty)
        #expect(setup.viewModel.graphScope == originalGraphScope)
        #expect(setup.viewModel.chatScope == originalChatScope)
        #expect(setup.viewModel.editingState == nil)
        #expect(setup.viewModel.composerState.text.isEmpty)
        #expect(setup.viewModel.suggestions.isEmpty == false)
    }

    @Test
    func newChatClearsPendingClarificationFeedbackAndHistoryWhileKeepingGraphLock() async throws {
        let access = GraphChatActionAccessDecisionBox()
        let historyStore = InMemoryGraphChatHistoryStore()
        let clarification = GraphChatClarification(
            id: UUID(),
            question: "Welchen Eintrag meinst du?",
            options: [
                GraphChatClarificationOption(id: "one", title: "Eintrag 1"),
                GraphChatClarificationOption(id: "two", title: "Eintrag 2"),
            ]
        )
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                state: .clarification(clarification),
                                directAnswer: clarification.question
                            )
                        )
                    ]
                )
            ],
            historyStore: historyStore,
            accessDecisionProvider: { access.decision }
        )
        await setup.viewModel.load()
        await Self.send("Mehrdeutige Frage", through: setup.viewModel)
        let assistantID = setup.viewModel.messages[1].id
        setup.viewModel.performMessageAction(
            .feedback(.misunderstoodQuestion),
            messageID: assistantID
        )
        await Self.waitForFeedback(
            store: setup.feedbackStore,
            scope: setup.viewModel.chatScope,
            category: .misunderstoodQuestion
        )
        #expect(await setup.orchestrator.snapshot().conversationState?.pendingClarification != nil)

        access.decision = .graphLockedForTests
        setup.viewModel.notifyGenerationAccessChanged()
        setup.viewModel.performChatAction(.startNewChat)
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isPerformingSessionMutation == false
        }

        #expect(setup.viewModel.messages.isEmpty)
        #expect(setup.viewModel.feedbackByMessageID.isEmpty)
        #expect(await setup.feedbackStore.records(for: setup.viewModel.chatScope).isEmpty)
        #expect(await historyStore.messages(for: setup.viewModel.chatScope).isEmpty)
        #expect(await setup.orchestrator.snapshot().conversationState == nil)
        setup.viewModel.setComposerText("Neue Frage")
        #expect(setup.viewModel.canSend == false)
        #expect(setup.viewModel.graphScope == setup.viewModel.chatScope.graphScope)
    }

    @Test
    func newChatDoesNotBypassTheProGate() async {
        let access = GraphChatActionAccessDecisionBox()
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Antwort vor Gate-Wechsel"
                            )
                        )
                    ]
                )
            ],
            accessDecisionProvider: { access.decision }
        )
        await setup.viewModel.load()
        await Self.send("Frage", through: setup.viewModel)

        access.decision = .proRequiredForTests
        setup.viewModel.notifyGenerationAccessChanged()
        setup.viewModel.performChatAction(.startNewChat)
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isPerformingSessionMutation == false
        }
        setup.viewModel.setComposerText("Neue Frage")

        #expect(setup.viewModel.messages.isEmpty)
        #expect(setup.viewModel.canSend == false)
        #expect(setup.viewModel.graphScope == setup.viewModel.chatScope.graphScope)
    }

    private static func send(
        _ question: String,
        through viewModel: GraphChatViewModel
    ) async {
        viewModel.setComposerText(question)
        viewModel.send()
        await waitForTerminalAnswer(viewModel)
    }

    private static func waitForTerminalAnswer(
        _ viewModel: GraphChatViewModel
    ) async {
        await GraphChatUITestSupport.waitUntil {
            guard viewModel.isGenerating == false,
                  viewModel.messages.isEmpty == false,
                  case .assistant(let state) = viewModel.messages.last?.state else {
                return false
            }
            return state.isTerminal
        }
    }

    private static func waitForFeedback(
        store: any GraphChatFeedbackStoring,
        scope: GraphChatScope,
        category: GraphChatFeedbackCategory
    ) async {
        await GraphChatProviderTestSupport.waitUntil {
            await store.records(for: scope).contains(where: {
                $0.category == category
            })
        }
    }
}
