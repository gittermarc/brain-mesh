import Foundation
import Testing
@testable import BrainMesh

@MainActor
@Suite("Foundational Accuracy acceptance")
struct GraphChatFoundationalAccuracyAcceptanceTests {
    @Test
    func legacyDetailValueIsIdenticalInUIRepositoryQueryAndChat()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Kontakte")
        let people = fixtures.makeEntity(name: "Personen", in: graph)
        let person = fixtures.makeAttribute(
            name: "Person X",
            owner: people
        )
        let birthday = fixtures.makeDetailField(
            owner: people,
            name: "Geburtsdatum",
            type: .date,
            sortIndex: 0
        )
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        let storedDate = try calendarDate(
            year: 1985,
            month: 10,
            day: 27,
            timeZone: timeZone
        )
        let value = fixtures.makeDetailValue(
            attribute: person,
            field: birthday,
            dateValue: storedDate
        )
        birthday.graphID = nil
        value.graphID = nil
        try fixtures.save()

        _ = try await GraphBootstrap.migrateLegacyRecordsIfNeeded(
            defaultGraphID: graph.id,
            using: store.context
        )
        let scope = GraphScope(graphID: graph.id)
        let runtime = makeRuntime(
            store: store,
            timeZone: timeZone
        )
        let repositoryValues = try await runtime.repository
            .detailValues(in: scope)
        let events = await collect(
            runtime: runtime,
            question: "Wann hat Person X Geburtstag?",
            graphScope: scope
        )
        let answer = try completedAnswer(events)
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let plan = try #require(state.lastValidatedQueryPlan)
        let replay = try await runtime.queryEngine.execute(plan)
        let replayValue = try #require(
            replay.rows.first?.cells.first {
                $0.fieldID == birthday.id
            }?.value
        )

        #expect(birthday.graphID == graph.id)
        #expect(value.graphID == graph.id)
        #expect(
            DetailsFormatting.displayValue(
                for: birthday,
                on: person
            ) == storedDate.formatted(
                date: .numeric,
                time: .omitted
            )
        )
        #expect(
            repositoryValues.first {
                $0.attributeID == person.id
                    && $0.fieldID == birthday.id
            }?.value == .date(storedDate)
        )
        #expect(replayValue == .date(storedDate))
        #expect(
            answer.directAnswer
                == "Geburtsdatum von Person X: 27.10.1985."
        )
        #expect(answer.evidence.isEmpty == false)
        #expect(answer.artifactIDs.count == 1)
        #expect(terminalEventCount(events) == 1)
        expectNoTechnicalPresentation(
            answer.directAnswer,
            identifiers: [
                graph.id,
                people.id,
                person.id,
                birthday.id,
                value.id,
            ]
        )
    }

    @Test
    func falseProviderBirthdayNeverReachesUIOrCopy()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Kontakte")
        let people = fixtures.makeEntity(name: "Personen", in: graph)
        let person = fixtures.makeAttribute(
            name: "Person X",
            owner: people
        )
        let birthday = fixtures.makeDetailField(
            owner: people,
            name: "Geburtsdatum",
            type: .date,
            sortIndex: 0
        )
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        let storedDate = try calendarDate(
            year: 1990,
            month: 5,
            day: 17,
            timeZone: timeZone
        )
        fixtures.makeDetailValue(
            attribute: person,
            field: birthday,
            dateValue: storedDate
        )
        try fixtures.save()
        let runtime = makeRuntime(
            store: store,
            timeZone: timeZone
        )
        await runtime.provider.enqueue(
            FakeGraphChatProviderScript(
                steps: [
                    .event(
                        .partialAnswer(
                            GraphChatProviderPartialAnswer(
                                directAnswer:
                                    "Geburtsdatum von Person X: 02.11.1999.",
                                hasInsufficientEvidence: false
                            )
                        )
                    ),
                    .event(
                        .completed(
                            GraphChatProviderTestSupport.makeFinalAnswer(
                                directAnswer:
                                    "Geburtsdatum von Person X: 02.11.1999."
                            )
                        )
                    ),
                ]
            )
        )

        let events = await collect(
            runtime: runtime,
            question: "Wann hat Person X Geburtstag?",
            graphScope: GraphScope(graphID: graph.id)
        )
        let answer = try completedAnswer(events)
        var messageState = GraphChatAssistantMessageState(
            question: "Wann hat Person X Geburtstag?"
        )
        for event in events {
            messageState.apply(event)
        }
        let copy = try #require(
            GraphChatCopyContentBuilder.payload(
                for: messageState,
                sourcePolicy: .none
            )
        )
        let providerState = await runtime.provider.snapshot()

        #expect(
            answer.directAnswer
                == "Geburtsdatum von Person X: 17.05.1990."
        )
        #expect(messageState.text == answer.directAnswer)
        #expect(copy.text == answer.directAnswer)
        #expect(answer.directAnswer.contains("02.11.1999") == false)
        #expect(copy.text.contains("02.11.1999") == false)
        #expect(providerState.createdSessions.isEmpty)
        #expect(providerState.streamedSessions.isEmpty)
        #expect(terminalEventCount(events) == 1)
    }

    @Test
    func searchOnlyHallucinationIsBlockedWithoutAFieldValue()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Kontakte")
        let people = fixtures.makeEntity(name: "Personen", in: graph)
        let person = fixtures.makeAttribute(
            name: "Person X",
            owner: people
        )
        fixtures.makeDetailField(
            owner: people,
            name: "Geburtsdatum",
            type: .date,
            sortIndex: 0
        )
        try fixtures.save()
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        let runtime = makeRuntime(
            store: store,
            timeZone: timeZone,
            foundationalQueryExecutor:
                AcceptanceSearchOnlyQueryExecutor(
                    graphScope: GraphScope(graphID: graph.id),
                    node: NodeRefKey(
                        kind: .attribute,
                        id: person.id
                    ),
                    entityID: people.id,
                    label: "Person X"
                )
        )
        await runtime.provider.enqueue(
            FakeGraphChatProviderScript(
                steps: [
                    .event(
                        .completed(
                            GraphChatProviderTestSupport.makeFinalAnswer(
                                directAnswer:
                                    "Geburtsdatum von Person X: 02.11.1999."
                            )
                        )
                    )
                ]
            )
        )

        let events = await collect(
            runtime: runtime,
            question: "Wann hat Person X Geburtstag?",
            graphScope: GraphScope(graphID: graph.id)
        )
        let answer = try completedAnswer(events)

        #expect(answer.state == .noResults)
        #expect(answer.directAnswer.contains("02.11.1999") == false)
        #expect(answer.evidence.isEmpty)
        #expect(answer.artifactIDs.isEmpty)
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(events) == 1)
    }

    @Test
    func completeTravelCollectionRetainsEveryAllowedResultAndCurrent()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Reisearchiv")
        let trips = fixtures.makeEntity(name: "Reisen", in: graph)
        let names = [
            "Berlin 2024",
            "New York 2025",
            "Altmühltal 2026",
        ]
        for name in names {
            fixtures.makeAttribute(name: name, owner: trips)
        }
        try fixtures.save()
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        let runtime = makeRuntime(
            store: store,
            timeZone: timeZone
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let events = await collect(
            runtime: runtime,
            question: "Welche Reisen habe ich gemacht?",
            graphScope: graphScope
        )
        let answer = try completedAnswer(events)
        let presentation = await runtime.orchestrator
            .resolveAnswerPresentation(
                artifactIDs: answer.artifactIDs,
                evidence: answer.evidence,
                graphScope: graphScope,
                chatScope: chatScope
            )
        let artifact = try #require(
            presentation.artifacts.first?.artifact
        )
        guard case .resultList(let payload) = artifact.payload
        else {
            Issue.record("Expected a result-list artifact.")
            return
        }
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let conversationContext =
            GraphChatConversationContextBuilder().makeSnapshot(
                from: state.snapshot
            )
        let current = try await
            GraphChatConversationReferenceResolver(
                revalidator:
                    GraphChatRepositoryConversationReferenceRevalidator(
                        repository: runtime.repository,
                        queryEngine: runtime.queryEngine
                    )
            ).resolveScope(
                .latestResults,
                in: conversationContext,
                expectedGraphScope: graphScope,
                expectedChatScope: chatScope
            )

        #expect(answer.state == .answer)
        #expect(answer.artifactIDs.count == 1)
        #expect(payload.rows.count == names.count)
        #expect(payload.resultMetadata.totalCount == names.count)
        #expect(payload.resultMetadata.returnedCount == names.count)
        #expect(payload.resultMetadata.truncation.isTruncated == false)
        #expect(Set(payload.rows.map(\.primaryText)) == Set(
            names.map { "Reisen · \($0)" }
        ))
        guard case .resolved(let currentScope) = current else {
            Issue.record("Expected CURRENT to resolve.")
            return
        }
        #expect(currentScope.nodes.count == names.count)
        #expect(terminalEventCount(events) == 1)
    }

    @Test
    func duplicateNamesClarifyBeforeAnyValueQuery()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Kontakte")
        let people = fixtures.makeEntity(name: "Personen", in: graph)
        fixtures.makeAttribute(name: "Alex", owner: people)
        fixtures.makeAttribute(name: "Alex", owner: people)
        fixtures.makeDetailField(
            owner: people,
            name: "Geburtsdatum",
            type: .date,
            sortIndex: 0
        )
        try fixtures.save()
        let runtime = makeRuntime(
            store: store,
            timeZone: try #require(
                TimeZone(identifier: "Europe/Berlin")
            )
        )

        let events = await collect(
            runtime: runtime,
            question: "Wann hat Alex Geburtstag?",
            graphScope: GraphScope(graphID: graph.id)
        )
        let answer = try completedAnswer(events)
        let toolActivities = events.compactMap {
            event -> GraphChatToolActivity? in
            if case .toolActivity(let activity) = event {
                return activity
            }
            return nil
        }

        guard case .clarification(let clarification) =
            answer.state else {
            Issue.record("Expected a clarification.")
            return
        }
        #expect(clarification.options.count == 2)
        #expect(toolActivities.isEmpty)
        #expect(answer.evidence.isEmpty)
        #expect(answer.artifactIDs.isEmpty)
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(events) == 1)
        expectNoTechnicalPresentation(
            answer.directAnswer,
            identifiers: [graph.id, people.id]
        )
    }

    @Test
    func conflictingDuplicateValuesProduceNeitherUIAuthorityNorChatFact()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Kontakte")
        let people = fixtures.makeEntity(name: "Personen", in: graph)
        let person = fixtures.makeAttribute(
            name: "Person X",
            owner: people
        )
        let birthday = fixtures.makeDetailField(
            owner: people,
            name: "Geburtsdatum",
            type: .date,
            sortIndex: 0
        )
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        fixtures.makeDetailValue(
            attribute: person,
            field: birthday,
            dateValue: try calendarDate(
                year: 1985,
                month: 10,
                day: 27,
                timeZone: timeZone
            )
        )
        fixtures.makeDetailValue(
            attribute: person,
            field: birthday,
            dateValue: try calendarDate(
                year: 1986,
                month: 10,
                day: 27,
                timeZone: timeZone
            )
        )
        try fixtures.save()
        let runtime = makeRuntime(
            store: store,
            timeZone: timeZone
        )

        let events = await collect(
            runtime: runtime,
            question: "Wann hat Person X Geburtstag?",
            graphScope: GraphScope(graphID: graph.id)
        )
        let answer = try completedAnswer(events)
        let repositoryValues = try await runtime.repository
            .detailValues(in: GraphScope(graphID: graph.id))

        #expect(
            DetailsFormatting.displayValue(
                for: birthday,
                on: person
            ) == DetailsFormatting.conflictDisplayText
        )
        #expect(
            repositoryValues.contains {
                $0.attributeID == person.id
                    && $0.fieldID == birthday.id
            } == false
        )
        #expect(answer.state == .noResults)
        #expect(answer.evidence.isEmpty)
        #expect(answer.artifactIDs.isEmpty)
        #expect(
            answer.directAnswer.contains("1985") == false
        )
        #expect(
            answer.directAnswer.contains("1986") == false
        )
        #expect(terminalEventCount(events) == 1)
    }

    @Test
    func graphSessionTurnAndCancellationBoundariesRejectLateFacts()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graphA = fixtures.makeGraph(name: "A")
        let graphB = fixtures.makeGraph(name: "B")
        let peopleA = fixtures.makeEntity(name: "Personen", in: graphA)
        let peopleB = fixtures.makeEntity(name: "Personen", in: graphB)
        fixtures.makeAttribute(name: "Person X", owner: peopleA)
        let personB = fixtures.makeAttribute(
            name: "Person X",
            owner: peopleB
        )
        fixtures.makeDetailField(
            owner: peopleA,
            name: "Geburtsdatum",
            type: .date,
            sortIndex: 0
        )
        let birthdayB = fixtures.makeDetailField(
            owner: peopleB,
            name: "Geburtsdatum",
            type: .date,
            sortIndex: 0
        )
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        fixtures.makeDetailValue(
            attribute: personB,
            field: birthdayB,
            dateValue: try calendarDate(
                year: 1977,
                month: 7,
                day: 7,
                timeZone: timeZone
            )
        )
        try fixtures.save()
        let runtime = makeRuntime(
            store: store,
            timeZone: timeZone
        )

        let foreignGraphEvents = await collect(
            runtime: runtime,
            question: "Wann hat Person X Geburtstag?",
            graphScope: GraphScope(graphID: graphA.id)
        )
        let foreignGraphAnswer = try completedAnswer(
            foreignGraphEvents
        )
        #expect(foreignGraphAnswer.state == .noResults)
        #expect(
            foreignGraphAnswer.directAnswer.contains("1977")
                == false
        )

        await runtime.orchestrator.discardSession()
        let graphBEvents = await collect(
            runtime: runtime,
            question: "Wann hat Person X Geburtstag?",
            graphScope: GraphScope(graphID: graphB.id)
        )
        let graphBAnswer = try completedAnswer(graphBEvents)
        #expect(
            graphBAnswer.directAnswer
                == "Geburtsdatum von Person X: 07.07.1977."
        )

        let blockingRuntime = makeRuntime(
            store: store,
            timeZone: timeZone,
            foundationalQueryExecutor:
                AcceptanceBlockingQueryExecutor()
        )
        let stream = await blockingRuntime.orchestrator
            .streamAnswer(
                question: "Wann hat Person X Geburtstag?",
                graphScope: GraphScope(graphID: graphB.id),
                chatScope: .entireGraph(
                    GraphScope(graphID: graphB.id)
                )
            )
        let collector = Task {
            await GraphChatProviderTestSupport.collect(stream)
        }
        let blocker = try #require(
            blockingRuntime.blockingExecutor
        )
        await blocker.waitUntilStarted()
        await blockingRuntime.orchestrator
            .cancelCurrentGeneration()
        let cancellationEvents = await collector.value

        #expect(cancellationEvents.last == .cancelled)
        #expect(terminalEventCount(cancellationEvents) == 1)
        #expect(cancellationEvents.contains {
            if case .completed = $0 {
                return true
            }
            return false
        } == false)
    }

    private struct Runtime {
        let orchestrator: GraphChatOrchestrator
        let provider: FakeGraphChatModelProvider
        let repository: GraphReadRepository
        let queryEngine: GraphChatQueryEngine
        let blockingExecutor: AcceptanceBlockingQueryExecutor?
    }

    private func makeRuntime(
        store: BrainMeshTestStore,
        timeZone: TimeZone,
        foundationalQueryExecutor:
            (any GraphChatFoundationalQueryExecuting)? = nil
    ) -> Runtime {
        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let evidenceValidator = GraphEvidenceSourceValidator(
            repository: repository
        )
        let schemaService = GraphSchemaService(
            repository: repository
        )
        let queryEngine = GraphChatQueryEngine(
            repository: repository,
            evidenceValidator: evidenceValidator
        )
        let provider = FakeGraphChatModelProvider()
        let blockingExecutor =
            foundationalQueryExecutor
                as? AcceptanceBlockingQueryExecutor
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaService,
            foundationalQueryExecutor:
                foundationalQueryExecutor ?? queryEngine,
            toolRunnerFactory:
                EvidenceRegisteringFakeToolRunnerFactory(),
            responseLanguageSelector:
                GraphChatResponseLanguageSelector(
                    fallback: .german
                ),
            artifactRevalidator:
                GraphChatLiveAnswerArtifactRevalidator(
                    evidenceValidator: evidenceValidator,
                    sourceRepository: repository
                ),
            evidenceValidator: evidenceValidator,
            referenceDate: {
                Date(timeIntervalSince1970: 1_800_000_000)
            },
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )
        return Runtime(
            orchestrator: orchestrator,
            provider: provider,
            repository: repository,
            queryEngine: queryEngine,
            blockingExecutor: blockingExecutor
        )
    }

    private func collect(
        runtime: Runtime,
        question: String,
        graphScope: GraphScope
    ) async -> [GraphChatStreamEvent] {
        await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: question,
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
    }

    private func completedAnswer(
        _ events: [GraphChatStreamEvent]
    ) throws -> GraphChatAnswer {
        try #require(
            events.compactMap { event in
                if case .completed(let answer) = event {
                    return answer
                }
                return nil
            }.last
        )
    }

    private func terminalEventCount(
        _ events: [GraphChatStreamEvent]
    ) -> Int {
        events.filter {
            switch $0 {
            case .completed, .cancelled, .failure:
                return true
            case .started, .toolActivity, .partialAnswer:
                return false
            }
        }.count
    }

    private func calendarDate(
        year: Int,
        month: Int,
        day: Int,
        timeZone: TimeZone
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return try #require(
            calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: timeZone,
                    year: year,
                    month: month,
                    day: day
                )
            )
        )
    }

    private func expectNoTechnicalPresentation(
        _ text: String,
        identifiers: [UUID]
    ) {
        for identifier in identifiers {
            #expect(text.contains(identifier.uuidString) == false)
        }
        for token in [
            "E1",
            "F1",
            "N1",
            "CURRENT",
            "QueryDetailValuesTool",
            "RepositoryError",
        ] {
            #expect(text.contains(token) == false)
        }
    }
}

