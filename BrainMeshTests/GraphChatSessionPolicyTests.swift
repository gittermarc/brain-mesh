import Foundation
import Testing
@testable import BrainMesh

struct GraphChatSessionPolicyTests {
    @Test
    func matchingPreparedSessionIsConsumedByTheNextRequest() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [Self.successfulEmptyScript("Prepared answer")]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        try await orchestrator.prepare(
            graphScope: graphScope,
            chatScope: chatScope
        )

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Nutze die vorbereitete Session.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let snapshot = await provider.snapshot()

        #expect(events.contains { event in
            if case .completed(let answer) = event {
                return answer.directAnswer == "Prepared answer"
            }
            return false
        })
        #expect(snapshot.createdSessions.count == 1)
        #expect(snapshot.prewarmedSessions.count == 1)
        #expect(snapshot.streamedSessions == snapshot.prewarmedSessions)
        #expect(snapshot.discardedSessions == snapshot.prewarmedSessions)
    }

    @Test
    func graphChangeDiscardsThePreparedSession() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [Self.successfulEmptyScript("Graph B")]
        )
        let factory = EvidenceRegisteringFakeToolRunnerFactory()
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: factory,
            graphIDs: [GraphChatTestSupport.graphID, GraphChatTestSupport.otherGraphID]
        )
        let firstGraph = GraphScope(graphID: GraphChatTestSupport.graphID)
        let secondGraph = GraphScope(graphID: GraphChatTestSupport.otherGraphID)
        try await orchestrator.prepare(
            graphScope: firstGraph,
            chatScope: .entireGraph(firstGraph)
        )

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Use the other graph.",
                graphScope: secondGraph,
                chatScope: .entireGraph(secondGraph)
            )
        )
        let snapshot = await provider.snapshot()

        #expect(snapshot.createdSessions.count == 2)
        #expect(snapshot.prewarmedSessions.count == 1)
        #expect(snapshot.discardedSessions.count == 2)
        #expect(snapshot.discardedSessions.first == snapshot.prewarmedSessions.first)
    }

    @Test
    func scopeChangeDiscardsThePreparedSession() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [Self.successfulEmptyScript("Entity scope")]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        try await orchestrator.prepare(
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Use the entity scope.",
                graphScope: graphScope,
                chatScope: .entity(GraphChatTestSupport.projectEntityID, in: graphScope)
            )
        )
        let snapshot = await provider.snapshot()

        #expect(snapshot.createdSessions.count == 2)
        #expect(snapshot.discardedSessions.count == 2)
    }

    @Test
    func aNewRequestCancelsThePreviousGenerationBeforeStarting() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(steps: [.waitForCancellation]),
                Self.successfulEmptyScript("Second answer")
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let firstStream = await orchestrator.streamAnswer(
            question: "First request",
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )
        let firstCollector = Task {
            await GraphChatProviderTestSupport.collect(firstStream)
        }
        await GraphChatProviderTestSupport.waitUntil {
            await provider.snapshot().streamedSessions.count == 1
        }

        let secondEvents = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Second request",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let firstEvents = await firstCollector.value
        let snapshot = await provider.snapshot()

        #expect(firstEvents.contains(.cancelled))
        #expect(secondEvents.contains { event in
            if case .completed(let answer) = event {
                return answer.directAnswer == "Second answer"
            }
            return false
        })
        #expect(snapshot.streamedSessions.count == 2)
        #expect(snapshot.cancelledSessions.contains(snapshot.streamedSessions[0]))
    }

    @Test
    func centralToolBudgetIsEnforcedAcrossModelToolCalls() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "one", limit: 1)),
                        .toolRequest(.getNode(nodeAlias: "E1", relatedLimit: 1))
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(),
            budgetPolicy: GraphChatToolBudgetPolicy(
                maximumCalls: 1,
                maximumResultCountPerTool: 10,
                maximumEvidenceCount: 10
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Use too many tools.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let error = try #require(events.compactMap { event -> GraphChatError? in
            if case .failure(let error) = event {
                return error
            }
            return nil
        }.last)

        #expect(error.code == .toolBudgetExceeded)
    }

    @Test
    func contextWindowFailureRetriesExactlyOnceWithAFreshSession() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .failure(
                            GraphChatProviderError(
                                code: .contextWindowExceeded,
                                message: "Context window exceeded"
                            )
                        )
                    ]
                ),
                Self.successfulEmptyScript("Recovered answer")
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Retry once.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let snapshot = await provider.snapshot()

        #expect(events.contains { event in
            if case .completed(let answer) = event {
                return answer.directAnswer == "Recovered answer"
            }
            return false
        })
        #expect(snapshot.createdSessions.count == 2)
        #expect(snapshot.streamedSessions.count == 2)
        #expect(snapshot.discardedSessions.count == 2)
        #expect(snapshot.streamedRequests[0].conversationContext != nil)
        #expect(snapshot.streamedRequests[1].conversationContext != nil)
    }

    @Test
    func repeatedContextWindowFailureDoesNotStartAThirdSession() async throws {
        let failure = FakeGraphChatProviderScript(
            steps: [
                .failure(
                    GraphChatProviderError(
                        code: .contextWindowExceeded,
                        message: "Context window exceeded"
                    )
                )
            ]
        )
        let provider = FakeGraphChatModelProvider(scripts: [failure, failure])
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Do not retry forever.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let snapshot = await provider.snapshot()
        let error = try #require(events.compactMap { event -> GraphChatError? in
            if case .failure(let error) = event {
                return error
            }
            return nil
        }.last)

        #expect(error.code == .contextWindowExceeded)
        #expect(snapshot.createdSessions.count == 2)
        #expect(snapshot.streamedSessions.count == 2)
    }

    @Test
    func contextRetryDiscardsPartiallyReducedConversationCandidate() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000021")!
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "partial", limit: 1)),
                        .failure(
                            GraphChatProviderError(
                                code: .contextWindowExceeded,
                                message: "Context window exceeded"
                            )
                        )
                    ]
                ),
                Self.successfulEmptyScript("Recovered without tools")
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [evidence]]
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Retry without retaining partial state.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        let stateSnapshot: GraphChatConversationState? = await orchestrator.conversationStateSnapshot()
        let state = try #require(stateSnapshot)
        #expect(state.turnContexts.count == 1)
        #expect(state.turnContexts[0].toolKinds.isEmpty)
        #expect(state.nodeReferences.isEmpty)
        #expect(state.resultContexts.isEmpty)
    }

    private static func successfulEmptyScript(
        _ answer: String
    ) -> FakeGraphChatProviderScript {
        FakeGraphChatProviderScript(
            steps: [
                .event(
                    .completed(
                        GraphChatProviderTestSupport.makeFinalAnswer(
                            directAnswer: answer,
                            hasInsufficientEvidence: true
                        )
                    )
                )
            ]
        )
    }
}
