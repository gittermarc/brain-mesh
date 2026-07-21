import Foundation
import Testing
@testable import BrainMesh

struct GraphChatEvidenceValidationTests {
    @Test
    func unknownEvidenceIDsAreRemovedFromAnswerAndSections() async throws {
        let known = GraphChatProviderTestSupport.makeEvidence(
            sourceID: UUID(uuidString: "50000000-0000-0000-0000-000000000002")!,
            summary: "Known evidence"
        )
        let unknown = GraphEvidenceID(
            rawValue: UUID(uuidString: "60000000-0000-0000-0000-000000000001")!
        )
        let final = GraphChatProviderFinalAnswer(
            directAnswer: "Only one source is valid.",
            sections: [
                GraphChatProviderAnswerSection(
                    title: "Details",
                    text: "Validated section",
                    evidenceIDValues: [
                        known.id.rawValue.uuidString,
                        unknown.rawValue.uuidString
                    ]
                )
            ],
            evidenceIDValues: [
                unknown.rawValue.uuidString,
                known.id.rawValue.uuidString
            ],
            appliedFilters: [],
            followUpSuggestions: [],
            hasInsufficientEvidence: false
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.getNode(nodeAlias: "E1", relatedLimit: 5)),
                        .event(.completed(final))
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.getNode: [known]]
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Show the known evidence.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let answer = try #require(events.compactMap { event -> GraphChatAnswer? in
            if case .completed(let answer) = event {
                return answer
            }
            return nil
        }.last)
        let section = try #require(answer.sections.first)

        #expect(answer.evidence == [known])
        #expect(section.evidenceIDs == [known.id])
        #expect(answer.evidenceIDs.contains(unknown) == false)
        #expect(answer.hasInsufficientEvidence == false)
    }

    @Test
    func anAnswerReferencingOnlyUnknownEvidenceBecomesInsufficient() async throws {
        let unknown = GraphEvidenceID(
            rawValue: UUID(uuidString: "60000000-0000-0000-0000-000000000002")!
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Unverified claim",
                                    evidenceIDs: [unknown]
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
                question: "Use an unknown source.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let answer = try #require(events.compactMap { event -> GraphChatAnswer? in
            if case .completed(let answer) = event {
                return answer
            }
            return nil
        }.last)

        #expect(answer.evidence.isEmpty)
        #expect(answer.hasInsufficientEvidence)
    }
}
