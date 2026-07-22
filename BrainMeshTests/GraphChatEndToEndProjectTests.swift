import Foundation
import Testing
@testable import BrainMesh

struct GraphChatEndToEndProjectTests {
    @MainActor
    @Test
    func importantOpenProjectTasksExposeValidatedEvidenceAndVisibleInterpretationFilters() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let referenceDate = try #require(
            calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: timeZone,
                    year: 2026,
                    month: 7,
                    day: 21,
                    hour: 14
                )
            )
        )
        let fixture = fixtures.makeGraphChatProjectFixture(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: referenceDate
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let schemaService = GraphSchemaService(repository: repository)
        let schema = try await schemaService.makeSnapshot(
            in: GraphScope(graphID: fixture.graph.id)
        )
        let entityAlias = try #require(schema.entityAlias(named: "Aufgaben"))
        let statusAlias = try #require(
            schema.fieldAlias(named: "Status", in: entityAlias)
        )
        let priorityAlias = try #require(
            schema.fieldAlias(named: "Priorität", in: entityAlias)
        )
        let deadlineAlias = try #require(
            schema.fieldAlias(named: "Deadline", in: entityAlias)
        )
        let plan = try GraphQueryPlanValidator(
            calendar: calendar,
            timeZone: timeZone,
            referenceDate: referenceDate
        ).validate(
            GraphQueryPlan(
                entityAlias: entityAlias,
                filters: [
                    GraphQueryFilter(
                        fieldAlias: priorityAlias,
                        operation: .equals,
                        value: .choice("Hoch")
                    ),
                    GraphQueryFilter(
                        fieldAlias: statusAlias,
                        operation: .oneOf,
                        value: .choices(["Offen", "In Arbeit"])
                    ),
                    GraphQueryFilter(
                        fieldAlias: deadlineAlias,
                        operation: .isOverdue,
                        value: .none
                    )
                ],
                sorting: [
                    GraphQuerySort(
                        key: .field(deadlineAlias),
                        direction: .ascending
                    )
                ],
                projection: [
                    .nodeIdentity,
                    .field(statusAlias),
                    .field(priorityAlias),
                    .field(deadlineAlias)
                ],
                limit: 20
            ),
            against: schema
        )
        let expected = try await GraphChatQueryEngine(
            repository: repository,
            evidenceValidator: GraphEvidenceSourceValidator(
                repository: repository
            )
        ).execute(plan)
        #expect(expected.rows.map(\.label) == [
            "Aufgaben · Security Review",
            "Aufgaben · API Migration"
        ])

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
                                            fieldAlias: priorityAlias.rawValue,
                                            operation: GraphQueryFilterOperator.equals.rawValue,
                                            value: "Hoch",
                                            secondValue: nil,
                                            values: []
                                        ),
                                        GraphChatModelQueryFilterRequest(
                                            fieldAlias: statusAlias.rawValue,
                                            operation: GraphQueryFilterOperator.oneOf.rawValue,
                                            value: nil,
                                            secondValue: nil,
                                            values: ["Offen", "In Arbeit"]
                                        ),
                                        GraphChatModelQueryFilterRequest(
                                            fieldAlias: deadlineAlias.rawValue,
                                            operation: GraphQueryFilterOperator.isOverdue.rawValue,
                                            value: nil,
                                            secondValue: nil,
                                            values: []
                                        )
                                    ],
                                    sortFieldAlias: deadlineAlias.rawValue,
                                    sortDirection: GraphQuerySortDirection.ascending.rawValue,
                                    projectionFieldAliases: [
                                        statusAlias.rawValue,
                                        priorityAlias.rawValue,
                                        deadlineAlias.rawValue
                                    ],
                                    aggregation: nil,
                                    aggregationFieldAlias: nil,
                                    limit: 20
                                )
                            )
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Als wichtig wurden hohe Priorität, offener Status und überfällige Deadline verwendet.",
                                    evidenceIDs: expected.evidence.map(\.id)
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let graphScope = GraphScope(graphID: fixture.graph.id)
        let viewModel = GraphChatViewModel(
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope),
            graphName: fixture.graph.name,
            orchestrator: GraphChatOrchestrator(
                provider: provider,
                schemaProvider: schemaService,
                toolRunnerFactory: GraphChatProviderTestSupport.makeRealRuntimeFactory(
                    store: store,
                    schemaService: schemaService,
                    repository: repository
                ),
                referenceDate: { referenceDate },
                calendar: calendar,
                timeZone: timeZone
            ),
            schemaProvider: schemaService,
            availabilityProvider: GraphChatModelAvailabilityAdapter(provider: provider),
            indexStatusProvider: GraphChatUIFakeIndexProvider(
                value: .ready(documentCount: 5)
            ),
            historyStore: InMemoryGraphChatHistoryStore(),
            navigationActions: .disabled
        )

        await viewModel.load()
        viewModel.setComposerText("Welche wichtigen offenen Projektaufgaben sind überfällig?")
        viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating == false
                && viewModel.messages.count == 2
        }

        let finalMessage = try #require(viewModel.messages.last)
        guard case .assistant(let assistant) = finalMessage.state else {
            Issue.record("Expected the final transcript message to be an assistant response.")
            return
        }
        let answer = try #require(assistant.answer)
        #expect(assistant.phase == GraphChatAssistantPhase.final)
        #expect(answer.hasInsufficientEvidence == false)
        #expect(
            Set(answer.evidence.map { evidence in evidence.id })
                == Set(expected.evidence.map { evidence in evidence.id })
        )
        #expect(answer.appliedFilters.map { filter in filter.fieldName } == [
            "Priorität", "Status", "Deadline"
        ])
        #expect(answer.appliedFilters.map { filter in filter.operationDescription } == [
            "ist gleich", "ist einer von", "ist überfällig"
        ])
        #expect(answer.appliedFilters.allSatisfy {
            $0.valueDescription?.isEmpty != true
                || $0.fieldName == "Deadline"
        })
        #expect(answer.directAnswer.contains("Als wichtig"))

        let providerSnapshot = await provider.snapshot()
        #expect(providerSnapshot.toolResponses.count == 1)
        #expect(providerSnapshot.toolResponses[0].evidenceIDs.isEmpty == false)
        #expect(providerSnapshot.streamedRequests[0].schemaPrompt.contains("Security Review") == false)
        #expect(providerSnapshot.streamedRequests[0].schemaPrompt.contains("API Migration") == false)
    }
}
