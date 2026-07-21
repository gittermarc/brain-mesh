import Foundation
import Testing
@testable import BrainMesh

struct GraphChatModelAvailabilityTests {
    @Test
    func fakeProviderExposesEveryAvailabilityReason() async {
        for reason in GraphChatModelUnavailableReason.allCases {
            let provider = FakeGraphChatModelProvider(
                availability: .unavailable(reason)
            )
            #expect(await provider.availability() == .unavailable(reason))
        }
    }

    @Test
    func unavailableModelProducesAValueOnlyModelUnavailableError() async throws {
        for reason in GraphChatModelUnavailableReason.allCases {
            let provider = FakeGraphChatModelProvider(
                availability: .unavailable(reason)
            )
            let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
                provider: provider,
                factory: EvidenceRegisteringFakeToolRunnerFactory()
            )
            let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
            let events = await GraphChatProviderTestSupport.collect(
                await orchestrator.streamAnswer(
                    question: "Can the model answer?",
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

            #expect(error.code == .modelUnavailable)
            #expect(error.message.isEmpty == false)
            #expect(events.contains { event in
                if case .completed = event { return true }
                return false
            } == false)
        }
    }
}
