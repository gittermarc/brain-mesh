import Foundation
import Testing
@testable import BrainMesh

private actor GraphChatRepairObservabilityRecorder: GraphChatObservabilityRecording {
    private var events: [GraphChatObservabilityEvent] = []

    func record(_ event: GraphChatObservabilityEvent) {
        events.append(event)
    }

    func repairMetrics() -> [GraphChatToolRepairMetric] {
        events.compactMap { event in
            guard case .toolRepair(let metric) = event else {
                return nil
            }
            return metric
        }
    }
}

private nonisolated struct GraphChatSyntheticRepositoryError: Error, Sendable {}

private nonisolated struct GraphChatFailingQueryRepository: GraphChatQueryReading {
    func graphChatQuerySource(
        entityID: UUID,
        fieldIDs: Set<UUID>,
        in scope: GraphScope
    ) async throws -> GraphChatQuerySourceSnapshot? {
        throw GraphChatSyntheticRepositoryError()
    }
}

private actor GraphChatBlockingQueryRepository: GraphChatQueryReading {
    private var didStart = false

    func graphChatQuerySource(
        entityID: UUID,
        fieldIDs: Set<UUID>,
        in scope: GraphScope
    ) async throws -> GraphChatQuerySourceSnapshot? {
        didStart = true
        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func hasStarted() -> Bool {
        didStart
    }
}

@Suite("Bounded graph-chat tool repair")
struct GraphChatBoundedToolRepairTests {
    @MainActor
    @Test
    func wrongEntityAliasIsCorrectedByExactlyOneRepairAttempt() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E999",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Die offenen Aufgaben wurden nach der Korrektur gefunden."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        let events = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let snapshot = await setup.provider.snapshot()
        let firstRepair = try #require(
            snapshot.toolResponses.first?.repairResult
        )

        #expect(completedAnswer(in: events) != nil)
        #expect(snapshot.toolResponses.count == 2)
        #expect(firstRepair.reason == .unknownEntityAlias)
        #expect(firstRepair.argumentPath == "entityAlias")
        #expect(
            firstRepair.allowedCandidates.contains {
                $0.alias == setup.aliases.tasks
            }
        )
        #expect(snapshot.toolResponses[1].repairResult == nil)
        #expect(
            snapshot.toolResponses[0].modelContent.range(
                of:
                    #"\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[1-5][0-9A-Fa-f]{3}-[89ABab][0-9A-Fa-f]{3}-[0-9A-Fa-f]{12}\b"#,
                options: .regularExpression
            ) == nil
        )
        #expect(
            await repairOutcomes(setup)
                == [.offered, .succeeded]
        )
    }

    @MainActor
    @Test
    func entityRepairCandidatesStayInsideTheAuthorizedChatScope() async throws {
        let setup = try await makeSetup(
            chatScopeBuilder: { graphScope, aliases in
                .entity(aliases.peopleID, in: graphScope)
            }
        ) { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E999",
                                    fieldAlias: aliases.role,
                                    operation: .contains,
                                    value: "Owner"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.people,
                                    fieldAlias: aliases.role,
                                    operation: .contains,
                                    value: "Owner"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Die passende Person wurde innerhalb des freigegebenen Bereichs gefunden."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        _ = await run(
            setup,
            question: "Welche Person hat die Rolle Owner?"
        )
        let snapshot = await setup.provider.snapshot()
        let repair = try #require(
            snapshot.toolResponses.first?.repairResult
        )

        #expect(repair.allowedCandidates.map(\.alias) == [setup.aliases.people])
        #expect(
            repair.allowedCandidates.contains {
                $0.alias == setup.aliases.tasks
            } == false
        )
    }

    @MainActor
    @Test
    func fieldEntityMismatchOffersOnlyFieldsFromTheSelectedEntity() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.role,
                                    operation: .contains,
                                    value: "Owner"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Die Aufgabenabfrage wurde mit dem passenden Feld korrigiert."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        _ = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let snapshot = await setup.provider.snapshot()
        let response = try #require(
            snapshot.toolResponses.first
        )
        let repair = try #require(response.repairResult)

        #expect(repair.reason == .fieldEntityMismatch)
        #expect(repair.argumentPath == "filters[0].fieldAlias")
        #expect(repair.allowedCandidates.isEmpty == false)
        #expect(
            repair.allowedCandidates.allSatisfy {
                $0.alias != setup.aliases.role
            }
        )
        #expect(
            repair.allowedCandidates.contains {
                $0.alias == setup.aliases.status
            }
        )
    }

    @MainActor
    @Test
    func invalidOperatorExposesOnlyTypeCompatibleOperators() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.deadline,
                                    operation: .contains,
                                    value: "2026"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.deadline,
                                    operation: .isOverdue
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Die überfälligen Aufgaben wurden sicher abgefragt."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        _ = await run(
            setup,
            question: "Welche Aufgaben sind überfällig?"
        )
        let snapshot = await setup.provider.snapshot()
        let repair = try #require(
            snapshot.toolResponses.first?.repairResult
        )

        #expect(repair.reason == .invalidOperator)
        #expect(repair.expectedDataType == "date")
        #expect(repair.allowedOperators.contains(.before))
        #expect(repair.allowedOperators.contains(.isOverdue))
        #expect(repair.allowedOperators.contains(.contains) == false)
        #expect(repair.allowedOperators.contains(.equals) == false)
    }

    @MainActor
    @Test
    func uniquelySimilarSchemaNameCanBeRepaired() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "Aufgabne",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Die ähnlich geschriebene Entity wurde eindeutig korrigiert."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        _ = await run(
            setup,
            question: "Zeige offene Aufgabne."
        )
        let snapshot = await setup.provider.snapshot()
        let repair = try #require(
            snapshot.toolResponses.first?.repairResult
        )

        #expect(repair.reason == .similarName)
        #expect(repair.allowedCandidates.count == 1)
        #expect(repair.allowedCandidates[0].alias == setup.aliases.tasks)
    }

    @Test
    func severalSimilarCandidatesAreReturnedWithoutAutomaticSelection() throws {
        let base = GraphChatTestSupport.makeSchemaContext()
        let firstAlias = GraphFieldAlias("F9")
        let secondAlias = GraphFieldAlias("F10")
        let existingStatusAlias = try #require(
            base.fieldAlias(
                named: "Status",
                in: GraphEntityAlias("E1")
            )
        )
        var fields = base.aliases.fieldsByAlias
        fields[firstAlias] = GraphSchemaFieldResolution(
            alias: firstAlias,
            entityAlias: GraphEntityAlias("E1"),
            entityID: GraphChatTestSupport.projectEntityID,
            fieldID: UUID(),
            name: "Status",
            type: .singleChoice,
            unit: nil,
            choiceOptions: ["Offen", "Fertig"]
        )
        fields[secondAlias] = GraphSchemaFieldResolution(
            alias: secondAlias,
            entityAlias: GraphEntityAlias("E1"),
            entityID: GraphChatTestSupport.projectEntityID,
            fieldID: UUID(),
            name: "Statis",
            type: .singleChoice,
            unit: nil,
            choiceOptions: ["Offen", "Fertig"]
        )
        let context = GraphSchemaContext(
            graphScope: base.graphScope,
            snapshot: base.snapshot,
            aliases: GraphSchemaAliasMap(
                graphScope: base.graphScope,
                entitiesByAlias: base.aliases.entitiesByAlias,
                fieldsByAlias: fields,
                nodeEntityIDs: base.aliases.nodeEntityIDs
            )
        )
        let entity = try #require(
            context.aliases.entity(for: GraphEntityAlias("E1"))
        )

        let repair = GraphChatToolRepairHintBuilder(
            schemaContext: context,
            scope: .entireGraph(context.graphScope)
        ).fieldIssue(
            rawValue: "Statas",
            path: "filters[0].fieldAlias",
            expectedCategory: .fieldAlias,
            entity: entity,
            reason: .schemaIncompatibility,
            current: nil
        )

        #expect(repair.reason == .similarName)
        #expect(
            Set(repair.allowedCandidates.map(\.alias))
                == Set(
                    [
                        existingStatusAlias.rawValue,
                        firstAlias.rawValue,
                        secondAlias.rawValue,
                    ]
                )
        )
    }

    @MainActor
    @Test
    func successfulFirstToolCallDoesNotOfferRepair() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Der erste Tool-Aufruf war bereits gültig."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        _ = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let snapshot = await setup.provider.snapshot()

        #expect(snapshot.toolResponses.count == 1)
        #expect(snapshot.toolResponses[0].repairResult == nil)
        #expect((await repairOutcomes(setup)).isEmpty)
    }

    @MainActor
    @Test
    func failedRepairDoesNotOfferASecondRepair() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E999",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E998",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Bitte wähle die gewünschte fachliche Kategorie genauer aus."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        let events = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let responses = await setup.provider.snapshot().toolResponses

        #expect(completedAnswer(in: events) != nil)
        #expect(responses.count == 2)
        #expect(responses[0].repairResult != nil)
        #expect(responses[1].repairResult == nil)
        #expect(responses[1].content.contains("repairFailed"))
        #expect(
            await repairOutcomes(setup)
                == [.offered, .failed]
        )
    }

    @MainActor
    @Test
    func furtherInvalidCallReportsExhaustedBudgetWithoutAnotherRepair() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E999",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E998",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E997",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Bitte präzisiere die gewünschte Kategorie."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        _ = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let responses = await setup.provider.snapshot().toolResponses

        #expect(responses.count == 3)
        #expect(responses[0].repairResult != nil)
        #expect(responses[1].content.contains("repairFailed"))
        #expect(responses[2].content.contains("repairBudgetExhausted"))
        #expect(
            await repairOutcomes(setup)
                == [.offered, .failed, .budgetExhausted]
        )
    }

    @MainActor
    @Test
    func contextRetryCarriesOnePendingRepairWithoutResettingItsBudget() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E999",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .failure(
                            GraphChatProviderError(
                                code: .contextWindowExceeded,
                                message: "Synthetic context pressure"
                            )
                        ),
                    ]
                ),
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Der Context-Retry hat denselben Repair weitergeführt."
                                )
                            )
                        ),
                    ]
                ),
            ]
        }

        let events = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let snapshot = await setup.provider.snapshot()

        #expect(completedAnswer(in: events) != nil)
        #expect(snapshot.createdSessions.count == 2)
        #expect(snapshot.streamedRequests.count == 2)
        #expect(snapshot.streamedRequests[0].toolRepairContext == nil)
        #expect(snapshot.streamedRequests[1].toolRepairContext != nil)
        #expect(snapshot.toolResponses.count == 2)
        #expect(
            snapshot.toolResponses.filter {
                $0.repairResult != nil
            }.count == 1
        )
        let metrics = await setup.observability.repairMetrics()
        #expect(metrics.map(\.outcome) == [.offered, .succeeded])
        #expect(metrics.last?.contextRetryCount == 1)
    }

    @MainActor
    @Test
    func graphScopeViolationIsNeverRepairable() async throws {
        let setup = try await makeSetup(
            chatScopeBuilder: { graphScope, aliases in
                .entity(aliases.peopleID, in: graphScope)
            }
        ) { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        )
                    ]
                )
            ]
        }

        let events = await run(
            setup,
            question: "Zeige Aufgaben außerhalb des aktuellen Scopes."
        )
        let snapshot = await setup.provider.snapshot()
        let metrics = await setup.observability.repairMetrics()
        let error = try #require(failure(in: events))

        #expect(snapshot.toolResponses.isEmpty)
        #expect(error.message.contains(setup.aliases.tasks) == false)
        #expect(error.message.contains("Scope") == false)
        #expect(await repairOutcomes(setup) == [.notAllowed])
        #expect(
            metrics.last?.nonRepairableReason
                == .unauthorizedNodeOrSelectionScope
        )
    }

    @MainActor
    @Test
    func repositoryFailureIsNeverRepairable() async throws {
        let setup = try await makeSetup(
            queryRepository: GraphChatFailingQueryRepository()
        ) { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        )
                    ]
                )
            ]
        }

        let events = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let metrics = await setup.observability.repairMetrics()
        let error = try #require(failure(in: events))

        let providerSnapshot = await setup.provider.snapshot()
        #expect(providerSnapshot.toolResponses.isEmpty)
        #expect(error.message.contains("GraphChatSyntheticRepositoryError") == false)
        #expect(await repairOutcomes(setup) == [.notAllowed])
        #expect(
            metrics.last?.nonRepairableReason
                == .repositoryOrStorageFailure
        )
    }

    @MainActor
    @Test
    func technicalIdentifierInAliasPositionIsNeverRepairable() async throws {
        let technicalID = UUID().uuidString
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: technicalID,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        )
                    ]
                )
            ]
        }

        let events = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let error = try #require(failure(in: events))
        let metrics = await setup.observability.repairMetrics()
        let snapshot = await setup.provider.snapshot()

        #expect(snapshot.toolResponses.isEmpty)
        #expect(error.message.contains(technicalID) == false)
        #expect(await repairOutcomes(setup) == [.notAllowed])
        #expect(
            metrics.last?.nonRepairableReason
                == .manipulatedTechnicalIdentifier
        )
    }

    @MainActor
    @Test
    func cancellationDuringRepairTargetsTheActiveProviderSession() async throws {
        let repository = GraphChatBlockingQueryRepository()
        let setup = try await makeSetup(
            queryRepository: repository
        ) { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E999",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                    ]
                )
            ]
        }
        let eventTask = Task {
            await run(
                setup,
                question: "Welche Aufgaben sind offen?"
            )
        }
        await GraphChatProviderTestSupport.waitUntil {
            await repository.hasStarted()
        }

        await setup.orchestrator.cancelCurrentGeneration()
        let events = await eventTask.value
        let snapshot = await setup.provider.snapshot()
        let activeSession = try #require(snapshot.streamedSessions.last)

        #expect(events.contains(.cancelled))
        #expect(snapshot.cancelledSessions.contains(activeSession))
        #expect(
            await repairOutcomes(setup)
                == [.offered, .failed]
        )
    }

    @MainActor
    @Test
    func terminalEventIsCommittedExactlyOnceAfterRepair() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E999",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: aliases.tasks,
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Die Reparatur wurde einmal abgeschlossen."
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        let events = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )

        #expect(
            events.filter {
                if case .completed = $0 {
                    return true
                }
                return false
            }.count == 1
        )
        #expect(
            events.filter {
                if case .failure = $0 {
                    return true
                }
                return false
            }.isEmpty
        )
        #expect(events.filter { $0 == .cancelled }.isEmpty)
    }

    @MainActor
    @Test
    func rawRepairAndResolverDetailsNeverReachVisibleText() async throws {
        let setup = try await makeSetup { aliases in
            [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E999",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .toolRequest(
                            .queryDetailValues(
                                query(
                                    entityAlias: "E998",
                                    fieldAlias: aliases.status,
                                    operation: .equals,
                                    value: "Offen"
                                )
                            )
                        ),
                        .event(
                            .completed(
                                safeFinalAnswer(
                                    "Raw resolver error: E999 at filters[0].fieldAlias"
                                )
                            )
                        ),
                    ]
                )
            ]
        }

        let events = await run(
            setup,
            question: "Welche Aufgaben sind offen?"
        )
        let visible = completedAnswer(in: events)?.directAnswer ?? ""

        #expect(visible.contains("E999") == false)
        #expect(visible.contains("filters[0]") == false)
        #expect(visible.contains("resolver error") == false)
    }
}

