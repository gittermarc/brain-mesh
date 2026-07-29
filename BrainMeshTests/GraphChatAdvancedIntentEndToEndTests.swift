import Foundation
import SwiftData
import Testing

@testable import BrainMesh

@Suite("Graph chat advanced semantic intent end-to-end")
struct GraphChatAdvancedIntentEndToEndTests {
    @MainActor
    @Test
    func uniqueNodeNameProducesLocalDetailsWithAppOwnedLimit()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Portfolio")
        let projects = fixtures.makeEntity(name: "Projekte", in: graph)
        let atlas = fixtures.makeAttribute(
            name: "Projekt Atlas",
            owner: projects,
            notes: "Interne Notiz"
        )
        let status = fixtures.makeDetailField(
            owner: projects,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Aktiv", "Pausiert"],
            isPinned: true
        )
        let budget = fixtures.makeDetailField(
            owner: projects,
            name: "Budget",
            type: .numberDouble,
            sortIndex: 1,
            unit: "EUR"
        )
        fixtures.makeDetailValue(
            attribute: atlas,
            field: status,
            stringValue: "Aktiv"
        )
        fixtures.makeDetailValue(
            attribute: atlas,
            field: budget,
            doubleValue: 125_000
        )
        fixtures.makeAttachment(
            owner: .attribute(atlas),
            title: "Atlas-Dossier",
            originalFilename: "atlas.pdf",
            contentTypeIdentifier: "com.adobe.pdf",
            fileExtension: "pdf",
            fileData: Data("ATTACHMENT-CONTENT-MUST-STAY-UNREAD".utf8)
        )
        try fixtures.save()

