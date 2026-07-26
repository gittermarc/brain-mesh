//
//  GraphChatMultiTurnOrchestratorTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

@Suite("Graph chat multi-turn orchestration")
struct GraphChatMultiTurnOrchestratorTests {
    @MainActor
    @Test
    func clarificationSelectionResumesTheOriginalValidatedOpenOperation() async throws {
        let setup = try await makeProjectSetup(
            continuationScript: FakeGraphChatProviderScript(
                steps: [
                    .toolRequest(.getNode(nodeAlias: "CURRENT", relatedLimit: 10)),
                    .event(
                        .completed(
                            GraphChatProviderTestSupport.makeFinalAnswer(
                                directAnswer: "Der ausgewählte Eintrag wurde validiert geöffnet."
                            )
                        )
                    ),
                ]
            )
        )

        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Zeige alle Projektaufgaben nach Deadline.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )

        let clarificationEvents = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Öffne den 99.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let clarificationAnswer = try #require(completedAnswer(in: clarificationEvents))
        guard case .clarification(let clarification) = clarificationAnswer.state else {
            Issue.record("Expected an explicit clarification answer.")
            return
        }
        #expect(clarification.options.count == 5)

        let stateBeforeInvalid = await setup.orchestrator.conversationStateSnapshot()
        let pendingBeforeInvalid = try #require(stateBeforeInvalid?.pendingClarification)
        let snapshotBeforeInvalid = await setup.provider.snapshot()
        #expect(snapshotBeforeInvalid.streamedRequests.count == 1)

        let invalidSelectionEvents = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Irgendetwas anderes",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let invalidSelectionAnswer = try #require(completedAnswer(in: invalidSelectionEvents))
        guard case .clarification = invalidSelectionAnswer.state else {
            Issue.record("Expected an invalid selection to remain in clarification.")
            return
        }
        let stateAfterInvalid = await setup.orchestrator.conversationStateSnapshot()
        let pendingAfterInvalid = try #require(stateAfterInvalid?.pendingClarification)
        #expect(pendingAfterInvalid.id == pendingBeforeInvalid.id)
        let providerAfterInvalid = await setup.provider.snapshot()
        #expect(providerAfterInvalid.streamedRequests.count == 1)

        let continuationEvents = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "2",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let continuationAnswer = try #require(completedAnswer(in: continuationEvents))
        #expect(continuationAnswer.state == .answer)

