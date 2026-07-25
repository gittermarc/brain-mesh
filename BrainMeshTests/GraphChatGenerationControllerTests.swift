//
//  GraphChatGenerationControllerTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

private nonisolated struct RecordedGraphChatGenerationEvent: Hashable, Sendable {
    let operationID: GraphChatGenerationOperationID
    let assistantMessageID: UUID
    let event: GraphChatStreamEvent
}

private nonisolated struct RecordedGraphChatGenerationOutcome: Hashable, Sendable {
    let operationID: GraphChatGenerationOperationID
    let assistantMessageID: UUID
    let outcome: GraphChatGenerationOutcome
}

@MainActor
private final class GraphChatGenerationCallbackRecorder {
    private(set) var messages: [GraphChatTranscriptMessage]
    private(set) var events: [RecordedGraphChatGenerationEvent] = []
    private(set) var outcomes: [RecordedGraphChatGenerationOutcome] = []
    private(set) var cancelledOperationIDs: [GraphChatGenerationOperationID] = []
    private(set) var completedTurnOperationIDs: [GraphChatGenerationOperationID] = []
    private(set) var visibleStateChanges: [Bool] = []

    init(assistantMessageIDs: [UUID]) {
        messages = assistantMessageIDs.map { messageID in
            GraphChatTranscriptMessage(
                id: messageID,
                state: .assistant(
                    GraphChatAssistantMessageState(
                        question: "Question \(messageID.uuidString.prefix(4))"
                    )
                )
            )
        }
    }

    func callbacks() -> GraphChatGenerationCallbacks {
        GraphChatGenerationCallbacks(
            messageSnapshot: { [weak self] in
                self?.messages ?? []
            },
            operationWillCancel: { [weak self] operationID, assistantMessageID in
                guard let self else {
                    return
                }
                cancelledOperationIDs.append(operationID)
                mutateAssistant(assistantMessageID) { state in
                    state.markCancelled()
                }
            },
            eventDidArrive: { [weak self] event, operationID, assistantMessageID in
                guard let self else {
                    return
                }
                events.append(
                    RecordedGraphChatGenerationEvent(
                        operationID: operationID,
                        assistantMessageID: assistantMessageID,
                        event: event
                    )
                )
                mutateAssistant(assistantMessageID) { state in
                    state.apply(event)
                }
            },
            completedTurnDidArrive: { [weak self] operationID, _ in
                self?.completedTurnOperationIDs.append(operationID)
            },
            outcomeDidResolve: { [weak self] operationID, assistantMessageID, outcome in
                self?.outcomes.append(
                    RecordedGraphChatGenerationOutcome(
                        operationID: operationID,
                        assistantMessageID: assistantMessageID,
                        outcome: outcome
                    )
                )
            },
            generationStateDidChange: { [weak self] isGenerating in
                self?.visibleStateChanges.append(isGenerating)
            }
        )
    }

    func assistantState(
        for messageID: UUID
    ) -> GraphChatAssistantMessageState? {
        guard let message = messages.first(where: { $0.id == messageID }),
              case .assistant(let state) = message.state else {
            return nil
        }
        return state
    }

    private func mutateAssistant(
        _ messageID: UUID,
        mutation: (inout GraphChatAssistantMessageState) -> Void
    ) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              case .assistant(var state) = messages[index].state else {
            return
        }
        mutation(&state)
        messages[index].state = .assistant(state)
    }
}

private actor GraphChatGenerationHistoryRecorder: GraphChatHistoryStoring {
    private var storedMessages: [GraphChatScope: [GraphChatTranscriptMessage]] = [:]
    private var saves: [
        (
            scope: GraphChatScope,
            messages: [GraphChatTranscriptMessage]
        )
    ] = []

    func messages(
        for scope: GraphChatScope
    ) -> [GraphChatTranscriptMessage] {
        storedMessages[scope, default: []]
    }

    func save(
        _ messages: [GraphChatTranscriptMessage],
        for scope: GraphChatScope
    ) {
        storedMessages[scope] = messages
        saves.append((scope, messages))
    }

    func removeMessages(for scope: GraphChatScope) {
        storedMessages.removeValue(forKey: scope)
    }

    func snapshots() -> [[GraphChatTranscriptMessage]] {
        saves.map { $0.messages }
    }

    func scopes() -> [GraphChatScope] {
        saves.map { $0.scope }
    }
}