private struct AcceptanceSearchOnlyQueryExecutor:
    GraphChatFoundationalQueryExecuting
{
    let graphScope: GraphScope
    let node: NodeRefKey
    let entityID: UUID
    let label: String

    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult {
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphScope.graphID,
                sourceKind: .attribute,
                sourceID: node.id,
                node: GraphSourceNodeReference(
                    kind: node.kind,
                    id: node.id
                ),
                owner: GraphSourceNodeReference(
                    kind: .entity,
                    id: entityID
                )
            ),
            summary: label,
            navigationTitle: label,
            identitySuffix: "search-only"
        )
        return GraphChatQueryResult(
            state: .success,
            rows: [
                GraphChatQueryResultRow(
                    node: node,
                    label: label,
                    cells: [],
                    evidenceIDs: [evidence.id]
                )
            ],
            aggregation: nil,
            appliedFilters: [],
            evidence: [evidence],
            resultWindow: GraphChatResultWindow(
                totalCount: 1,
                returnedCount: 1,
                limit: plan.limit,
                limitReached: false,
                limitSource: .query
            )
        )
    }
}

private actor AcceptanceBlockingQueryExecutor:
    GraphChatFoundationalQueryExecuting
{
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult {
        _ = plan
        started = true
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
        }
        try await Task.sleep(nanoseconds: UInt64.max)
        throw CancellationError()
    }

    func waitUntilStarted() async {
        guard started == false else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