        let interpreter = FakeGraphChatIntentInterpreter(
            steps: [
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .nodeDetails,
                        nodeTerms: ["Projekt Atlas"],
                        responseLanguage: .german
                    )
                ),
            ]
        )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let events = await collect(
            await runtime.orchestrator.streamAnswer(
                question: "Ich möchte mir Projekt Atlas genauer ansehen.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let answer = try completedAnswer(events)
        let artifacts = await resolvedArtifacts(
            answer: answer,
            runtime: runtime,
            graphScope: graphScope,
            chatScope: chatScope
        )
        let artifact = try #require(artifacts.first)
        guard case .table(let payload) = artifact.payload else {
            Issue.record("Expected a deterministic node-detail table.")
            return
        }
        let inputs = await runtime.nodeExecutor.inputs()
        let state = try #require(
            await runtime.orchestrator.conversationStateSnapshot()
        )

        #expect(inputs.count == 1)
        #expect(
            inputs[0].node
                == NodeRefKey(kind: .attribute, id: atlas.id)
        )
        #expect(
            inputs[0].relatedLimit
                == GraphChatAdvancedIntentPolicy.default
                    .nodeDetailRelatedLimit
        )
        #expect(inputs[0].includeNotes)
        #expect(payload.rows.count == 2)
        #expect(
            payload.rows
                .flatMap(\.cells)
                .contains {
                    if case .text("Status") = $0.value {
                        return true
                    }
                    return false
                }
        )
        #expect(
            answer.evidence
                .flatMap(\.fieldValues)
                .contains {
                    if case .text(
                        "ATTACHMENT-CONTENT-MUST-STAY-UNREAD"
                    ) = $0.value {
                        return true
                    }
                    return false
                } == false
        )
        #expect(
            state.resultContexts.last?.kind == .node
        )
        #expect(
            state.referenceTargets.singular
                == .node(
                    NodeRefKey(
                        kind: .attribute,
                        id: atlas.id
                    )
                )
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(
            await runtime.observability.semanticEvents()
                .contains(.nodeDetailsCompiled)
        )
        #expect(terminalEventCount(events) == 1)
        #expect(
            visibleText(events)
                .contains(atlas.id.uuidString) == false
        )
    }

    @MainActor
    @Test
    func duplicateNodeNameClarifiesThenRevalidatesLastNode()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Portfolio")
        let active = fixtures.makeEntity(name: "Aktive Projekte", in: graph)
        let archive = fixtures.makeEntity(name: "Archivprojekte", in: graph)
        let first = fixtures.makeAttribute(
            name: "Atlas",
            owner: active
        )
        fixtures.makeAttribute(
            name: "Atlas",
            owner: archive
        )
        try fixtures.save()

        let interpreter = FakeGraphChatIntentInterpreter(
            steps: [
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .nodeDetails,
                        nodeTerms: ["Atlas"],
                        responseLanguage: .german
                    )
                ),
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .nodeDetails,
                        responseLanguage: .german
                    )
                ),
            ]
        )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        let clarificationEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question: "Welcher Eintrag steckt hinter Atlas?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let clarificationAnswer = try completedAnswer(
            clarificationEvents
        )
        guard case .clarification(let clarification) =
                clarificationAnswer.state
        else {
            Issue.record("Expected duplicate-name clarification.")
            return
        }
        #expect(clarification.options.count == 2)
        #expect(await runtime.nodeExecutor.inputs().isEmpty)

        let selectedEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question: "1",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        _ = try completedAnswer(selectedEvents)
        let selectedInput = try #require(
            await runtime.nodeExecutor.inputs().first
        )
        #expect(
            selectedInput.node
                == NodeRefKey(
                    kind: .attribute,
                    id: first.id
                )
        )

        let lastNodeEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question: "Was weißt du über den letzten Node?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        _ = try completedAnswer(lastNodeEvents)
        let nodeInputs = await runtime.nodeExecutor.inputs()

        #expect(nodeInputs.count == 2)
        #expect(nodeInputs[1].node == selectedInput.node)
        #expect(
            await interpreter.snapshot()
                .requests.count == 2
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(clarificationEvents) == 1)
        #expect(terminalEventCount(selectedEvents) == 1)
        #expect(terminalEventCount(lastNodeEvents) == 1)
    }

    @MainActor
    @Test
    func lastNodeFromAnotherGraphIsNotReused()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let firstGraph = fixtures.makeGraph(name: "Portfolio")
        let projects = fixtures.makeEntity(
            name: "Projekte",
            in: firstGraph
        )
        let atlas = fixtures.makeAttribute(
            name: "Atlas",
            owner: projects
        )
        let secondGraph = fixtures.makeGraph(name: "Archiv")
        fixtures.makeEntity(name: "Archiv", in: secondGraph)
        try fixtures.save()

        let interpreter = FakeGraphChatIntentInterpreter(
            steps: [
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .nodeDetails,
                        nodeTerms: ["Atlas"],
                        responseLanguage: .german
                    )
                ),
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .nodeDetails,
                        responseLanguage: .german
                    )
                ),
            ]
        )
        let runtime = makeRuntime(
            store: store,
            graphID: firstGraph.id,
            interpreter: interpreter
        )
        let firstScope = GraphScope(graphID: firstGraph.id)
        let firstEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question: "Zeige mir Atlas genauer.",
                graphScope: firstScope,
                chatScope:
                    GraphChatScope.entireGraph(
                        firstScope
                    )
            )
        )
        _ = try completedAnswer(firstEvents)
        #expect(
            await runtime.nodeExecutor.inputs()
                .map(\.node)
                == [
                    NodeRefKey(
                        kind: .attribute,
                        id: atlas.id
                    ),
                ]
        )

        let secondScope = GraphScope(graphID: secondGraph.id)
        let secondEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question: "Zeige mir den letzten Node.",
                graphScope: secondScope,
                chatScope:
                    GraphChatScope.entireGraph(
                        secondScope
                    )
            )
        )

        #expect(
            await runtime.nodeExecutor.inputs().count == 1
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(firstEvents) == 1)
        #expect(terminalEventCount(secondEvents) == 1)
    }

    @MainActor
    @Test
    func sameEntityComparisonUsesRequestedAndStableDefaultFields()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Portfolio")
        let projects = fixtures.makeEntity(name: "Projekte", in: graph)
        let atlas = fixtures.makeAttribute(name: "Atlas", owner: projects)
        let apollo = fixtures.makeAttribute(name: "Apollo", owner: projects)
        let priority = fixtures.makeDetailField(
            owner: projects,
            name: "Priorität",
            type: .numberInt,
            sortIndex: 0,
            isPinned: true
        )
        let status = fixtures.makeDetailField(
            owner: projects,
            name: "Status",
            type: .singleChoice,
            sortIndex: 2,
            options: ["Aktiv", "Pausiert"],
            isPinned: true
        )
        let sponsor = fixtures.makeDetailField(
            owner: projects,
            name: "Sponsor",
            type: .singleLineText,
            sortIndex: 0
        )
        let budget = fixtures.makeDetailField(
            owner: projects,
            name: "Budget",
            type: .numberDouble,
            sortIndex: 1,
            unit: "EUR"
        )
        for (node, priorityValue, statusValue, budgetValue) in [
            (atlas, 1, "Aktiv", 125_000.0),
            (apollo, 2, "Pausiert", 98_000.0),
        ] {
            fixtures.makeDetailValue(
                attribute: node,
                field: priority,
                intValue: priorityValue
            )
            fixtures.makeDetailValue(
                attribute: node,
                field: status,
                stringValue: statusValue
            )
            fixtures.makeDetailValue(
                attribute: node,
                field: budget,
                doubleValue: budgetValue
            )
        }
        fixtures.makeDetailValue(
            attribute: atlas,
            field: sponsor,
            stringValue: "Team Nord"
        )
        try fixtures.save()

        let interpreter = FakeGraphChatIntentInterpreter(
            steps: [
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .compareNodes,
                        entityTerm: "Projekte",
                        nodeTerms: ["Atlas", "Apollo"],
                        projectionTerms: ["Budget", "Status"],
                        responseLanguage: .german
                    )
                ),
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .compareNodes,
                        entityTerm: "Projekte",
                        nodeTerms: ["Atlas", "Apollo"],
                        responseLanguage: .german
                    )
                ),
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .nodeDetails,
                        responseLanguage: .german
                    )
                ),
            ]
        )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        let explicitEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question:
                    "Stelle Atlas und Apollo nach Budget und Status gegenüber.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let explicitAnswer = try completedAnswer(explicitEvents)
        let explicitArtifact = try #require(
            await resolvedArtifacts(
                answer: explicitAnswer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            ).first
        )
        guard case .comparison(let explicit) =
                explicitArtifact.payload
        else {
            Issue.record("Expected a same-entity comparison artifact.")
            return
        }
        #expect(
            explicit.features.map(\.label)
                == ["Budget", "Status"]
        )
        #expect(explicit.subjects.map(\.label) == ["Atlas", "Apollo"])
        #expect(explicit.values.count == 4)
        #expect(
            explicit.values.allSatisfy {
                $0.evidence?.evidenceIDs.isEmpty
                    == false
            }
        )
        #expect(
            explicitArtifact.navigationTargets
                .allSatisfy {
                    $0.graphScope == graphScope
                }
        )
        let explicitState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let explicitQuery = try #require(
            explicitState.lastValidatedQueryPlan
        )
        let expectedSelection = try GraphChatScope
            .selection(
                [
                    NodeRefKey(
                        kind: .attribute,
                        id: atlas.id
                    ),
                    NodeRefKey(
                        kind: .attribute,
                        id: apollo.id
                    ),
                ],
                in: graphScope
            ).nodeReferences
        #expect(
            explicitQuery.scope
                == .selection(
                    expectedSelection
                )
        )
        #expect(explicitQuery.filters.isEmpty)
        #expect(explicitQuery.aggregation == nil)
        #expect(
            explicitQuery.projection
                == [
                    .nodeIdentity,
                    .field(budget.id),
                    .field(status.id),
                ]
        )

        let defaultEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question:
                    "Vergleiche Atlas und Apollo noch einmal vollständig.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let defaultAnswer = try completedAnswer(defaultEvents)
        let defaultArtifact = try #require(
            await resolvedArtifacts(
                answer: defaultAnswer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            ).first
        )
        guard case .comparison(let defaults) =
                defaultArtifact.payload
        else {
            Issue.record("Expected the default-field comparison artifact.")
            return
        }
        #expect(
            defaults.features.map(\.label)
                == [
                    "Priorität",
                    "Status",
                    "Sponsor",
                    "Budget",
                ]
        )
        let sponsorFeature = try #require(
            defaults.features.first {
                $0.label == "Sponsor"
            }
        )
        let apolloSubject = try #require(
            defaults.subjects.first {
                $0.label == "Apollo"
            }
        )
        let missingSponsor = try #require(
            defaults.values.first {
                $0.subjectID == apolloSubject.id
                    && $0.featureID == sponsorFeature.id
            }
        )
        #expect(missingSponsor.value == .missing)
        #expect(
            missingSponsor.evidence?
                .evidenceIDs.isEmpty == false
        )

        let stateAfterComparison = try #require(
            await runtime.orchestrator.conversationStateSnapshot()
        )
        #expect(stateAfterComparison.lastComparison?.references.count == 2)
        #expect(
            stateAfterComparison.resultContexts.last?.kind
                == .comparison
        )
        #expect(
            stateAfterComparison.referenceTargets.plural.count == 2
        )

        let ordinalEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question: "Was weißt du über den zweiten Eintrag?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        _ = try completedAnswer(ordinalEvents)
        let nodeInput = try #require(
            await runtime.nodeExecutor.inputs().last
        )
        #expect(
            nodeInput.node
                == NodeRefKey(
                    kind: .attribute,
                    id: apollo.id
                )
        )
        #expect(
            await runtime.observability.semanticEvents()
                .filter {
                    $0 == .sameEntityComparisonCompiled
                }.count == 2
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(explicitEvents) == 1)
        #expect(terminalEventCount(defaultEvents) == 1)
        #expect(terminalEventCount(ordinalEvents) == 1)
    }

    @MainActor
    @Test
    func mixedKindsUseOnlyEvidenceBackedStructuralFeatures()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Portfolio")
        let projects = fixtures.makeEntity(
            name: "Projekte",
            in: graph,
            notes: "ENTITY-NOTE-MUST-NOT-BE-ANALYZED"
        )
        let atlas = fixtures.makeAttribute(
            name: "Atlas",
            owner: projects,
            notes: "ATTRIBUTE-NOTE-MUST-NOT-BE-ANALYZED"
        )
        let status = fixtures.makeDetailField(
            owner: projects,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Aktiv"]
        )
        fixtures.makeDetailValue(
            attribute: atlas,
            field: status,
            stringValue: "Aktiv"
        )
        fixtures.makeLink(
            source: .entity(projects),
            target: .attribute(atlas),
            note: "LINK-NOTE-MUST-NOT-BE-ANALYZED"
        )
        try fixtures.save()

        let interpreter = FakeGraphChatIntentInterpreter(
            steps: [
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .compareNodes,
                        nodeTerms: ["Projekte", "Atlas"],
                        responseLanguage: .german
                    )
                ),
            ]
        )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter
        )
        let graphScope = GraphScope(graphID: graph.id)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let events = await collect(
            await runtime.orchestrator.streamAnswer(
                question:
                    "Worin unterscheiden sich Projekte und Atlas strukturell?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let answer = try completedAnswer(events)
        let artifact = try #require(
            await resolvedArtifacts(
                answer: answer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            ).first
        )
        guard case .comparison(let payload) = artifact.payload else {
            Issue.record("Expected a structural comparison artifact.")
            return
        }
        let inputs = await runtime.nodeExecutor.inputs()
        let labels = payload.features.map(\.label)

        #expect(inputs.count == 2)
        #expect(inputs.allSatisfy { $0.relatedLimit == 0 })
        #expect(inputs.allSatisfy { $0.includeNotes == false })
        #expect(
            labels == [
                "Node-Art",
                "Owner",
                "Direkte Verbindungen",
                "Attachment-Metadaten",
                "Notizen vorhanden",
                "Autoritative Detailwerte",
            ]
        )
        #expect(labels.contains("Status") == false)
        #expect(payload.values.count == 12)
        #expect(
            payload.values.allSatisfy {
                $0.evidence?.evidenceIDs.isEmpty
                    == false
            }
        )
        #expect(
            answer.directAnswer
                .contains("MUST-NOT-BE-ANALYZED")
                == false
        )
        #expect(
            await runtime.observability.semanticEvents()
                .contains(.structuralComparisonCompiled)
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func graphHealthRequiresExactEntireGraphScope()
        async throws
    {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(context: store.context)
        let graph = fixtures.makeGraph(name: "Wissensnetz")
        let first = fixtures.makeEntity(name: "Erster Bereich", in: graph)
        fixtures.makeEntity(name: "Isolierter Bereich", in: graph)
        try fixtures.save()

        let interpreter = FakeGraphChatIntentInterpreter(
            steps: [
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .inspectGraphState,
                        graphStateAspect: .health,
                        responseLanguage: .german
                    )
                ),
                .draft(
                    GraphChatUntrustedSemanticIntentDraft(
                        family: .inspectGraphState,
                        graphStateAspect: .health,
                        responseLanguage: .german
                    )
                ),
            ]
        )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter
        )
        let graphScope = GraphScope(graphID: graph.id)
        let entityScope = GraphChatScope.entity(
            first.id,
            in: graphScope
        )
        let blockedEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question:
                    "Gib mir eine Einschätzung zur Gesundheit des ganzen Netzes.",
                graphScope: graphScope,
                chatScope: entityScope
            )
        )
        #expect(
            blockedEvents.contains {
                if case .failure = $0 {
                    return true
                }
                return false
            }
        )
        #expect(await runtime.statsExecutor.inputs().isEmpty)
        #expect(
            await runtime.observability.semanticEvents()
                .contains(.scopeExpansionPrevented)
        )

        let chatScope = GraphChatScope.entireGraph(graphScope)
        let healthEvents = await collect(
            await runtime.orchestrator.streamAnswer(
                question:
                    "Wie gesund ist mein Wissensnetz insgesamt?",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let answer = try completedAnswer(healthEvents)
        let artifacts = await resolvedArtifacts(
            answer: answer,
            runtime: runtime,
            graphScope: graphScope,
            chatScope: chatScope
        )
        let statsInputs = await runtime.statsExecutor.inputs()
        let state = try #require(
            await runtime.orchestrator.conversationStateSnapshot()
        )

        #expect(statsInputs.count == 1)
        #expect(
            statsInputs[0].hubLimit
                == GraphChatAdvancedIntentPolicy.default
                    .graphHubLimit
        )
        #expect(
            artifacts.contains {
                if case .metric = $0.payload {
                    return true
                }
                return false
            }
        )
        #expect(
            artifacts.contains {
                if case .healthFinding = $0.payload {
                    return true
                }
                return false
            }
        )
        #expect(state.resultContexts.last?.kind == .stats)
        #expect(
            await runtime.observability.semanticEvents()
                .contains(.graphHealthCompiled)
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(blockedEvents) == 1)
        #expect(terminalEventCount(healthEvents) == 1)
    }

    @MainActor
    @Test
    func comparisonCancellationCannotPublishAResultOrSecondTerminal()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures =
            BrainMeshFixtureBuilder(
                context: store.context
            )
        let graph = fixtures.makeGraph(
            name: "Portfolio"
        )
        let projects = fixtures.makeEntity(
            name: "Projekte",
            in: graph
        )
        fixtures.makeAttribute(
            name: "Atlas",
            owner: projects
        )
        fixtures.makeAttribute(
            name: "Apollo",
            owner: projects
        )
        fixtures.makeDetailField(
            owner: projects,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options: ["Offen", "Erledigt"],
            isPinned: true
        )
        try fixtures.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .compareNodes,
                            entityTerm:
                                "Projekte",
                            nodeTerms: [
                                "Atlas",
                                "Apollo",
                            ],
                            projectionTerms: [
                                "Status",
                            ],
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let blocker =
            AdvancedBlockingQueryExecutor()
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            queryExecutorBase: blocker
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let stream =
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Vergleiche Atlas und Apollo.",
                    graphScope: graphScope,
                    chatScope:
                        .entireGraph(
                            graphScope
                        )
                )
        let collector = Task {
            await collect(stream)
        }
        await blocker.waitUntilStarted()
        await runtime.orchestrator
            .cancelCurrentGeneration()
        let events = await collector.value
        let state =
            await runtime.orchestrator
                .conversationStateSnapshot()

        #expect(events.last == .cancelled)
        #expect(terminalEventCount(events) == 1)
        #expect(
            state?.turnContexts.isEmpty
                != false
        )
        #expect(
            state?.resultContexts.isEmpty
                != false
        )
        #expect(
            state?.lastValidatedQueryPlan
                == nil
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    private struct Runtime {
        let orchestrator: GraphChatOrchestrator
        let provider: FakeGraphChatModelProvider
        let nodeExecutor: AdvancedRecordingNodeExecutor
        let statsExecutor: AdvancedRecordingStatsExecutor
        let observability: AdvancedIntentObservabilityRecorder
    }

    @MainActor
    private func makeRuntime(
        store: BrainMeshTestStore,
        graphID: UUID,
        interpreter: FakeGraphChatIntentInterpreter,
        queryExecutorBase:
            (any GraphChatLocalIntentQueryExecuting)? =
                nil
    ) -> Runtime {
        let repository = GraphReadRepository(
            container: AnyModelContainer(store.container)
        )
        let evidenceValidator = GraphEvidenceSourceValidator(
            repository: repository
        )
        let queryEngine = GraphChatQueryEngine(
            repository: repository,
            evidenceValidator: evidenceValidator
        )
        let nodeExecutor = AdvancedRecordingNodeExecutor(
            base: GetNodeTool(
                repository: repository,
                evidenceValidator: evidenceValidator,
                logger: NoOpGraphChatToolLogger()
            )
        )
        let statsExecutor = AdvancedRecordingStatsExecutor(
            base: GraphStatsTool(
                reader: GraphStatsServiceReader(
                    container: AnyModelContainer(store.container)
                ),
                evidenceValidator: evidenceValidator,
                logger: NoOpGraphChatToolLogger()
            )
        )
        let referenceResolver = GraphChatConversationReferenceResolver(
            revalidator:
                GraphChatRepositoryConversationReferenceRevalidator(
                    repository: repository,
                    queryEngine: queryEngine
                )
        )
        let provider = FakeGraphChatModelProvider()
        let observability = AdvancedIntentObservabilityRecorder()
        let orchestrator = GraphChatOrchestrator(
            provider: provider,
            intentInterpreter: interpreter,
            schemaProvider: GraphSchemaService(
                repository: repository
            ),
            foundationalQueryExecutor:
                queryExecutorBase
                ?? queryEngine,
            semanticNodeExecutor: nodeExecutor,
            semanticStatsExecutor: statsExecutor,
            toolRunnerFactory:
                EvidenceRegisteringFakeToolRunnerFactory(),
            referenceResolver: referenceResolver,
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
            observability: observability,
            referenceDate: {
                Date(
                    timeIntervalSince1970:
                        1_768_413_600
                )
            },
            calendar: Calendar(identifier: .gregorian),
            timeZone:
                TimeZone(
                    identifier: "Europe/Berlin"
                )!
        )
        _ = graphID
        return Runtime(
            orchestrator: orchestrator,
            provider: provider,
            nodeExecutor: nodeExecutor,
            statsExecutor: statsExecutor,
            observability: observability
        )
    }

    private func collect(
        _ stream: GraphChatEventStream
    ) async -> [GraphChatStreamEvent] {
        await GraphChatProviderTestSupport.collect(
            stream
        )
    }

    private func completedAnswer(
        _ events: [GraphChatStreamEvent]
    ) throws -> GraphChatAnswer {
        try #require(
            events.compactMap {
                if case .completed(let answer) = $0 {
                    return answer
                }
                return nil
            }.last
        )
    }

    private func resolvedArtifacts(
        answer: GraphChatAnswer,
        runtime: Runtime,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async -> [GraphChatAnswerArtifact] {
        let presentation =
            await runtime.orchestrator
                .resolveAnswerPresentation(
                    artifactIDs: answer.artifactIDs,
                    evidence: answer.evidence,
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        return presentation.artifacts.map(\.artifact)
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

    private func visibleText(
        _ events: [GraphChatStreamEvent]
    ) -> String {
        events.compactMap {
            switch $0 {
            case .partialAnswer(let text):
                return text
            case .completed(let answer):
                return answer.directAnswer
            case .started, .toolActivity, .cancelled, .failure:
                return nil
            }
        }.joined(separator: "\n")
    }
}

private actor AdvancedBlockingQueryExecutor:
    GraphChatLocalIntentQueryExecuting
{
    private var started = false
    private var waiters:
        [CheckedContinuation<Void, Never>] = []

    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult {
        _ = plan
        started = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach {
            $0.resume()
        }
        try await Task.sleep(
            nanoseconds: UInt64.max
        )
        throw CancellationError()
    }

    func waitUntilStarted() async {
        guard started == false else {
            return
        }
        await withCheckedContinuation {
            waiters.append($0)
        }
    }
}

private actor AdvancedRecordingNodeExecutor:
    GraphChatLocalIntentNodeExecuting
{
    private let base: any GraphChatLocalIntentNodeExecuting
    private var recordedInputs: [GetNodeInput] = []

    init(base: any GraphChatLocalIntentNodeExecuting) {
        self.base = base
    }

    func execute(
        _ input: GetNodeInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<GetNodeOutput> {
        recordedInputs.append(input)
        return try await base.execute(input, context: context)
    }

    func inputs() -> [GetNodeInput] {
        recordedInputs
    }
}

private actor AdvancedRecordingStatsExecutor:
    GraphChatLocalIntentStatsExecuting
{
    private let base: any GraphChatLocalIntentStatsExecuting
    private var recordedInputs: [GraphStatsInput] = []

    init(base: any GraphChatLocalIntentStatsExecuting) {
        self.base = base
    }

    func execute(
        _ input: GraphStatsInput,
        context: GraphChatToolContext
    ) async throws -> GraphChatToolResult<GraphStatsOutput> {
        recordedInputs.append(input)
        return try await base.execute(input, context: context)
    }

    func inputs() -> [GraphStatsInput] {
        recordedInputs
    }
}

private actor AdvancedIntentObservabilityRecorder:
    GraphChatObservabilityRecording
{
    private var events: [GraphChatObservabilityEvent] = []

    func record(_ event: GraphChatObservabilityEvent) {
        events.append(event)
    }

    func semanticEvents()
        -> [GraphChatSemanticIntentLifecycleEvent]
    {
        events.compactMap {
            guard case .semanticIntent(let metric) = $0 else {
                return nil
            }
            return metric.event
        }
    }
}