private actor GraphChatGenerationObservabilityRecorder:
    GraphChatObservabilityRecording
{
    private var events: [GraphChatObservabilityEvent] = []

    func record(_ event: GraphChatObservabilityEvent) {
        events.append(event)
    }

    func requestMetrics() -> [GraphChatRequestMetric] {
        events.compactMap { event in
            guard case .request(let metric) = event else {
                return nil
            }
            return metric
        }
    }
}

@MainActor
private final class GraphChatGenerationOperationIDSequence {
    private(set) var generatedCount = 0
    private var values: [GraphChatGenerationOperationID]

    init(_ values: [GraphChatGenerationOperationID]) {
        self.values = values
    }

    func next() -> GraphChatGenerationOperationID {
        generatedCount += 1
        precondition(values.isEmpty == false)
        return values.removeFirst()
    }
}

@MainActor
private struct GraphChatGenerationControllerSetup {
    let controller: GraphChatGenerationController
    let orchestrator: GraphChatUIFakeOrchestrator
    let history: GraphChatGenerationHistoryRecorder
    let observability: GraphChatGenerationObservabilityRecorder
    let callbacks: GraphChatGenerationCallbackRecorder
    let operationIDs: GraphChatGenerationOperationIDSequence
    let chatScope: GraphChatScope
}

@Suite("Graph chat generation controller")
@MainActor
struct GraphChatGenerationControllerTests {
    @Test
    func startCreatesOneTypedOperationAndPublishesOneVisibleStart() async {
        let assistantID = UUID()
        let operationID = GraphChatGenerationOperationID()
        let setup = makeSetup(
            assistantMessageIDs: [assistantID],
            operationIDs: [operationID],
            scripts: [
                GraphChatUIFakeScript(
                    events: [.started(requestID: UUID())],
                    waitsForCancellation: true
                )
            ]
        )

        let returnedID = setup.controller.start(
            request(
                question: "First",
                assistantMessageID: assistantID,
                mode: .newTurn
            )
        )

        #expect(returnedID == operationID)
        #expect(setup.operationIDs.generatedCount == 1)
        #expect(
            setup.controller.state
                == .generating(
                    GraphChatActiveGeneration(
                        operationID: operationID,
                        assistantMessageID: assistantID,
                        mode: .newTurn
                    )
                )
        )
        #expect(setup.callbacks.visibleStateChanges == [true])

