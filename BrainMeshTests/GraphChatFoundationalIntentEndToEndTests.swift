import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat foundational intent end-to-end")
struct GraphChatFoundationalIntentEndToEndTests {
    @MainActor
    @Test
    func birthdayValueComesFromSwiftDataWithoutAProviderCall() async throws {
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let storedBirthday = try #require(
            calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: timeZone,
                    year: 1990,
                    month: 5,
                    day: 17
                )
            )
        )
        fixtures.makeDetailValue(
            attribute: person,
            field: birthday,
            dateValue: storedBirthday
        )
        try fixtures.save()

        let runtime = makeRuntime(
            store: store,
            calendar: calendar,
            timeZone: timeZone
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let events = await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: "Wann hat Person X Geburtstag?",
                graphScope: graphScope,
                chatScope: chatScope
            )
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
        guard case .resultList(let payload) = artifact.payload else {
            Issue.record("Expected a result-list artifact")
            return
        }
        let state = try #require(
            await runtime.orchestrator.conversationStateSnapshot()
        )
        let providerSnapshot = await runtime.provider.snapshot()
        let toolActivities: [GraphChatToolKind] = events.compactMap {
            event in
            if case .toolActivity(let activity) = event {
                return activity.tool
            }
            return nil
        }
        let expectedToolActivities: [GraphChatToolKind] = [
            .queryDetailValues,
            .queryDetailValues,
        ]

        #expect(answer.state == .answer)
        #expect(answer.directAnswer.isEmpty == false)
        #expect(answer.directAnswer.contains("1990"))
        #expect(answer.evidence.contains { evidence in
            evidence.fieldValues.contains {
                $0.fieldID == birthday.id
                    && $0.value == .date(storedBirthday)
            }
        })
        #expect(answer.artifactIDs.count == 1)
        #expect(payload.rows.count == 1)
        #expect(payload.rows[0].primaryText.contains("Person X"))
        #expect(
            payload.rows[0].secondaryText?.contains("Geburtsdatum")
                == true
        )
        #expect(payload.resultMetadata.totalCount == 1)
        #expect(payload.resultMetadata.returnedCount == 1)
        #expect(
            state.lastValidatedQueryPlan?.projection == [
                .nodeIdentity,
                .field(birthday.id),
            ]
        )
        #expect(state.lastValidatedQueryPlan?.limit == 1)
        #expect(
            state.referenceTargets.singular
                == .node(attributeNodeKey(person))
        )
        #expect(providerSnapshot.createdSessions.isEmpty)
        #expect(providerSnapshot.streamedSessions.isEmpty)
        #expect(terminalEventCount(events) == 1)
        #expect(toolActivities == expectedToolActivities)
        #expect(
            answer.directAnswer.contains(person.id.uuidString) == false
        )
        #expect(
            answer.directAnswer.contains(birthday.id.uuidString) == false
        )
    }

    @MainActor
    @Test
    func allTripsReachTheResultWindowAndArtifactWithoutAProviderCall()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let fixture = fixtures.makeGraphChatTravelFixture(
            calendar: calendar,
            timeZone: timeZone
        )
        try fixtures.save()

        let runtime = makeRuntime(
            store: store,
            calendar: calendar,
            timeZone: timeZone
        )
        let graphScope = GraphScope(graphID: fixture.graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let events = await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: "Welche Reisen habe ich gemacht?",
                graphScope: graphScope,
                chatScope: chatScope
            )
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
        guard case .resultList(let payload) = artifact.payload else {
            Issue.record("Expected a result-list artifact")
            return
        }
        let state = try #require(
            await runtime.orchestrator.conversationStateSnapshot()
        )
        let validatedPlan = try #require(
            state.lastValidatedQueryPlan
        )
        let firstReplay = try await runtime.queryEngine.execute(
            validatedPlan
        )
        let secondReplay = try await runtime.queryEngine.execute(
            validatedPlan
        )
        let providerSnapshot = await runtime.provider.snapshot()
        let expectedNames = fixture.tripsByName.keys.sorted {
            let left = BMSearch.fold($0)
            let right = BMSearch.fold($1)
            return left == right ? $0 < $1 : left < right
        }
        let conversationContext =
            GraphChatConversationContextBuilder().makeSnapshot(
                from: state.snapshot
            )
        let currentResolution =
            try await GraphChatConversationReferenceResolver(
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
        #expect(answer.directAnswer.isEmpty == false)
        #expect(answer.hasInsufficientEvidence == false)
        #expect(answer.artifactIDs.count == 1)
        #expect(payload.rows.map(\.primaryText) == expectedNames.map {
            "Reisen · \($0)"
        })
        #expect(payload.rows.count == fixture.tripsByName.count)
        #expect(
            payload.resultMetadata.totalCount
                == fixture.tripsByName.count
        )
        #expect(
            payload.resultMetadata.returnedCount
                == fixture.tripsByName.count
        )
        #expect(payload.resultMetadata.truncation.isTruncated == false)
        #expect(
            state.lastValidatedQueryPlan?.limit
                == GraphQueryPlanLimits.maximumResultLimit
        )
        #expect(
            state.lastValidatedQueryPlan?.projection
                == [.nodeIdentity]
        )
        #expect(
            firstReplay.rows.map(\.node)
                == secondReplay.rows.map(\.node)
        )
        #expect(
            Set(state.referenceTargets.plural.compactMap {
                if case .node(let node) = $0 {
                    return node
                }
                return nil
            })
                == Set(fixture.tripsByName.values.map {
                    attributeNodeKey($0)
                })
        )
        guard case .resolved(let currentScope) = currentResolution else {
            Issue.record("Expected CURRENT to resolve locally")
            return
        }
        #expect(
            Set(currentScope.nodes)
                == Set(fixture.tripsByName.values.map {
                    attributeNodeKey($0)
                })
        )
        #expect(providerSnapshot.createdSessions.isEmpty)
        #expect(providerSnapshot.streamedSessions.isEmpty)
        #expect(terminalEventCount(events) == 1)
        #expect(
            fixture.tripsByName.values.allSatisfy {
                answer.directAnswer.contains($0.id.uuidString) == false
            }
        )
    }

    @MainActor
    @Test
    func missingBirthdayValueEndsAsTypedNoResults() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Kontakte")
        let people = fixtures.makeEntity(name: "Personen", in: graph)
        fixtures.makeAttribute(name: "Person X", owner: people)
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let runtime = makeRuntime(
            store: store,
            calendar: calendar,
            timeZone: timeZone
        )
        let graphScope = GraphScope(graphID: graph.id)
        let events = await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: "Wann hat Person X Geburtstag?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let answer = try completedAnswer(events)
        let providerSnapshot = await runtime.provider.snapshot()

        #expect(answer.state == .noResults)
        #expect(answer.directAnswer.isEmpty == false)
        #expect(answer.evidence.isEmpty)
        #expect(answer.artifactIDs.isEmpty)
        #expect(answer.hasInsufficientEvidence)
        #expect(providerSnapshot.createdSessions.isEmpty)
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func duplicateNodeClarificationIsStoredAndContinuedLocally()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Kontakte")
        let people = fixtures.makeEntity(name: "Personen", in: graph)
        let first = fixtures.makeAttribute(
            name: "Person X",
            owner: people
        )
        let second = fixtures.makeAttribute(
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let firstDate = try #require(
            calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: timeZone,
                    year: 1988,
                    month: 1,
                    day: 2
                )
            )
        )
        let secondDate = try #require(
            calendar.date(
                from: DateComponents(
                    calendar: calendar,
                    timeZone: timeZone,
                    year: 1999,
                    month: 3,
                    day: 4
                )
            )
        )
        fixtures.makeDetailValue(
            attribute: first,
            field: birthday,
            dateValue: firstDate
        )
        fixtures.makeDetailValue(
            attribute: second,
            field: birthday,
            dateValue: secondDate
        )
        try fixtures.save()

        let runtime = makeRuntime(
            store: store,
            calendar: calendar,
            timeZone: timeZone
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let clarificationEvents =
            await GraphChatProviderTestSupport.collect(
                await runtime.orchestrator.streamAnswer(
                    question: "Wann hat Person X Geburtstag?",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
            )
        let clarificationAnswer = try completedAnswer(
            clarificationEvents
        )
        guard case .clarification(let clarification) =
            clarificationAnswer.state else {
            Issue.record("Expected a foundational clarification")
            return
        }
        let pendingState = try #require(
            await runtime.orchestrator.conversationStateSnapshot()
        )

        #expect(clarification.options.count == 2)
        #expect(
            pendingState.pendingClarification?.decision
                == .foundationalIntent
        )
        #expect(
            pendingState.pendingClarification?.sourceTurnID
                == pendingState.turnContexts.last?.id
        )
        #expect(pendingState.resultContexts.isEmpty)
        #expect(clarificationAnswer.artifactIDs.isEmpty)
        #expect(
            await runtime.provider.snapshot().createdSessions.isEmpty
        )

        let answerEvents = await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: "1",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let answer = try completedAnswer(answerEvents)
        let committedState = try #require(
            await runtime.orchestrator.conversationStateSnapshot()
        )
        let selectedNode = try #require(
            pendingState.pendingClarification?.options.first?
                .foundationalSelection?.node
        )
        let selectedDate = selectedNode == attributeNodeKey(first)
            ? firstDate
            : secondDate

        #expect(answer.state == .answer)
        #expect(answer.directAnswer.contains(
            Calendar(identifier: .gregorian)
                .component(.year, from: selectedDate)
                .description
        ))
        #expect(committedState.pendingClarification == nil)
        #expect(
            committedState.lastValidatedQueryPlan?.scope
                == .node(selectedNode)
        )
        #expect(
            await runtime.provider.snapshot().createdSessions.isEmpty
        )
        #expect(terminalEventCount(answerEvents) == 1)
    }

    @MainActor
    @Test
    func conflictingAuthoritativeDetailValuesAreNotPresentedAsFacts()
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let first = try #require(
            calendar.date(from: DateComponents(year: 1980))
        )
        let second = try #require(
            calendar.date(from: DateComponents(year: 1990))
        )
        fixtures.makeDetailValue(
            attribute: person,
            field: birthday,
            dateValue: first
        )
        fixtures.makeDetailValue(
            attribute: person,
            field: birthday,
            dateValue: second
        )
        try fixtures.save()

        let runtime = makeRuntime(
            store: store,
            calendar: calendar,
            timeZone: timeZone
        )
        let graphScope = GraphScope(graphID: graph.id)
        let events = await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: "Wann hat Person X Geburtstag?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let answer = try completedAnswer(events)

        #expect(answer.state == .noResults)
        #expect(answer.evidence.isEmpty)
        #expect(answer.artifactIDs.isEmpty)
        #expect(answer.directAnswer.contains("1980") == false)
        #expect(answer.directAnswer.contains("1990") == false)
        #expect(
            await runtime.provider.snapshot().createdSessions.isEmpty
        )
    }

    @MainActor
    @Test
    func emptyAndSingleItemCollectionsKeepTypedCardinality()
        async throws
    {
        for count in [0, 1] {
            let store = try BrainMeshTestContainer.makeInMemoryStore()
            let fixtures = BrainMeshFixtureBuilder(context: store.context)
            let graph = fixtures.makeGraph(name: "Portfolio")
            let projects = fixtures.makeEntity(
                name: "Projekte",
                in: graph
            )
            if count == 1 {
                fixtures.makeAttribute(
                    name: "Projekt Atlas",
                    owner: projects
                )
            }
            try fixtures.save()

            let timeZone = try #require(
                TimeZone(identifier: "Europe/Berlin")
            )
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let runtime = makeRuntime(
                store: store,
                calendar: calendar,
                timeZone: timeZone
            )
            let graphScope = GraphScope(graphID: graph.id)
            let chatScope = GraphChatScope.entireGraph(graphScope)
            let events = await GraphChatProviderTestSupport.collect(
                await runtime.orchestrator.streamAnswer(
                    question: "Liste alle Projekte auf.",
                    graphScope: graphScope,
                    chatScope: chatScope
                )
            )
            let answer = try completedAnswer(events)

            if count == 0 {
                #expect(answer.state == .noResults)
                #expect(answer.artifactIDs.isEmpty)
                #expect(answer.evidence.isEmpty)
            } else {
                #expect(answer.state == .answer)
                #expect(answer.artifactIDs.count == 1)
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
                guard case .resultList(let payload) =
                    artifact.payload else {
                    Issue.record("Expected a result-list artifact")
                    continue
                }
                #expect(payload.rows.map(\.primaryText) == [
                    "Projekte · Projekt Atlas"
                ])
                #expect(payload.resultMetadata.totalCount == 1)
            }
            #expect(
                await runtime.provider.snapshot().createdSessions.isEmpty
            )
            #expect(terminalEventCount(events) == 1)
        }
    }

    @MainActor
    @Test
    func completeCollectionUsesSharedSafetyLimitAndReportsTruncation()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Reisearchiv")
        let trips = fixtures.makeEntity(name: "Reisen", in: graph)
        for index in 0...GraphQueryPlanLimits.maximumResultLimit {
            fixtures.makeAttribute(
                name: String(format: "Reise %03d", index),
                owner: trips
            )
        }
        try fixtures.save()

        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let runtime = makeRuntime(
            store: store,
            calendar: calendar,
            timeZone: timeZone
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let events = await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: "Zeige mir alle Reisen.",
                graphScope: graphScope,
                chatScope: chatScope
            )
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
        guard case .resultList(let payload) = artifact.payload else {
            Issue.record("Expected a result-list artifact")
            return
        }

        #expect(
            artifact.estimatedByteCount
                <= GraphChatAnswerArtifactRegistryBudget.default
                    .maximumArtifactByteCount
        )
        #expect(
            Set(artifact.allEvidenceIDs).count
                == GraphQueryPlanLimits.maximumResultLimit
        )
        #expect(
            payload.rows.count
                == GraphQueryPlanLimits.maximumResultLimit
        )
        #expect(
            payload.resultMetadata.returnedCount
                == GraphQueryPlanLimits.maximumResultLimit
        )
        #expect(
            payload.resultMetadata.totalCount
                == GraphQueryPlanLimits.maximumResultLimit + 1
        )
        #expect(payload.resultMetadata.truncation.isTruncated)
        #expect(payload.resultMetadata.truncation.omittedCount == 1)
        #expect(answer.directAnswer.contains("Sicherheitslimit"))
        #expect(
            await runtime.provider.snapshot().createdSessions.isEmpty
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func cancellationBeforeQueryCompletionCommitsNothing() async throws {
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
        fixtures.makeDetailValue(
            attribute: person,
            field: birthday,
            dateValue: Date(timeIntervalSince1970: 0)
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let evidenceValidator = GraphEvidenceSourceValidator(
            repository: repository
        )
        let schemaService = GraphSchemaService(repository: repository)
        let provider = FakeGraphChatModelProvider()
        let blocker = BlockingFoundationalQueryExecutor()
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaService,
            foundationalQueryExecutor: blocker,
            toolRunnerFactory:
                EvidenceRegisteringFakeToolRunnerFactory(),
            artifactRevalidator:
                GraphChatLiveAnswerArtifactRevalidator(
                    evidenceValidator: evidenceValidator,
                    sourceRepository: repository
                ),
            evidenceValidator: evidenceValidator,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )
        let graphScope = GraphScope(graphID: graph.id)
        let stream = await orchestrator.streamAnswer(
            question: "Wann hat Person X Geburtstag?",
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )
        let collector = Task {
            await GraphChatProviderTestSupport.collect(stream)
        }
        await blocker.waitUntilStarted()
        await orchestrator.cancelCurrentGeneration()
        let events = await collector.value
        let state = await orchestrator.conversationStateSnapshot()

        #expect(events.last == .cancelled)
        #expect(terminalEventCount(events) == 1)
        #expect(events.contains {
            if case .completed = $0 {
                return true
            }
            return false
        } == false)
        #expect(state?.turnContexts.isEmpty != false)
        #expect(state?.resultContexts.isEmpty != false)
        #expect(state?.lastValidatedQueryPlan == nil)
        #expect(await provider.snapshot().createdSessions.isEmpty)
    }

    @MainActor
    @Test
    func unrecognizedQuestionFallsThroughToTheExistingProviderPipeline()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Portfolio")
        fixtures.makeEntity(name: "Projekte", in: graph)
        try fixtures.save()
        let timeZone = try #require(
            TimeZone(identifier: "Europe/Berlin")
        )
        let runtime = makeRuntime(
            store: store,
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone
        )
        await runtime.provider.enqueue(
            FakeGraphChatProviderScript(
                steps: [
                    .event(
                        .completed(
                            GraphChatProviderTestSupport.makeFinalAnswer(
                                directAnswer:
                                    "Projekte schaffen einen gemeinsamen Arbeitskontext."
                            )
                        )
                    )
                ]
            )
        )
        let graphScope = GraphScope(graphID: graph.id)
        let events = await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: "Warum sind Projekte wichtig?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let answer = try completedAnswer(events)
        let providerSnapshot = await runtime.provider.snapshot()

        #expect(
            answer.directAnswer
                == "Projekte schaffen einen gemeinsamen Arbeitskontext."
        )
        #expect(providerSnapshot.createdSessions.count == 1)
        #expect(providerSnapshot.streamedSessions.count == 1)
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func nodeOnlyCandidateCannotCompleteASingleFieldQuestion()
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
            calendar: Calendar(identifier: .gregorian),
            timeZone: timeZone,
            foundationalQueryExecutor:
                NodeOnlyFoundationalQueryExecutor(
                    node: attributeNodeKey(person),
                    label: person.displayName
                )
        )
        let graphScope = GraphScope(graphID: graph.id)
        let events = await GraphChatProviderTestSupport.collect(
            await runtime.orchestrator.streamAnswer(
                question: "Wann hat Person X Geburtstag?",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let answer = try completedAnswer(events)

        #expect(answer.state == .noResults)
        #expect(answer.evidence.isEmpty)
        #expect(answer.artifactIDs.isEmpty)
        #expect(
            await runtime.provider.snapshot().createdSessions.isEmpty
        )
    }

    private struct Runtime {
        let orchestrator: GraphChatOrchestrator
        let provider: FakeGraphChatModelProvider
        let repository: GraphReadRepository
        let queryEngine: GraphChatQueryEngine
    }

    @MainActor
    private func makeRuntime(
        store: BrainMeshTestStore,
        calendar: Calendar,
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
        let schemaService = GraphSchemaService(repository: repository)
        let queryEngine = GraphChatQueryEngine(
            repository: repository,
            evidenceValidator: evidenceValidator
        )
        let provider = FakeGraphChatModelProvider()
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaService,
            foundationalQueryExecutor:
                foundationalQueryExecutor ?? queryEngine,
            toolRunnerFactory:
                EvidenceRegisteringFakeToolRunnerFactory(),
            responseLanguageSelector:
                GraphChatResponseLanguageSelector(fallback: .german),
            artifactRevalidator:
                GraphChatLiveAnswerArtifactRevalidator(
                    evidenceValidator: evidenceValidator,
                    sourceRepository: repository
                ),
            evidenceValidator: evidenceValidator,
            referenceDate: {
                Date(timeIntervalSince1970: 1_768_413_600)
            },
            calendar: calendar,
            timeZone: timeZone
        )
        return Runtime(
            orchestrator: orchestrator,
            provider: provider,
            repository: repository,
            queryEngine: queryEngine
        )
    }

    private func completedAnswer(
        _ events: [GraphChatStreamEvent]
    ) throws -> GraphChatAnswer {
        try #require(events.compactMap { event in
            if case .completed(let answer) = event {
                return answer
            }
            return nil
        }.last)
    }

    private func terminalEventCount(
        _ events: [GraphChatStreamEvent]
    ) -> Int {
        events.filter { event in
            switch event {
            case .completed, .cancelled, .failure:
                return true
            case .started, .toolActivity, .partialAnswer:
                return false
            }
        }.count
    }

    private func attributeNodeKey(
        _ attribute: MetaAttribute
    ) -> NodeRefKey {
        NodeRefKey(kind: .attribute, id: attribute.id)
    }
}

private struct NodeOnlyFoundationalQueryExecutor:
    GraphChatFoundationalQueryExecuting
{
    let node: NodeRefKey
    let label: String

    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult {
        GraphChatQueryResult(
            state: .success,
            rows: [
                GraphChatQueryResultRow(
                    node: node,
                    label: label,
                    cells: [],
                    evidenceIDs: []
                )
            ],
            aggregation: nil,
            appliedFilters: [],
            evidence: [],
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

private actor BlockingFoundationalQueryExecutor:
    GraphChatFoundationalQueryExecuting
{
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult {
        _ = plan
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
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
            startWaiters.append(continuation)
        }
    }
}
