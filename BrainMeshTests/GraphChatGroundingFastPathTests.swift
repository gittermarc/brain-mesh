import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat grounding fast paths")
struct GraphChatGroundingFastPathTests {
    @Test
    func recognizesMedicalLibraryAndOperationsCollections() throws {
        let cases: [
            (
                String,
                GraphChatResponseLanguage,
                GraphChatGroundingFixture,
                String
            )
        ] = [
            (
                "Welche Patienten gibt es?",
                .german,
                .medicine(),
                "Patient"
            ),
            (
                "Welche Autoren gibt es?",
                .german,
                .library(),
                "Autor"
            ),
            (
                "Welche Incident Records gibt es?",
                .german,
                .itOperations(),
                "Incident Record"
            ),
        ]

        for (
            question,
            language,
            fixture,
            entityName
        ) in cases {
            let intent = try #require(
                compiled(
                    question,
                    language: language,
                    fixture: fixture
                )
            )
            #expect(
                intent.kind
                    == .entityAttributeCollection
            )
            #expect(
                intent.entity.id
                    == fixture.entityID(
                        named: entityName
                    )
            )
        }
    }

    @Test
    func describesUniquelyNamedNodeWithoutProvider() throws {
        let fixture =
            GraphChatGroundingFixture.medicine()
        let intent = try #require(
            compiled(
                "Nenne mir Details zu Patient A",
                language: .german,
                fixture: fixture
            )
        )

        #expect(intent.kind == .nodeDetails)
        #expect(
            intent.node?.node
                == fixture.node(
                    named: "Patient A"
                ).node
        )
        #expect(intent.field == nil)
        #expect(
            intent.queryScope
                == .node(
                    fixture.node(
                        named: "Patient A"
                    ).node,
                    in: fixture.graphScope
                )
        )
        let adaptation = try
            GraphChatFoundationalIntentAdapter()
                .adapt(intent)
        #expect(
            adaptation.intent.kind
                == .nodeDetails
        )
        guard case .nodeDetails(let action) =
                adaptation.action else {
            Issue.record(
                "Expected the shared local node action"
            )
            return
        }
        #expect(
            action.node.node
                == fixture.node(
                    named: "Patient A"
                ).node
        )
    }

    @Test
    func listFastPathBindsEntityBeyondPromptCatalogLimit() throws {
        let fixture =
            GraphChatGroundingFixture
                .beyondInterpreterCatalogLimits()
        let intent = try #require(
            compiled(
                "Show me all Remote Workloads",
                language: .english,
                fixture: fixture
            )
        )
        #expect(
            intent.entity.id
                == fixture.entityID(
                    named: "Remote Workload"
                )
        )
    }

    @Test
    func trueNodeAmbiguityProducesUnderstandableClarification() {
        let fixture =
            GraphChatGroundingFixture(
                graphName: "Ambiguous nodes",
                entities: [
                    GraphChatGroundingEntityDefinition(
                        name: "Clinical Case",
                        nodeNames: ["Case A"],
                        fieldNames: []
                    ),
                    GraphChatGroundingEntityDefinition(
                        name: "Support Case",
                        nodeNames: ["Case A"],
                        fieldNames: []
                    ),
                ]
            )
        let result = compile(
            "Show me details about Case A",
            language: .english,
            fixture: fixture
        )
        guard case .clarification(
            let clarification
        ) = result else {
            Issue.record(
                "Expected a scoped domain clarification"
            )
            return
        }
        #expect(clarification.options.count == 2)
        #expect(
            clarification.options
                .allSatisfy {
                    $0.title.contains("Case A")
                        && (
                            $0.title.contains(
                                "Clinical Case"
                            )
                            || $0.title.contains(
                                "Support Case"
                            )
                        )
                }
        )
    }

    @Test
    func entityAndSelectionScopesNeverExpand() throws {
        let fixture =
            GraphChatGroundingFixture.itOperations()
        let incidentID =
            fixture.entityID(
                named: "Incident Record"
            )
        let incidentNode =
            fixture.node(
                named: "Edge Gateway 07"
            ).node
        let serviceNode =
            fixture.node(
                named: "Core Maintenance"
            ).node

        let entityIntent = try #require(
            compiled(
                "Which Incident Records are there?",
                language: .english,
                fixture: fixture,
                chatScope:
                    .entity(
                        incidentID,
                        in: fixture.graphScope
                    )
            )
        )
        #expect(
            entityIntent.entity.id
                == incidentID
        )

        let nodeResult = compile(
            "Show me details about Core Maintenance",
            language: .english,
            fixture: fixture,
            chatScope:
                .node(
                    incidentNode,
                    in: fixture.graphScope
                )
        )
        guard case .rejected(
            .unauthorizedSelection
        ) = nodeResult else {
            Issue.record(
                "Node scope must reject another node"
            )
            return
        }

        let selectionResult = compile(
            "Show me details about Core Maintenance",
            language: .english,
            fixture: fixture,
            chatScope:
                try .selection(
                    [serviceNode],
                    in: fixture.graphScope
                )
        )
        guard case .compiled(let selected) =
                selectionResult else {
            Issue.record(
                "Selected node should remain bindable"
            )
            return
        }
        #expect(selected.node?.node == serviceNode)
    }

    private func compiled(
        _ question: String,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope? = nil
    ) -> GraphChatFoundationalIntent? {
        guard case .compiled(let intent) =
                compile(
                    question,
                    language: language,
                    fixture: fixture,
                    chatScope: chatScope
                ) else {
            return nil
        }
        return intent
    }

    private func compile(
        _ question: String,
        language: GraphChatResponseLanguage,
        fixture: GraphChatGroundingFixture,
        chatScope: GraphChatScope? = nil
    ) -> GraphChatFoundationalIntentCompilation {
        let scope =
            chatScope
            ?? .entireGraph(
                fixture.graphScope
            )
        return GraphChatFoundationalIntentCompiler()
            .compile(
                GraphChatFoundationalIntentCompilerInput(
                    requestID: UUID(),
                    question: question,
                    graphScope:
                        fixture.graphScope,
                    chatScope: scope,
                    responseLanguage: language,
                    conversationState:
                        .initial(
                            graphScope:
                                fixture.graphScope,
                            chatScope: scope
                        ),
                    schemaContext:
                        fixture.context,
                    selectedCandidate: nil,
                    sourceTurnID: nil,
                    clarificationID: nil
                )
            )
    }
}
