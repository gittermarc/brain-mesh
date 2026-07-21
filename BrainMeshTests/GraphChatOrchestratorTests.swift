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
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "I cannot verify that from the graph."
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
}