private extension GraphChatBoundedToolRepairTests {
    struct Aliases: Sendable {
        let tasks: String
        let people: String
        let status: String
        let deadline: String
        let role: String
        let peopleID: UUID
    }

    @MainActor
    struct Setup {
        let provider: FakeGraphChatModelProvider
        let orchestrator: GraphChatOrchestrator
        let graphScope: GraphScope
        let chatScope: GraphChatScope
        let aliases: Aliases
        let observability: GraphChatRepairObservabilityRecorder
    }

    @MainActor
    func makeSetup(
        queryRepository: (any GraphChatQueryReading)? = nil,
        chatScopeBuilder: (
            (GraphScope, Aliases) -> GraphChatScope
        )? = nil,
        scripts: (Aliases) -> [FakeGraphChatProviderScript]
    ) async throws -> Setup {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Repair-Test")
        let tasks = fixtures.makeEntity(name: "Aufgaben", in: graph)
        let status = fixtures.makeDetailField(
            owner: tasks,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Offen", "Fertig"],
            isPinned: true
        )
        let deadline = fixtures.makeDetailField(
            owner: tasks,
            name: "Deadline",
            type: .date,
            sortIndex: 1,
            isPinned: true
        )
        let task = fixtures.makeAttribute(
            name: "Release vorbereiten",
            owner: tasks
        )
        fixtures.makeDetailValue(
            attribute: task,
            field: status,
            stringValue: "Offen"
        )
        fixtures.makeDetailValue(
            attribute: task,
            field: deadline,
            dateValue: Date(timeIntervalSince1970: 1_735_646_400)
        )

        let people = fixtures.makeEntity(name: "Personen", in: graph)
        let role = fixtures.makeDetailField(
            owner: people,
            name: "Rolle",
            type: .singleLineText,
            sortIndex: 0,
            isPinned: true
        )
        let person = fixtures.makeAttribute(
            name: "Ada",
            owner: people
        )
        fixtures.makeDetailValue(
            attribute: person,
            field: role,
            stringValue: "Owner"
        )
        try fixtures.save()

        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let evidenceValidator = GraphEvidenceSourceValidator(
            repository: repository
        )
        let schemaService = GraphSchemaService(repository: repository)
        let graphScope = GraphScope(graphID: graph.id)
        let schema = try await schemaService.makeSnapshot(in: graphScope)
        let tasksAlias = try #require(
            schema.entityAlias(named: "Aufgaben")
        )
        let peopleAlias = try #require(
            schema.entityAlias(named: "Personen")
        )
        let statusAlias = try #require(
            schema.fieldAlias(named: "Status", in: tasksAlias)
        )
        let deadlineAlias = try #require(
            schema.fieldAlias(named: "Deadline", in: tasksAlias)
        )
        let roleAlias = try #require(
            schema.fieldAlias(named: "Rolle", in: peopleAlias)
        )
        let aliases = Aliases(
            tasks: tasksAlias.rawValue,
            people: peopleAlias.rawValue,
            status: statusAlias.rawValue,
            deadline: deadlineAlias.rawValue,
            role: roleAlias.rawValue,
            peopleID: people.id
        )
        let provider = FakeGraphChatModelProvider(
            scripts: scripts(aliases)
        )
        let observability = GraphChatRepairObservabilityRecorder()
        let querySource: any GraphChatQueryReading
        if let queryRepository {
            querySource = queryRepository
        } else {
            querySource = repository
        }
        let queryEngine = GraphChatQueryEngine(
            repository: querySource,
            evidenceValidator: evidenceValidator
        )
        let logger = NoOpGraphChatToolLogger()
        let runtimeFactory = GraphChatModelToolRuntimeFactory(
            describeSchemaTool: DescribeGraphSchemaTool(
                schemaService: schemaService,
                evidenceValidator: evidenceValidator,
                logger: logger
            ),
            searchGraphTool: SearchGraphTool(logger: logger),
            queryDetailValuesTool: QueryDetailValuesTool(
                queryEngine: queryEngine,
                logger: logger
            ),
            getNodeTool: GetNodeTool(
                repository: repository,
                evidenceValidator: evidenceValidator,
                logger: logger
            ),
            getNeighborsTool: GetNeighborsTool(
                repository: NodeRepository(
                    container: AnyModelContainer(store.container)
                ),
                evidenceValidator: evidenceValidator,
                logger: logger
            ),
            graphStatsTool: GraphStatsTool(
                reader: GraphStatsServiceReader(
                    container: AnyModelContainer(store.container)
                ),
                evidenceValidator: evidenceValidator,
                logger: logger
            )
        )
        let chatScope = chatScopeBuilder?(graphScope, aliases)
            ?? .entireGraph(graphScope)
        let resolver = GraphChatConversationReferenceResolver(
            revalidator: GraphChatRepositoryConversationReferenceRevalidator(
                repository: repository
            )
        )
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            schemaProvider: schemaService,
            toolRunnerFactory: runtimeFactory,
            referenceResolver: resolver,
            responseLanguageSelector: GraphChatResponseLanguageSelector(
                fallback: .german
            ),
            evidenceValidator: evidenceValidator,
            observability: observability,
            referenceDate: {
                Date(timeIntervalSince1970: 1_735_732_800)
            },
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "Europe/Berlin")!
        )
        return Setup(
            provider: provider,
            orchestrator: orchestrator,
            graphScope: graphScope,
            chatScope: chatScope,
            aliases: aliases,
            observability: observability
        )
    }

    func query(
        entityAlias: String,
        conversationReferenceAlias: String? = nil,
        fieldAlias: String,
        operation: GraphQueryFilterOperator,
        value: String? = nil
    ) -> GraphChatModelQueryRequest {
        GraphChatModelQueryRequest(
            entityAlias: entityAlias,
            conversationReferenceAlias: conversationReferenceAlias,
            filters: [
                GraphChatModelQueryFilterRequest(
                    fieldAlias: fieldAlias,
                    operation: operation.rawValue,
                    value: value,
                    secondValue: nil,
                    values: []
                )
            ],
            sortFieldAlias: nil,
            sortDirection: nil,
            projectionFieldAliases: [fieldAlias],
            aggregation: nil,
            aggregationFieldAlias: nil,
            limit: 20
        )
    }

    func safeFinalAnswer(
        _ directAnswer: String
    ) -> GraphChatProviderFinalAnswer {
        GraphChatProviderTestSupport.makeFinalAnswer(
            directAnswer: directAnswer,
            hasInsufficientEvidence: true
        )
    }

    @MainActor
    func run(
        _ setup: Setup,
        question: String
    ) async -> [GraphChatStreamEvent] {
        await GraphChatProviderTestSupport.collect(
            await setup.orchestrator.streamAnswer(
                question: question,
                graphScope: setup.graphScope,
                chatScope: setup.chatScope
            )
        )
    }

    func completedAnswer(
        in events: [GraphChatStreamEvent]
    ) -> GraphChatAnswer? {
        events.compactMap { event -> GraphChatAnswer? in
            guard case .completed(let answer) = event else {
                return nil
            }
            return answer
        }.last
    }

    func failure(
        in events: [GraphChatStreamEvent]
    ) -> GraphChatError? {
        events.compactMap { event -> GraphChatError? in
            guard case .failure(let error) = event else {
                return nil
            }
            return error
        }.last
    }

    @MainActor
    func repairOutcomes(
        _ setup: Setup
    ) async -> [GraphChatToolRepairOutcome] {
        await setup.observability.repairMetrics().map(\.outcome)
    }
}
