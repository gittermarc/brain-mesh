import Foundation
import Testing
@testable import BrainMesh

struct GraphChatOrchestratorTests {
    @Test
    func successfulRequestStreamsControlledToolsAndValidatedAnswer() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000001")!,
            summary: "Project Alpha is active"
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "Alpha", limit: 5)),
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "Project Alpha",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Project Alpha is active.",
                                    evidenceIDs: [evidence.id]
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let recorder = GraphChatFakeToolRunnerRecorder()
        let factory = EvidenceRegisteringFakeToolRunnerFactory(
            recorder: recorder,
            evidenceByTool: [.searchGraph: [evidence]]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: factory
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let stream = await orchestrator.streamAnswer(
            question: "What is the status of Project Alpha?",
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )

        let events = await GraphChatProviderTestSupport.collect(stream)

        #expect(events.first.map { event in
            if case .started = event { return true }
            return false
        } == true)
        #expect(events.contains { event in
            if case .toolActivity(let activity) = event {
                return activity.tool == .searchGraph && activity.state == .started
            }
            return false
        })
        #expect(events.contains { event in
            if case .toolActivity(let activity) = event {
                return activity.tool == .searchGraph && activity.state == .finished
            }
            return false
        })
        #expect(events.contains(.partialAnswer("Project Alpha")))

        let completed = try #require(events.compactMap { event -> GraphChatAnswer? in
            if case .completed(let answer) = event {
                return answer
            }
            return nil
        }.last)
        #expect(completed.directAnswer == "Project Alpha is active.")
        #expect(completed.evidence == [evidence])
        #expect(completed.hasInsufficientEvidence == false)

        let providerSnapshot = await provider.snapshot()
        let sessionID = try #require(providerSnapshot.createdSessions.first)
        let configuration = try #require(providerSnapshot.sessionConfigurations[sessionID])
        #expect(await configuration.toolRunner.registeredToolKinds() == Set(GraphChatToolKind.allCases))
        #expect(await recorder.snapshot().requests == [.searchGraph(query: "Alpha", limit: 5)])
    }

    @Test
    func answerWithoutRegisteredEvidenceIsMarkedInsufficient() async throws {
        let inventedEvidenceID = GraphEvidenceID(rawValue: UUID())
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Invented model wording must not become graph state.",
                                    evidenceIDs: [inventedEvidenceID]
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let stream = await orchestrator.streamAnswer(
            question: "Tell me something unavailable.",
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )

        let events = await GraphChatProviderTestSupport.collect(stream)
        let answer = try #require(events.compactMap { event -> GraphChatAnswer? in
            if case .completed(let answer) = event {
                return answer
            }
            return nil
        }.last)

        #expect(answer.evidence.isEmpty)
        #expect(answer.hasInsufficientEvidence)
        let stateSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let state = try #require(stateSnapshot)
        #expect(state.turnContexts.count == 1)
        #expect(state.turnContexts[0].evidenceIDs.isEmpty)
        #expect(state.nodeReferences.isEmpty)
        #expect(state.entityReferences.isEmpty)
        #expect(state.fieldReferences.isEmpty)
        #expect(state.resultContexts.isEmpty)
    }

    @Test
    func providerCanBeReplacedCompletelyByAFake() async throws {
        let provider: any GraphChatModelProvider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Fake provider response",
                                    hasInsufficientEvidence: true
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Use the fake provider.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        #expect(events.contains { event in
            if case .completed(let answer) = event {
                return answer.directAnswer == "Fake provider response"
            }
            return false
        })
    }

    @Test
    func successfulTurnCommitsTrustedStructuredState() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000011")!,
            summary: "Trusted project result"
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "project", limit: 5)),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Assistant wording is not state data.",
                                    evidenceIDs: [evidence.id]
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [evidence]]
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Find the project.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )

        let stateSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let state = try #require(stateSnapshot)
        #expect(state.graphScope == graphScope)
        #expect(state.chatScope == chatScope)
        #expect(state.turnContexts.count == 1)
        #expect(state.turnContexts[0].toolKinds == [.searchGraph])
        #expect(state.turnContexts[0].evidenceIDs == [evidence.id])
        #expect(state.nodeReferences.count == 1)
        #expect(state.resultContexts.count == 1)
        #expect(state.resultContexts[0].kind == .search)

        let providerSnapshot = await provider.snapshot()
        let providerRequest: GraphChatModelRequest = try #require(
            providerSnapshot.streamedRequests.first
        )
        #expect(providerRequest.conversationState?.conversationID == state.conversationID)
        #expect(providerRequest.conversationState?.turnContexts.isEmpty == true)
        #expect(providerRequest.conversationState?.nodeReferences.isEmpty == true)
    }

    @Test
    func failedTurnKeepsPreviouslyCommittedState() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000012")!
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "first", limit: 1)),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    evidenceIDs: [evidence.id]
                                )
                            )
                        )
                    ]
                ),
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "second", limit: 1)),
                        .failure(
                            GraphChatProviderError(
                                code: .toolFailure,
                                message: "Expected failure"
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [evidence]]
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "First turn",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let committedSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let committed = try #require(committedSnapshot)

        let failedEvents = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Fail this turn",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )

        #expect(failedEvents.contains { event in
            if case .failure = event {
                return true
            }
            return false
        })
        #expect(await orchestrator.conversationStateSnapshot() == committed)
    }

    @Test
    func failedToolExecutionDoesNotChangeCommittedState() async throws {
        let foreignEvidence = GraphChatProviderTestSupport.makeEvidence(
            graphID: GraphChatTestSupport.otherGraphID,
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000017")!
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Committed baseline",
                                    hasInsufficientEvidence: true
                                )
                            )
                        )
                    ]
                ),
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "foreign", limit: 1))
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [foreignEvidence]]
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Create a committed baseline.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let committedSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let committed = try #require(committedSnapshot)

        let failedEvents = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Reject graph-foreign tool evidence.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )

        #expect(failedEvents.contains { event in
            if case .failure = event {
                return true
            }
            return false
        })
        #expect(await orchestrator.conversationStateSnapshot() == committed)
    }

    @Test
    func cancellationDoesNotCommitPartiallyReducedState() async throws {
        let firstEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000013")!,
            summary: "First committed result"
        )
        let secondEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000014")!,
            summary: "Uncommitted result"
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "first", limit: 1)),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    evidenceIDs: [firstEvidence.id]
                                )
                            )
                        )
                    ]
                ),
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.getNode(nodeAlias: "E1", relatedLimit: 1)),
                        .waitForCancellation
                    ]
                )
            ]
        )
        let factory = EvidenceRegisteringFakeToolRunnerFactory(
            evidenceByTool: [
                .searchGraph: [firstEvidence],
                .getNode: [secondEvidence]
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: factory
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Commit the first turn",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let committedSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let committed = try #require(committedSnapshot)
        let stream = await orchestrator.streamAnswer(
            question: "Cancel the second turn",
            graphScope: graphScope,
            chatScope: chatScope
        )
        let collector = Task {
            await GraphChatProviderTestSupport.collect(stream)
        }
        await GraphChatProviderTestSupport.waitUntil {
            await provider.snapshot().toolResponses.count == 2
        }

        let inFlightProviderSnapshot = await provider.snapshot()
        let inFlightRequest: GraphChatModelRequest = try #require(
            inFlightProviderSnapshot.streamedRequests.last
        )
        #expect(inFlightRequest.conversationState == committed.snapshot)
        #expect(await orchestrator.conversationStateSnapshot() == committed)

        await orchestrator.cancelCurrentGeneration()
        let events = await collector.value

        #expect(events.contains(.cancelled))
        #expect(await orchestrator.conversationStateSnapshot() == committed)
    }

    @Test
    func successiveTurnsUpdateStateDeterministicallyAndNewChatResetsIt() async throws {
        let firstEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000015")!
        )
        let secondEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000016")!
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                successfulScript(evidence: firstEvidence, query: "first"),
                successfulScript(evidence: secondEvidence, query: "second"),
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Fresh conversation",
                                    hasInsufficientEvidence: true
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [firstEvidence, secondEvidence]]
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        for question in ["First", "Second"] {
            _ = await GraphChatProviderTestSupport.collect(
                await orchestrator.streamAnswer(
                    question: question,
                    graphScope: graphScope,
                    chatScope: chatScope
                )
            )
        }
        let twoTurnSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let twoTurnState = try #require(twoTurnSnapshot)
        #expect(twoTurnState.turnContexts.count == 2)
        #expect(twoTurnState.resultContexts.count == 2)
        let oldConversationID = twoTurnState.conversationID

        await orchestrator.discardSession(reason: .newConversation)
        #expect(await orchestrator.conversationStateSnapshot() == nil)
        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Fresh",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let freshSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let freshState = try #require(freshSnapshot)
        #expect(freshState.conversationID != oldConversationID)
        #expect(freshState.turnContexts.count == 1)
        #expect(freshState.nodeReferences.isEmpty)
        #expect(freshState.lastResetReason == .newConversation)
    }

    @Test
    func graphChangeCreatesFreshGraphIsolatedConversationState() async throws {
        let firstEvidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000018")!
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                successfulScript(evidence: firstEvidence, query: "first-graph"),
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Second graph",
                                    hasInsufficientEvidence: true
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [firstEvidence]]
            ),
            graphIDs: [GraphChatTestSupport.graphID, GraphChatTestSupport.otherGraphID]
        )
        let firstGraph = GraphScope(graphID: GraphChatTestSupport.graphID)
        let secondGraph = GraphScope(graphID: GraphChatTestSupport.otherGraphID)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "First graph",
                graphScope: firstGraph,
                chatScope: .entireGraph(firstGraph)
            )
        )
        let firstStateSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let firstState = try #require(firstStateSnapshot)
        #expect(firstState.nodeReferences.isEmpty == false)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Second graph",
                graphScope: secondGraph,
                chatScope: .entireGraph(secondGraph)
            )
        )
        let secondStateSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let secondState = try #require(secondStateSnapshot)

        #expect(secondState.graphScope == secondGraph)
        #expect(secondState.chatScope == .entireGraph(secondGraph))
        #expect(secondState.conversationID != firstState.conversationID)
        #expect(secondState.lastResetReason == .graphChanged)
        #expect(secondState.nodeReferences.isEmpty)
        #expect(secondState.entityReferences.isEmpty)
        #expect(secondState.fieldReferences.isEmpty)
    }

    @Test
    func graphLockDeletionAndAccessRevocationResetConversationState() async throws {
        let reasons: [GraphChatConversationResetReason] = [
            .graphLocked,
            .graphDeleted,
            .accessRevoked
        ]

        for reason in reasons {
            let evidence = GraphChatProviderTestSupport.makeEvidence(
                sourceID: UUID(),
                summary: reason.rawValue
            )
            let provider = FakeGraphChatModelProvider(
                scripts: [
                    successfulScript(evidence: evidence, query: "before-reset"),
                    FakeGraphChatProviderScript(
                        steps: [
                            .event(
                                .completed(
                                    GraphChatProviderTestSupport.makeFinalAnswer(
                                        directAnswer: "After reset",
                                        hasInsufficientEvidence: true
                                    )
                                )
                            )
                        ]
                    )
                ]
            )
            let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
                provider: provider,
                factory: EvidenceRegisteringFakeToolRunnerFactory(
                    evidenceByTool: [.searchGraph: [evidence]]
                )
            )
            let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
            let chatScope = GraphChatScope.entireGraph(graphScope)

            _ = await GraphChatProviderTestSupport.collect(
                await orchestrator.streamAnswer(
                    question: "Before reset",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
            )
            let oldStateSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
            let oldState = try #require(oldStateSnapshot)

            await orchestrator.discardSession(reason: reason)
            #expect(await orchestrator.conversationStateSnapshot() == nil)

            _ = await GraphChatProviderTestSupport.collect(
                await orchestrator.streamAnswer(
                    question: "After reset",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
            )
            let resetStateSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
            let resetState = try #require(resetStateSnapshot)
            #expect(resetState.conversationID != oldState.conversationID)
            #expect(resetState.lastResetReason == reason)
            #expect(resetState.nodeReferences.isEmpty)
        }
    }

    private func successfulScript(
        evidence: GraphEvidence,
        query: String
    ) -> FakeGraphChatProviderScript {
        FakeGraphChatProviderScript(
            steps: [
                .toolRequest(.searchGraph(query: query, limit: 1)),
                .event(
                    .completed(
                        GraphChatProviderTestSupport.makeFinalAnswer(
                            evidenceIDs: [evidence.id]
                        )
                    )
                )
            ]
        )
    }

}