        let providerSnapshot = await setup.provider.snapshot()
        #expect(providerSnapshot.streamedRequests.count == 2)
        let continuationRequest = providerSnapshot.streamedRequests[1]
        #expect(continuationRequest.question == "Öffne den 99.")
        #expect(continuationRequest.continuationOperation == .openReference)
        #expect(continuationRequest.responseLanguage == .german)
        let currentAlias = try #require(
            continuationRequest.conversationContext?.alias("CURRENT")
        )
        guard case .node(let selectedNode, _) = currentAlias.target else {
            Issue.record("Expected CURRENT to contain one validated node.")
            return
        }
        let expectedSecondTask = try #require(setup.fixture.tasksByName["Release Notes"])
        #expect(selectedNode == NodeRefKey(kind: .attribute, id: expectedSecondTask.id))
        let stateAfterContinuation = await setup.orchestrator.conversationStateSnapshot()
        #expect(stateAfterContinuation?.pendingClarification == nil)
    }

    @MainActor
    @Test
    func queryFollowUpRestrictsCurrentReferenceToTheFirstThreeResults() async throws {
        let setup = try await makeProjectSetup(
            continuationScript: Self.answerScript("Die ersten drei wurden verwendet.")
        )

        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Zeige alle Projektaufgaben nach Deadline.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let events = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Nur die ersten drei.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let answer = try #require(completedAnswer(in: events))
        #expect(answer.state == .answer)

        let snapshot = await setup.provider.snapshot()
        #expect(snapshot.streamedRequests.count == 2)
        let request = snapshot.streamedRequests[1]
        #expect(request.continuationOperation == .filterReferenceSet)
        let current = try #require(request.conversationContext?.alias("CURRENT"))
        guard case .resultSet(_, let nodes, _) = current.target else {
            Issue.record("Expected CURRENT to contain the validated result subset.")
            return
        }
        #expect(nodes.count == 3)
    }

    @MainActor
    @Test
    func queryOldestFollowUpKeepsTheValidatedSetAndSortOperation() async throws {
        let setup = try await makeProjectSetup(
            continuationScript: Self.answerScript("Der älteste Eintrag wurde bestimmt.")
        )

        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Zeige alle Projektaufgaben nach Deadline.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let events = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Welches davon ist am ältesten?",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let answer = try #require(completedAnswer(in: events))
        #expect(answer.state == .answer)

        let snapshot = await setup.provider.snapshot()
        #expect(snapshot.streamedRequests.count == 2)
        let request = snapshot.streamedRequests[1]
        #expect(request.continuationOperation == .sortReferenceSet)
        let current = try #require(request.conversationContext?.alias("CURRENT"))
        guard case .resultSet(_, let nodes, _) = current.target else {
            Issue.record("Expected CURRENT to contain the validated result set.")
            return
        }
        #expect(nodes.count == 5)
    }

    @MainActor
    @Test
    func currentQueryDerivesEntityInsteadOfTrustingAWrongModelAlias() async throws {
        try await verifyTypedCurrentQuery(
            modelEntityAlias: "E999",
            expectedAnswer: "Die validierte Auswahl wurde erneut abgefragt."
        )
    }

    @MainActor
    @Test
    func currentQueryDoesNotRequireAModelEntityAlias() async throws {
        try await verifyTypedCurrentQuery(
            modelEntityAlias: "",
            expectedAnswer: "Die Auswahl funktioniert ohne Modell-Entity-Alias."
        )
    }

    @MainActor
    @Test
    func graphLockDiscardsAPendingClarificationBeforeTheNextTurn() async throws {
        let setup = try await makeProjectSetup(
            continuationScript: Self.answerScript("Neuer Turn nach Entsperrung")
        )

        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Zeige alle Projektaufgaben nach Deadline.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Öffne den 99.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let pendingState = await setup.orchestrator.conversationStateSnapshot()
        #expect(pendingState?.pendingClarification != nil)

        await setup.orchestrator.discardSession(reason: .graphLocked)
        let discardedState = await setup.orchestrator.conversationStateSnapshot()
        #expect(discardedState == nil)

        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Welche Projekte sind offen?",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let resetState = try #require(
            await setup.orchestrator.conversationStateSnapshot()
        )
        #expect(resetState.pendingClarification == nil)
        #expect(resetState.lastResetReason == .graphLocked)
    }

    @MainActor
    @Test
    func cancellationKeepsThePreviouslyCommittedClarificationIntact() async throws {
        let partialAnswer = "Die Fortsetzung wartet auf den Abbruch."
        let setup = try await makeProjectSetup(
            continuationScript: FakeGraphChatProviderScript(
                steps: [
                    .event(
                        .partialAnswer(
                            GraphChatProviderPartialAnswer(
                                directAnswer: partialAnswer,
                                hasInsufficientEvidence: nil
                            )
                        )
                    ),
                    .waitForCancellation,
                ]
            )
        )

        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Zeige alle Projektaufgaben nach Deadline.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Öffne den 99.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let committedState = await setup.orchestrator.conversationStateSnapshot()
        let committedPending = try #require(committedState?.pendingClarification)

        let stream = await setup.orchestrator.streamAnswer(
            question: "2",
            graphScope: setup.graphScope,
            chatScope: setup.chatScope
        )
        var iterator = stream.makeAsyncIterator()
        var events: [GraphChatStreamEvent] = []
        while let event = await iterator.next() {
            events.append(event)
            if event == .partialAnswer(partialAnswer) {
                break
            }
        }
        try #require(events.contains(.partialAnswer(partialAnswer)))

        let providerBeforeCancellation = await setup.provider.snapshot()
        #expect(providerBeforeCancellation.streamedRequests.count == 2)

        await setup.orchestrator.cancelCurrentGeneration()
        while let event = await iterator.next() {
            events.append(event)
        }

        #expect(events.contains(.cancelled))
        let cancellationState = await setup.orchestrator.conversationStateSnapshot()
        let stateAfterCancellation = try #require(cancellationState)
        #expect(stateAfterCancellation.pendingClarification == committedPending)
    }

    @Test
    func responseLanguageFollowsEachCurrentQuestionAndItsSessionInstructions() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                Self.answerScript("Deutsche Antwort"),
                Self.answerScript("English answer"),
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(),
            responseLanguageSelector: GraphChatResponseLanguageSelector(fallback: .german)
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Welche Projekte sind offen?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Which projects are open?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )

        let snapshot = await provider.snapshot()
        #expect(snapshot.streamedRequests.map(\.responseLanguage) == [.german, .english])
        let firstSession = try #require(snapshot.createdSessions.first)
        let secondSession = try #require(snapshot.createdSessions.dropFirst().first)
        #expect(
            snapshot.sessionConfigurations[firstSession]?.instructions.contains(
                "Antworte vollständig auf Deutsch"
            ) == true
        )
        #expect(
            snapshot.sessionConfigurations[secondSession]?.instructions.contains(
                "Answer entirely in English"
            ) == true
        )
    }

    @Test
    func unsupportedRequestCompletesWithoutCreatingAModelSession() async throws {
        let provider = FakeGraphChatModelProvider()
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Lösche den Node Phoenix.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let answer = try #require(completedAnswer(in: events))

        #expect(answer.state == .unsupported(.graphMutation))
        let snapshot = await provider.snapshot()
        #expect(snapshot.createdSessions.isEmpty)
        #expect(snapshot.streamedRequests.isEmpty)
    }
}

extension GraphChatMultiTurnOrchestratorTests {
    @MainActor
    fileprivate struct ProjectSetup {
        let fixture: GraphChatProjectFixture
        let graphScope: GraphScope
        let chatScope: GraphChatScope
        let provider: FakeGraphChatModelProvider
        let orchestrator: GraphChatOrchestrator
    }

