import Foundation
import Testing
@testable import BrainMesh

struct GraphChatStreamingStateTests {
    @Test
    func partialAnswersNeverExposeNavigableEvidence() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000003")!
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "active", limit: 3)),
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "One active item",
                                    hasInsufficientEvidence: false
                                )
                            )
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "One active item was found.",
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
        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "How many active items are there?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        let partialIndex = try #require(events.firstIndex { event in
            if case .partialAnswer = event { return true }
            return false
        })
        let completedIndex = try #require(events.firstIndex { event in
            if case .completed = event { return true }
            return false
        })
        #expect(partialIndex < completedIndex)
        #expect(events[partialIndex] == .partialAnswer("One active item"))
    }

    @Test
    func cancellationEndsTheStreamAndCancelsTheActiveTool() async throws {
        let recorder = GraphChatFakeToolRunnerRecorder()
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "slow", limit: 3)),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Should not complete"
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
                recorder: recorder,
                delayNanoseconds: 60_000_000_000
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let stream = await orchestrator.streamAnswer(
            question: "Run a slow search.",
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )
        let collector = Task {
            await GraphChatProviderTestSupport.collect(stream)
        }
        await GraphChatProviderTestSupport.waitUntil {
            await recorder.snapshot().requests.isEmpty == false
        }

        await orchestrator.cancelCurrentGeneration()
        let events = await collector.value
        let runnerSnapshot = await recorder.snapshot()
        let providerSnapshot = await provider.snapshot()

        #expect(events.contains(.cancelled))
        #expect(events.contains { event in
            if case .completed = event { return true }
            return false
        } == false)
        #expect(runnerSnapshot.cancellationCount == 1)
        #expect(providerSnapshot.cancelledSessions.isEmpty == false)
    }
}
