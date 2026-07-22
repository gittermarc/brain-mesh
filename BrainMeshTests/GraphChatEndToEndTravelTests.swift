import Foundation
import Testing
@testable import BrainMesh

struct GraphChatEndToEndTravelTests {
    @MainActor
    @Test
    func travelYear2024FlowsThroughRealSchemaValidatorEngineToolsEvidenceViewModelAndRouting() async throws {
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
                    hour: 12
                )
            )
        )
        let fixture = fixtures.makeGraphChatTravelFixture(
            calendar: calendar,
            timeZone: timeZone
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let schemaService = GraphSchemaService(repository: repository)
        let schema = try await schemaService.makeSnapshot(
            in: GraphScope(graphID: fixture.graph.id)
        )
        let entityAlias = try #require(schema.entityAlias(named: "Reisen"))
        let startAlias = try #require(
            schema.fieldAlias(named: "Startdatum", in: entityAlias)
        )
        let endAlias = try #require(
            schema.fieldAlias(named: "Enddatum", in: entityAlias)
        )
        let countryAlias = try #require(
            schema.fieldAlias(named: "Land", in: entityAlias)
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
                        fieldAlias: startAlias,
                        operation: .inYear,
                        value: .year(2024)
                    )
                ],
                sorting: [
                    GraphQuerySort(
                        key: .field(startAlias),
                        direction: .ascending
                    )
                ],
                projection: [
                    .nodeIdentity,
                    .field(startAlias),
                    .field(endAlias),
                    .field(countryAlias)
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
            "Reisen · Paris Neujahr",
            "Reisen · New York Sommer"
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
                                            fieldAlias: startAlias.rawValue,
                                            operation: GraphQueryFilterOperator.inYear.rawValue,
                                            value: "2024",
                                            secondValue: nil,
                                            values: []
                                        )
                                    ],
                                    sortFieldAlias: startAlias.rawValue,
                                    sortDirection: GraphQuerySortDirection.ascending.rawValue,
                                    projectionFieldAliases: [
                                        startAlias.rawValue,
                                        endAlias.rawValue,
                                        countryAlias.rawValue
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
                                    directAnswer: "2024 sind Paris Neujahr und New York Sommer dokumentiert.",
                                    evidenceIDs: expected.evidence.map(\.id)
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let runtimeFactory = GraphChatProviderTestSupport.makeRealRuntimeFactory(
            store: store,
            schemaService: schemaService,
            repository: repository
        )
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaService,
            toolRunnerFactory: runtimeFactory,
            referenceDate: { referenceDate },
            calendar: calendar,
            timeZone: timeZone
        )
        let navigation = GraphChatUINavigationRecorder()
        let graphScope = GraphScope(graphID: fixture.graph.id)
        let viewModel = GraphChatViewModel(
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope),
            graphName: fixture.graph.name,
            orchestrator: orchestrator,
            schemaProvider: schemaService,
            availabilityProvider: GraphChatModelAvailabilityAdapter(provider: provider),
            indexStatusProvider: GraphChatUIFakeIndexProvider(
                value: .ready(documentCount: 4)
            ),
            historyStore: InMemoryGraphChatHistoryStore(),
            navigationActions: navigation.actions()
        )

        await viewModel.load()
        viewModel.setComposerText("Welche Reisen hatte ich 2024?")
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
        #expect(
            answer.appliedFilters.map { filter in filter.fieldName }
                == expected.appliedFilters.map { filter in filter.fieldName }
        )
        #expect(
            answer.appliedFilters.map { filter in filter.operationDescription }
                == expected.appliedFilters.map { filter in filter.operationDescription }
        )
        #expect(
            answer.appliedFilters.map { filter in filter.valueDescription }
                == expected.appliedFilters.map { filter in filter.valueDescription }
        )
        #expect(answer.evidence.allSatisfy {
            $0.sourceReference.graphID == fixture.graph.id
        })

        let source = try #require(answer.evidence.first { evidence in
            let presentation = GraphChatEvidencePresentation(evidence: evidence)
            return presentation.canOpenEntry && presentation.canShowInGraph
        })
        let presentation = GraphChatEvidencePresentation(evidence: source)
        viewModel.openEntry(presentation)
        viewModel.showInGraph(presentation)
        #expect(navigation.openedReferences == [source.sourceReference])
        #expect(navigation.shownReferences == [source.sourceReference])

        let providerSnapshot = await provider.snapshot()
        #expect(providerSnapshot.streamedRequests.count == 1)
        #expect(providerSnapshot.toolResponses.count == 1)
        #expect(providerSnapshot.toolResponses[0].tool == .queryDetailValues)
    }

    @MainActor
    @Test
    func undocumentedTravelYearEndsAsNoResultsWithoutInventedSources() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let referenceDate = Date(timeIntervalSince1970: 1_768_413_600)
        let fixture = fixtures.makeGraphChatTravelFixture(
            calendar: calendar,
            timeZone: timeZone
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let schemaService = GraphSchemaService(repository: repository)
        let schema = try await schemaService.makeSnapshot(
            in: GraphScope(graphID: fixture.graph.id)
        )
        let entityAlias = try #require(schema.entityAlias(named: "Reisen"))
        let startAlias = try #require(
            schema.fieldAlias(named: "Startdatum", in: entityAlias)
        )
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
                                            fieldAlias: startAlias.rawValue,
                                            operation: GraphQueryFilterOperator.inYear.rawValue,
                                            value: "2030",
                                            secondValue: nil,
                                            values: []
                                        )
                                    ],
                                    sortFieldAlias: nil,
                                    sortDirection: nil,
                                    projectionFieldAliases: [startAlias.rawValue],
                                    aggregation: nil,
                                    aggregationFieldAlias: nil,
                                    limit: 20
                                )
                            )
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    responseState: .noResults,
                                    directAnswer: "Für 2030 wurden keine dokumentierten Reisen gefunden.",
                                    hasInsufficientEvidence: true
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
                value: .ready(documentCount: 4)
            ),
            historyStore: InMemoryGraphChatHistoryStore(),
            navigationActions: .disabled
        )

        await viewModel.load()
        viewModel.setComposerText("Welche Reisen hatte ich 2030?")
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
        #expect(assistant.phase == GraphChatAssistantPhase.noResults)
        #expect(answer.hasInsufficientEvidence)
        #expect(answer.evidence.isEmpty)
        #expect(answer.directAnswer.contains("keine dokumentierten Reisen"))
    }
}