    @MainActor
    fileprivate func makeProjectSetup(
        continuationScript: FakeGraphChatProviderScript
    ) async throws -> ProjectSetup {
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
        let statusAlias = try #require(schema.fieldAlias(named: "Status", in: entityAlias))
        let priorityAlias = try #require(schema.fieldAlias(named: "Priorität", in: entityAlias))
        let deadlineAlias = try #require(schema.fieldAlias(named: "Deadline", in: entityAlias))
        let queryRequest = GraphChatModelQueryRequest(
            entityAlias: entityAlias.rawValue,
            filters: [],
            sortFieldAlias: deadlineAlias.rawValue,
            sortDirection: GraphQuerySortDirection.ascending.rawValue,
            projectionFieldAliases: [
                statusAlias.rawValue,
                priorityAlias.rawValue,
                deadlineAlias.rawValue,
            ],
            aggregation: nil,
            aggregationFieldAlias: nil,
            limit: 20
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.queryDetailValues(queryRequest)),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Die Aufgaben wurden nach Deadline sortiert."
                                )
                            )
                        ),
                    ]
                ),
                continuationScript,
            ]
        )
        let graphScope = GraphScope(graphID: fixture.graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let resolver = GraphChatConversationReferenceResolver(
            revalidator: GraphChatRepositoryConversationReferenceRevalidator(
                repository: repository
            )
        )
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaService,
            toolRunnerFactory: GraphChatProviderTestSupport.makeRealRuntimeFactory(
                store: store,
                schemaService: schemaService,
                repository: repository
            ),
            referenceResolver: resolver,
            responseLanguageSelector: GraphChatResponseLanguageSelector(fallback: .german),
            referenceDate: { referenceDate },
            calendar: calendar,
            timeZone: timeZone
        )
        return ProjectSetup(
            fixture: fixture,
            graphScope: graphScope,
            chatScope: chatScope,
            provider: provider,
            orchestrator: orchestrator
        )
    }

    fileprivate static func answerScript(_ text: String) -> FakeGraphChatProviderScript {
        FakeGraphChatProviderScript(
            steps: [
                .event(
                    .completed(
                        GraphChatProviderTestSupport.makeFinalAnswer(
                            directAnswer: text
                        )
                    )
                )
            ]
        )
    }

    @MainActor
    fileprivate func verifyTypedCurrentQuery(
        modelEntityAlias: String,
        expectedAnswer: String
    ) async throws {
        let currentQuery = GraphChatModelQueryRequest(
            entityAlias: modelEntityAlias,
            conversationReferenceAlias: "CURRENT",
            filters: [],
            sortFieldAlias: nil,
            sortDirection: nil,
            projectionFieldAliases: [],
            aggregation: nil,
            aggregationFieldAlias: nil,
            limit: 20
        )
        let setup = try await makeProjectSetup(
            continuationScript: FakeGraphChatProviderScript(
                steps: [
                    .toolRequest(.queryDetailValues(currentQuery)),
                    .event(
                        .completed(
                            GraphChatProviderTestSupport.makeFinalAnswer(
                                directAnswer: expectedAnswer
                            )
                        )
                    ),
                ]
            )
        )

        _ = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Zeige alle Projektaufgaben nach Deadline.",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let events = await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: "Welche davon sind weiterhin offen?",
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
        let answer = try #require(completedAnswer(in: events))

        #expect(answer.state == .answer)
        #expect(answer.directAnswer == expectedAnswer)
        let providerSnapshot = await setup.provider.snapshot()
        #expect(providerSnapshot.streamedRequests.count == 2)

        let state = try #require(
            await setup.orchestrator.conversationStateSnapshot()
        )
        let plan = try #require(state.lastValidatedQueryPlan)
        #expect(plan.entityID == setup.fixture.entity.id)
        guard case .selection(let nodes) = plan.scope else {
            Issue.record("Expected the validated CURRENT selection scope.")
            return
        }
        #expect(
            Set(nodes)
                == Set(
                    setup.fixture.tasksByName.values.map {
                        NodeRefKey(kind: .attribute, id: $0.id)
                    }
                )
        )

        let visibleText = events.compactMap { event -> String? in
            switch event {
            case .partialAnswer(let text):
                return text
            case .completed(let completed):
                return completed.directAnswer
            case .started, .toolActivity, .cancelled, .failure:
                return nil
            }
        }.joined(separator: "\n")
        let forbiddenTokens = [
            "CURRENT",
            "E1",
            "E999",
            "N1",
            "CR_",
            setup.fixture.entity.id.uuidString,
        ]
        #expect(
            forbiddenTokens.allSatisfy {
                visibleText.contains($0) == false
            }
        )
        #expect(
            visibleText.range(
                of: #"\b(?:E|N)\d+\b"#,
                options: .regularExpression
            ) == nil
        )
        #expect(
            visibleText.range(
                of:
                    #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\b"#,
                options: .regularExpression
            ) == nil
        )
    }

    fileprivate func completedAnswer(
        in events: [GraphChatStreamEvent]
    ) -> GraphChatAnswer? {
        for event in events.reversed() {
            if case .completed(let answer) = event {
                return answer
            }
        }
        return nil
    }
}
