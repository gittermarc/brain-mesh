import Foundation
import Testing

@testable import BrainMesh

@MainActor
struct GraphChatViewModelTests {
    @Test
    func sendStreamsEventsIntoOneAssistantMessageInOrder() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "E0000000-0000-0000-0000-000000000001")!,
            summary: "Projekt Atlas ist offen"
        )
        let activityID = UUID()
        let answer = GraphChatUITestSupport.finalAnswer(
            directAnswer: "Projekt Atlas ist offen.",
            evidence: [evidence],
            filters: [
                GraphChatAppliedFilter(
                    fieldName: "Status",
                    operationDescription: "entspricht",
                    valueDescription: "Offen"
                )
            ],
            followUps: [
                GraphChatFollowUpSuggestion(
                    title: "Aufgaben anzeigen",
                    prompt: "Welche Aufgaben sind offen?"
                )
            ]
        )
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .toolActivity(
                            GraphChatToolActivity(
                                id: activityID,
                                tool: .searchGraph,
                                state: .started
                            )
                        ),
                        .partialAnswer("Projekt Atlas"),
                        .toolActivity(
                            GraphChatToolActivity(
                                id: activityID,
                                tool: .searchGraph,
                                state: .finished
                            )
                        ),
                        .completed(answer),
                    ]
                )
            ]
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("  Wie ist der Status von Atlas?  ")

        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isGenerating == false
                && setup.viewModel.messages.count == 2
        }

        #expect(setup.viewModel.composerState.text.isEmpty)
        #expect(setup.viewModel.messages.count == 2)
        guard case .userQuestion(let question) = setup.viewModel.messages[0].state else {
            Issue.record("Expected a user question.")
            return
        }
        #expect(question == "Wie ist der Status von Atlas?")

        guard case .assistant(let assistant) = setup.viewModel.messages[1].state else {
            Issue.record("Expected an assistant message.")
            return
        }
        #expect(assistant.phase == .final)
        #expect(assistant.text == "Projekt Atlas ist offen.")
        #expect(assistant.toolActivities.count == 1)
        #expect(assistant.toolActivities.first?.state == .finished)
        #expect(assistant.answer?.appliedFilters.first?.valueDescription == "Offen")
        #expect(assistant.answer?.followUpSuggestions.first?.prompt == "Welche Aufgaben sind offen?")

        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.questions == ["Wie ist der Status von Atlas?"])
    }

    @Test
    func whitespaceAndUnavailableModelKeepSendDisabled() async {
        let unavailable = GraphChatUITestSupport.makeViewModel(
            scripts: [],
            availability: .unavailable(.appleIntelligenceNotEnabled)
        )
        await unavailable.viewModel.load()
        unavailable.viewModel.setComposerText("Frage")

        #expect(unavailable.viewModel.canSend == false)
        unavailable.viewModel.send()
        #expect(unavailable.viewModel.messages.isEmpty)

        let available = GraphChatUITestSupport.makeViewModel(scripts: [])
        await available.viewModel.load()
        available.viewModel.setComposerText(" \n ")

        #expect(available.viewModel.canSend == false)
        available.viewModel.send()
        #expect(available.viewModel.messages.isEmpty)
    }

    @Test
    func cancellationStopsGenerationAndMarksPartialAnswerCancelled() async {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .partialAnswer("Bereits erzeugter Teil"),
                    ],
                    waitsForCancellation: true
                )
            ]
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Lange Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            guard setup.viewModel.messages.count == 2,
                case .assistant(let state) = setup.viewModel.messages[1].state
            else {
                return false
            }
            return state.phase == .partial
        }

        setup.viewModel.cancelGeneration()
        await GraphChatProviderTestSupport.waitUntil {
            await setup.orchestrator.snapshot().cancellationCount > 0
        }

        #expect(setup.viewModel.isGenerating == false)
        guard case .assistant(let state) = setup.viewModel.messages[1].state else {
            Issue.record("Expected an assistant message.")
            return
        }
        #expect(state.phase == .cancelled)
        #expect(state.text == "Bereits erzeugter Teil")
    }

    @Test
    func technicalFailureCanRetryWithoutDuplicatingUserQuestion() async {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .failure(
                            GraphChatError(
                                code: .toolFailure,
                                message: "Indexabfrage fehlgeschlagen",
                                recoverySuggestion: "Erneut versuchen."
                            )
                        )
                    ]
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Retry erfolgreich.",
                                evidence: [GraphChatProviderTestSupport.makeEvidence()]
                            )
                        )
                    ]
                ),
            ]
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Retry-Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isGenerating == false
                && setup.viewModel.messages.count == 2
        }
        let assistantID = setup.viewModel.messages[1].id
        guard case .assistant(let failedState) = setup.viewModel.messages[1].state else {
            Issue.record("Expected an assistant message.")
            return
        }
        #expect(failedState.phase == .technicalError)

        setup.viewModel.retry(messageID: assistantID)
        await GraphChatUITestSupport.waitUntil {
            guard setup.viewModel.isGenerating == false,
                case .assistant(let state) = setup.viewModel.messages[1].state
            else {
                return false
            }
            return state.phase == .final
        }

        #expect(setup.viewModel.messages.count == 2)
        guard case .assistant(let retriedState) = setup.viewModel.messages[1].state else {
            Issue.record("Expected an assistant message.")
            return
        }
        #expect(retriedState.text == "Retry erfolgreich.")
        #expect(await setup.orchestrator.snapshot().questions == ["Retry-Frage", "Retry-Frage"])
    }

    @Test
    func noResultsAndAvailabilityFailuresReceiveDedicatedStates() async {
        let noResultsSetup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                state: .noResults,
                                directAnswer: "Keine passenden Daten.",
                                insufficient: true
                            )
                        )
                    ]
                )
            ]
        )
        await noResultsSetup.viewModel.load()
        noResultsSetup.viewModel.setComposerText("Unbekannte Frage")
        noResultsSetup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            noResultsSetup.viewModel.isGenerating == false
                && noResultsSetup.viewModel.messages.count == 2
        }
        guard case .assistant(let noResultsState) = noResultsSetup.viewModel.messages[1].state else {
            Issue.record("Expected no-results assistant message.")
            return
        }
        #expect(noResultsState.phase == .noResults)

        let availabilitySetup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .failure(
                            GraphChatError(
                                code: .modelUnavailable,
                                message: "Lokales Modell nicht verfügbar"
                            )
                        )
                    ]
                )
            ]
        )
        await availabilitySetup.viewModel.load()
        availabilitySetup.viewModel.setComposerText("Frage")
        availabilitySetup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            availabilitySetup.viewModel.isGenerating == false
                && availabilitySetup.viewModel.messages.count == 2
        }
        guard case .assistant(let availabilityState) = availabilitySetup.viewModel.messages[1].state
        else {
            Issue.record("Expected availability assistant message.")
            return
        }
        #expect(availabilityState.phase == .availabilityError)
        #expect(
            availabilitySetup.viewModel.availabilityState
                == .unavailable(reason: .unknown)
        )
    }

    @Test
    func runtimeHeaderStatesExposeBuildingAndFailedIndex() async {
        let building = GraphChatUITestSupport.makeViewModel(
            scripts: [],
            indexState: .building(
                processed: 10,
                estimated: 40,
                documentCount: 8
            )
        )
        await building.viewModel.load()
        #expect(
            building.viewModel.indexState
                == .building(processed: 10, estimated: 40, documentCount: 8)
        )

        let failed = GraphChatUITestSupport.makeViewModel(
            scripts: [],
            indexState: .failed(
                message: "SQLite nicht verfügbar",
                isUsable: false,
                documentCount: nil
            )
        )
        await failed.viewModel.load()
        #expect(
            failed.viewModel.indexState
                == .failed(
                    message: "SQLite nicht verfügbar",
                    isUsable: false,
                    documentCount: nil
                )
        )
    }

    @Test
    func followUpSuggestionFillsComposerWithoutSending() async {
        let followUp = GraphChatFollowUpSuggestion(
            title: "Details",
            prompt: "Zeige mir die Details."
        )
        let setup = GraphChatUITestSupport.makeViewModel(scripts: [])
        await setup.viewModel.load()

        setup.viewModel.useFollowUp(followUp)

        #expect(setup.viewModel.composerState.text == "Zeige mir die Details.")
        #expect(setup.viewModel.messages.isEmpty)
        #expect(await setup.orchestrator.snapshot().questions.isEmpty)
    }

    @Test
    func inMemoryHistoryIsSeparatedByGraphAndScope() async {
        let historyStore = InMemoryGraphChatHistoryStore()
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let entityScope = GraphChatScope.entity(
            GraphChatTestSupport.projectEntityID,
            in: graphScope
        )
        let answer = GraphChatUITestSupport.finalAnswer(
            directAnswer: "Gespeicherte Antwort",
            evidence: [GraphChatProviderTestSupport.makeEvidence()]
        )
        let first = GraphChatUITestSupport.makeViewModel(
            chatScope: .entireGraph(graphScope),
            scripts: [
                GraphChatUIFakeScript(events: [.completed(answer)])
            ],
            historyStore: historyStore
        )
        await first.viewModel.load()
        first.viewModel.setComposerText("Gespeicherte Frage")
        first.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            first.viewModel.isGenerating == false
                && first.viewModel.messages.count == 2
        }

        let sameScope = GraphChatUITestSupport.makeViewModel(
            chatScope: .entireGraph(graphScope),
            scripts: [],
            historyStore: historyStore
        )
        await sameScope.viewModel.load()
        #expect(sameScope.viewModel.messages.count == 2)

        let otherScope = GraphChatUITestSupport.makeViewModel(
            chatScope: entityScope,
            scripts: [],
            historyStore: historyStore
        )
        await otherScope.viewModel.load()
        #expect(otherScope.viewModel.messages.isEmpty)

        let otherGraph = GraphChatUITestSupport.makeViewModel(
            graphID: GraphChatTestSupport.otherGraphID,
            scripts: [],
            historyStore: historyStore
        )
        await otherGraph.viewModel.load()
        #expect(otherGraph.viewModel.messages.isEmpty)
    }

    @Test
    func viewDisappearanceCancelsAndDiscardsSession() async {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [.started(requestID: UUID())],
                    waitsForCancellation: true
                )
            ]
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isGenerating
        }

        setup.viewModel.viewDidDisappear()
        await GraphChatProviderTestSupport.waitUntil {
            let snapshot = await setup.orchestrator.snapshot()
            return snapshot.cancellationCount > 0 && snapshot.discardCount > 0
        }

        #expect(setup.viewModel.isGenerating == false)
    }

    @Test
    func oneOfTwoPresentationsCanCloseWithoutCancellingTheSharedStream() async {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [.started(requestID: UUID())],
                    waitsForCancellation: true
                )
            ]
        )
        let firstPresentationID = UUID()
        let secondPresentationID = UUID()
        setup.viewModel.presentationDidAppear(firstPresentationID)
        setup.viewModel.presentationDidAppear(secondPresentationID)
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isGenerating
        }

        setup.viewModel.presentationDidDisappear(firstPresentationID)
        for _ in 0..<20 {
            await Task.yield()
        }

        let whileSecondHostIsVisible = await setup.orchestrator.snapshot()
        #expect(whileSecondHostIsVisible.cancellationCount == 0)
        #expect(setup.viewModel.isGenerating)

        setup.viewModel.presentationDidDisappear(secondPresentationID)
        await GraphChatProviderTestSupport.waitUntil {
            let snapshot = await setup.orchestrator.snapshot()
            return snapshot.cancellationCount > 0
        }

        let afterLastHostClosed = await setup.orchestrator.snapshot()
        #expect(afterLastHostClosed.discardCount == 0)
        #expect(setup.viewModel.isGenerating == false)
    }

    @Test
    func reopeningBeforePresentationCleanupKeepsTheRunningStreamAlive() async {
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [
                GraphChatUIFakeScript(
                    events: [.started(requestID: UUID())],
                    waitsForCancellation: true
                )
            ]
        )
        let firstPresentationID = UUID()
        let reopenedPresentationID = UUID()
        setup.viewModel.presentationDidAppear(firstPresentationID)
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Frage")
        setup.viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            setup.viewModel.isGenerating
        }

        setup.viewModel.presentationDidDisappear(firstPresentationID)
        setup.viewModel.presentationDidAppear(reopenedPresentationID)
        for _ in 0..<20 {
            await Task.yield()
        }

        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.cancellationCount == 0)
        #expect(snapshot.discardCount == 0)
        #expect(setup.viewModel.isGenerating)

        setup.viewModel.presentationDidDisappear(reopenedPresentationID)
        await GraphChatProviderTestSupport.waitUntil {
            let snapshot = await setup.orchestrator.snapshot()
            return snapshot.cancellationCount > 0
        }
    }

    @Test
    func newChatClearsWorkspaceDerivedStateExactlyOnce() async {
        var cleanupCount = 0
        let setup = GraphChatUITestSupport.makeViewModel(
            scripts: [],
            sessionDerivedStateDidClear: {
                cleanupCount += 1
            }
        )
        await setup.viewModel.load()
        setup.viewModel.setComposerText("Draft")

        await setup.viewModel.clearHistory()

        #expect(cleanupCount == 1)
        #expect(setup.viewModel.messages.isEmpty)
        #expect(setup.viewModel.composerState.text.isEmpty)
        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.discardReasons.last == .newConversation)
    }

}