        let cleanup = setup.controller.cancel(discardSession: false)
        await cleanup?.value
    }

    @Test
    func replacementWaitsForTheOldTaskAndCannotBeFinishedByIt() async {
        let firstAssistantID = UUID()
        let secondAssistantID = UUID()
        let firstOperationID = GraphChatGenerationOperationID()
        let secondOperationID = GraphChatGenerationOperationID()
        let setup = makeSetup(
            assistantMessageIDs: [firstAssistantID, secondAssistantID],
            operationIDs: [firstOperationID, secondOperationID],
            scripts: [
                GraphChatUIFakeScript(
                    events: [.started(requestID: UUID())],
                    waitsForCancellation: true
                ),
                GraphChatUIFakeScript(
                    events: [.started(requestID: UUID())],
                    waitsForCancellation: true
                ),
            ]
        )
        setup.controller.start(
            request(
                question: "Old",
                assistantMessageID: firstAssistantID,
                mode: .newTurn
            )
        )
        await waitUntil {
            setup.callbacks.events.contains {
                $0.operationID == firstOperationID
            }
        }

        setup.controller.start(
            request(
                question: "New",
                assistantMessageID: secondAssistantID,
                mode: .regeneration
            )
        )
        await GraphChatProviderTestSupport.waitUntil {
            let snapshot = await setup.orchestrator.snapshot()
            return snapshot.questions == ["Old", "New"]
                && snapshot.cancellationCount > 0
        }

        #expect(setup.controller.activeOperationID == secondOperationID)
        #expect(setup.controller.activeAssistantMessageID == secondAssistantID)
        #expect(setup.controller.isGenerating)
        #expect(setup.callbacks.visibleStateChanges == [true])
        #expect(
            setup.callbacks.outcomes.contains(
                RecordedGraphChatGenerationOutcome(
                    operationID: firstOperationID,
                    assistantMessageID: firstAssistantID,
                    outcome: .cancelled
                )
            )
        )
        #expect(
            setup.callbacks.events.contains {
                $0.operationID == firstOperationID
                    && $0.event == .cancelled
            } == false
        )

        let cleanup = setup.controller.cancel(discardSession: false)
        await cleanup?.value
        #expect(setup.callbacks.visibleStateChanges == [true, false])
    }

    @Test
    func eventsStayOrderedHistoryIsScopedAndOnlyStartedToolsAreCounted() async throws {
        let assistantID = UUID()
        let operationID = GraphChatGenerationOperationID()
        let activityID = UUID()
        let answer = GraphChatUITestSupport.finalAnswer(
            directAnswer: "Final",
            evidence: [GraphChatProviderTestSupport.makeEvidence()]
        )
        let expectedEvents: [GraphChatStreamEvent] = [
            .started(requestID: UUID()),
            .toolActivity(
                GraphChatToolActivity(
                    id: activityID,
                    tool: .searchGraph,
                    state: .started
                )
            ),
            .partialAnswer("Partial"),
            .toolActivity(
                GraphChatToolActivity(
                    id: activityID,
                    tool: .searchGraph,
                    state: .finished
                )
            ),
            .completed(answer),
        ]
        let setup = makeSetup(
            assistantMessageIDs: [assistantID],
            operationIDs: [operationID],
            scripts: [
                GraphChatUIFakeScript(
                    events: expectedEvents + [
                        .partialAnswer("Must be ignored after terminal")
                    ]
                )
            ]
        )

        setup.controller.start(
            request(
                question: "Ordered",
                assistantMessageID: assistantID,
                mode: .newTurn,
                usedIndexFallback: true
            )
        )
        await waitUntil {
            setup.controller.isGenerating == false
        }
        await waitForMetricCount(1, in: setup.observability)

        #expect(setup.callbacks.events.map(\.event) == expectedEvents)
        #expect(
            setup.callbacks.outcomes == [
                RecordedGraphChatGenerationOutcome(
                    operationID: operationID,
                    assistantMessageID: assistantID,
                    outcome: .completed
                )
            ]
        )
        #expect(setup.callbacks.completedTurnOperationIDs == [operationID])
        #expect(setup.callbacks.visibleStateChanges == [true, false])

        let metrics = await setup.observability.requestMetrics()
        let metric = try #require(metrics.first)
        #expect(metrics.count == 1)
        #expect(metric.toolCount == 1)
        #expect(metric.toolKinds == [.searchGraph])
        #expect(metric.evidenceCount == 1)
        #expect(metric.usedIndexFallback)
        #expect(metric.outcome == .completed)

        let snapshots = await setup.history.snapshots()
        #expect(snapshots.count == expectedEvents.count + 1)
        #expect(
            snapshots.first.flatMap {
                assistantState(in: $0, messageID: assistantID)
            }?.phase == .running
        )
        #expect(
            snapshots.last.flatMap {
                assistantState(in: $0, messageID: assistantID)
            }?.phase == .final
        )
        let savedScopes = await setup.history.scopes()
        #expect(savedScopes.allSatisfy { $0 == setup.chatScope })
    }

    @Test
    func completedCancelledAndFailureEachResolveExactlyOneTerminalOutcome() async {
        let failure = GraphChatError(
            code: .toolFailure,
            message: "Tool failed"
        )
        let cases: [
            (
                event: GraphChatStreamEvent,
                expected: GraphChatGenerationOutcome,
                metric: GraphChatRequestOutcome
            )
        ] = [
            (
                .completed(
                    GraphChatUITestSupport.finalAnswer(
                        directAnswer: "Done"
                    )
                ),
                .completed,
                .completed
            ),
            (.cancelled, .cancelled, .cancelled),
            (.failure(failure), .failure(failure), .failed),
        ]

        for testCase in cases {
            let assistantID = UUID()
            let operationID = GraphChatGenerationOperationID()
            let setup = makeSetup(
                assistantMessageIDs: [assistantID],
                operationIDs: [operationID],
                scripts: [
                    GraphChatUIFakeScript(
                        events: [
                            testCase.event,
                            .completed(
                                GraphChatUITestSupport.finalAnswer(
                                    directAnswer: "Ignored duplicate terminal"
                                )
                            ),
                        ]
                    )
                ]
            )
            setup.controller.start(
                request(
                    question: "Terminal",
                    assistantMessageID: assistantID,
                    mode: .newTurn
                )
            )
            await waitUntil {
                setup.controller.isGenerating == false
            }
            await waitForMetricCount(1, in: setup.observability)

            #expect(setup.callbacks.events.map(\.event) == [testCase.event])
            #expect(setup.callbacks.outcomes.map(\.outcome) == [testCase.expected])
            let metrics = await setup.observability.requestMetrics()
            #expect(metrics.map(\.outcome) == [testCase.metric])
        }
    }

    @Test
    func emptyStreamCreatesTheControlledUnexpectedFailureAndPersistsIt() async throws {
        let assistantID = UUID()
        let operationID = GraphChatGenerationOperationID()
        let setup = makeSetup(
            assistantMessageIDs: [assistantID],
            operationIDs: [operationID],
            scripts: [
                GraphChatUIFakeScript(events: [])
            ]
        )

        setup.controller.start(
            request(
                question: "Empty",
                assistantMessageID: assistantID,
                mode: .newTurn
            )
        )
        await waitUntil {
            setup.controller.isGenerating == false
        }
        await waitForMetricCount(1, in: setup.observability)

        let event = try #require(setup.callbacks.events.first?.event)
        guard case .failure(let error) = event else {
            Issue.record("Expected the synthetic failure.")
            return
        }
        #expect(setup.callbacks.events.count == 1)
        #expect(error.code == .unexpected)
        #expect(error.message == "Die Antwort wurde ohne Abschluss beendet.")
        #expect(error.recoverySuggestion == "Versuche die Frage erneut.")
        #expect(
            setup.callbacks.assistantState(for: assistantID)?.phase
                == .technicalError
        )
        let snapshots = await setup.history.snapshots()
        let metrics = await setup.observability.requestMetrics()
        #expect(snapshots.count == 2)
        #expect(metrics.map(\.outcome) == [.failed])
    }

    @Test
    func localCancellationProducesOneCancellationMetricAndNoSyntheticFailure() async {
        let assistantID = UUID()
        let operationID = GraphChatGenerationOperationID()
        let setup = makeSetup(
            assistantMessageIDs: [assistantID],
            operationIDs: [operationID],
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .partialAnswer("Partial")
                    ],
                    waitsForCancellation: true
                )
            ]
        )
        setup.controller.start(
            request(
                question: "Cancel",
                assistantMessageID: assistantID,
                mode: .newTurn
            )
        )
        await waitUntil {
            setup.callbacks.assistantState(for: assistantID)?.phase == .partial
        }

        let cleanup = setup.controller.cancel(discardSession: false)
        await cleanup?.value
        await waitForMetricCount(1, in: setup.observability)

        #expect(setup.controller.isGenerating == false)
        #expect(setup.callbacks.cancelledOperationIDs == [operationID])
        #expect(setup.callbacks.outcomes.map(\.outcome) == [.cancelled])
        #expect(
            setup.callbacks.events.contains { event in
                if case .failure = event.event {
                    return true
                }
                return false
            } == false
        )
        #expect(
            setup.callbacks.assistantState(for: assistantID)?.phase
                == .cancelled
        )
        let metrics = await setup.observability.requestMetrics()
        #expect(metrics.count == 1)
        #expect(metrics.first?.outcome == .cancelled)
        #expect(metrics.first?.errorCode == .cancelled)
        #expect(setup.callbacks.visibleStateChanges == [true, false])
    }

    @Test
    func cancelledOldTaskCannotWriteASuccessMetricForTheReplacement() async {
        let firstAssistantID = UUID()
        let secondAssistantID = UUID()
        let firstOperationID = GraphChatGenerationOperationID()
        let secondOperationID = GraphChatGenerationOperationID()
        let setup = makeSetup(
            assistantMessageIDs: [firstAssistantID, secondAssistantID],
            operationIDs: [firstOperationID, secondOperationID],
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .partialAnswer("Old partial")
                    ],
                    waitsForCancellation: true
                ),
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "New final"
                            )
                        )
                    ]
                ),
            ]
        )
        setup.controller.start(
            request(
                question: "Old",
                assistantMessageID: firstAssistantID,
                mode: .newTurn
            )
        )
        await waitUntil {
            setup.callbacks.assistantState(for: firstAssistantID)?.phase == .partial
        }
        setup.controller.start(
            request(
                question: "New",
                assistantMessageID: secondAssistantID,
                mode: .branchReplacement
            )
        )
        await waitUntil {
            setup.controller.isGenerating == false
                && setup.callbacks.assistantState(for: secondAssistantID)?.phase == .final
        }
        await waitForMetricCount(2, in: setup.observability)

        let metrics = await setup.observability.requestMetrics()
        #expect(metrics.count == 2)
        #expect(metrics.filter { $0.outcome == .cancelled }.count == 1)
        #expect(metrics.filter { $0.outcome == .completed }.count == 1)
        #expect(
            setup.callbacks.assistantState(for: firstAssistantID)?.phase
                == .partial
        )
        #expect(
            setup.callbacks.assistantState(for: secondAssistantID)?.text
                == "New final"
        )
        #expect(setup.callbacks.visibleStateChanges == [true, false])
    }

    private func makeSetup(
        assistantMessageIDs: [UUID],
        operationIDs: [GraphChatGenerationOperationID],
        scripts: [GraphChatUIFakeScript]
    ) -> GraphChatGenerationControllerSetup {
        let graphScope = GraphScope(graphID: UUID())
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let orchestrator = GraphChatUIFakeOrchestrator(scripts: scripts)
        let history = GraphChatGenerationHistoryRecorder()
        let observability = GraphChatGenerationObservabilityRecorder()
        let callbacks = GraphChatGenerationCallbackRecorder(
            assistantMessageIDs: assistantMessageIDs
        )
        let sequence = GraphChatGenerationOperationIDSequence(operationIDs)
        let controller = GraphChatGenerationController(
            graphScope: graphScope,
            chatScope: chatScope,
            orchestrator: orchestrator,
            historyStore: history,
            observability: observability,
            callbacks: callbacks.callbacks(),
            operationIDFactory: {
                sequence.next()
            }
        )
        return GraphChatGenerationControllerSetup(
            controller: controller,
            orchestrator: orchestrator,
            history: history,
            observability: observability,
            callbacks: callbacks,
            operationIDs: sequence,
            chatScope: chatScope
        )
    }

    private func request(
        question: String,
        assistantMessageID: UUID,
        mode: GraphChatGenerationMode,
        usedIndexFallback: Bool = false
    ) -> GraphChatGenerationRequest {
        GraphChatGenerationRequest(
            question: question,
            assistantMessageID: assistantMessageID,
            mode: mode,
            usedIndexFallback: usedIndexFallback
        )
    }

    private func waitUntil(
        maximumYields: Int = 20_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        await GraphChatUITestSupport.waitUntil(
            maximumYields: maximumYields,
            condition: condition
        )
    }

    private func waitForMetricCount(
        _ count: Int,
        in recorder: GraphChatGenerationObservabilityRecorder
    ) async {
        await GraphChatProviderTestSupport.waitUntil {
            await recorder.requestMetrics().count >= count
        }
    }

    private func assistantState(
        in messages: [GraphChatTranscriptMessage],
        messageID: UUID
    ) -> GraphChatAssistantMessageState? {
        guard let message = messages.first(where: { $0.id == messageID }),
              case .assistant(let state) = message.state else {
            return nil
        }
        return state
    }
}
