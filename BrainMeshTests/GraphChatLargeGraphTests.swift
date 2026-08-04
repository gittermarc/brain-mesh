import Foundation
import Testing
@testable import BrainMesh

struct GraphChatLargeGraphTests {
    @MainActor
    @Test
    func thousandsOfAttributesUseCompactSchemaAndBoundedToolResultsInsteadOfFullGraphPrompt() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let fixture = fixtures.makeGraphChatLargeGraphFixture(attributeCount: 2_400)
        try fixtures.save()

        let schemaFetches = GraphChatLargeGraphSchemaFetchRecorder()
        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container),
            schemaSourceInstrumentation: GraphSchemaSourceInstrumentation {
                schemaFetches.record($0)
            }
        )
        let schemaService = GraphSchemaService(repository: repository)
        let graphScope = GraphScope(graphID: fixture.graph.id)
        let schema = try await schemaService.makeSnapshot(in: graphScope)
        let entityAlias = try #require(schema.entityAlias(named: "Large Items"))
        let statusAlias = try #require(
            schema.fieldAlias(named: "Status", in: entityAlias)
        )
        let sequenceAlias = try #require(
            schema.fieldAlias(named: "Sequence", in: entityAlias)
        )

        #expect(schema.snapshot.entities.count == 1)
        #expect(schema.snapshot.entities[0].attributeCount == fixture.attributeCount)
        #expect(schema.snapshot.entities[0].fields.count == 2)

        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                GraphChatModelQueryRequest(
                                    entityAlias: entityAlias.rawValue,
                                    filters: [
                                        GraphChatModelQueryFilterRequest(
                                            fieldAlias: statusAlias.rawValue,
                                            operation: GraphQueryFilterOperator.equals.rawValue,
                                            value: "Open",
                                            secondValue: nil,
                                            values: []
                                        )
                                    ],
                                    sortFieldAlias: sequenceAlias.rawValue,
                                    sortDirection: GraphQuerySortDirection.ascending.rawValue,
                                    projectionFieldAliases: [
                                        statusAlias.rawValue,
                                        sequenceAlias.rawValue
                                    ],
                                    aggregation: nil,
                                    aggregationFieldAlias: nil,
                                    limit: 50
                                )
                            )
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Die Tool-Ergebnisse wurden begrenzt ausgewertet.",
                                    hasInsufficientEvidence: true
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaService,
            toolRunnerFactory: GraphChatProviderTestSupport.makeRealRuntimeFactory(
                store: store,
                schemaService: schemaService,
                repository: repository
            )
        )
        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Zeige offene Large-Graph-Einträge.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        let snapshot = await provider.snapshot()
        let request = try #require(snapshot.streamedRequests.first)
        let response = try #require(snapshot.toolResponses.first)
        let configuration = try #require(
            snapshot.sessionConfigurations.values.first
        )

        #expect(
            request.schemaPrompt.count
                <= request.contextProfile.maximumSchemaCharacters
        )
        #expect(request.schemaPrompt.contains(fixture.firstAttribute.displayName) == false)
        #expect(request.schemaPrompt.contains(fixture.lastAttribute.displayName) == false)
        #expect(request.schemaPrompt.contains("Documented large-graph fixture row") == false)
        #expect(response.tool == .queryDetailValues)
        #expect(
            response.content.count
                <= GraphChatModelToolOutputBudget.default.maximumCollectionCharacters
        )
        #expect(response.evidenceIDs.count <= GraphChatToolBudgetPolicy.default.maximumEvidenceCount)
        #expect(response.content.contains("Large Item 0000"))
        #expect(response.content.contains("Large Item 2399") == false)
        #expect(configuration.schemaContext.identity == schema.identity)
        #expect(fixture.detailValueCount == 4_800)
        #expect(fixture.linkCount == 2_399)
        #expect(schemaFetches.count(.graph) == 1)
        #expect(schemaFetches.count(.fullSourceSnapshot) == 0)
        #expect(schemaFetches.count(.links) == 0)
        #expect(schemaFetches.count(.attachments) == 0)
        #expect(schemaFetches.count(.exampleValues) == 0)
    }

    @Test
    func schemaAndToolBudgetConstantsRemainReleaseBounded() {
        #expect(GraphSchemaLimits.default.maximumEntities == 64)
        #expect(GraphSchemaLimits.default.maximumFieldsPerEntity == 32)
        #expect(GraphSchemaLimits.default.maximumFieldsTotal == 256)
        #expect(GraphChatToolBudgetPolicy.default.maximumCalls == 8)
        #expect(GraphChatToolBudgetPolicy.default.maximumResultCountPerTool == 50)
        #expect(GraphChatToolBudgetPolicy.default.maximumEvidenceCount == 200)
        #expect(QueryDetailValuesTool.maximumResultCount == 50)
        #expect(GraphChatModelContextProfile.standard.maximumSchemaCharacters == 3_200)
        #expect(GraphChatModelContextProfile.compact.maximumSchemaCharacters == 1_800)
        #expect(GraphChatModelContextProfile.recovery.maximumSchemaCharacters == 900)
        #expect(GraphChatModelToolOutputBudget.default.maximumSchemaCharacters == 2_400)
        #expect(GraphChatModelToolOutputBudget.default.maximumCollectionCharacters == 3_200)
    }
}

private nonisolated final class GraphChatLargeGraphSchemaFetchRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var counts: [GraphSchemaSourceFetchKind: Int] = [:]

    func record(_ kind: GraphSchemaSourceFetchKind) {
        lock.withLock {
            counts[kind, default: 0] += 1
        }
    }

    func count(_ kind: GraphSchemaSourceFetchKind) -> Int {
        lock.withLock { counts[kind, default: 0] }
    }
}
