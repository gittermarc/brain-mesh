import Foundation
import SwiftData
import Testing

@testable import BrainMesh

@Suite("Graph chat semantic intent end-to-end")
struct GraphChatSemanticIntentEndToEndTests {
    @MainActor
    @Test
    func naturalFindRunsLocalSearchWithoutAnswerProvider()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Portfolio"
        )
        let projects = fixtures.makeEntity(
            name: "Projekte",
            in: graph
        )
        let atlas = fixtures.makeAttribute(
            name: "Atlas",
            owner: projects
        )
        let otherGraph = fixtures.makeGraph(
            name: "Archiv"
        )
        let archivedProjects = fixtures.makeEntity(
            name: "Projekte",
            in: otherGraph
        )
        let archivedAtlas = fixtures.makeAttribute(
            name: "Atlas Alt",
            owner: archivedProjects
        )
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .findNodes,
                            entityTerm: "Projekte",
                            searchTerm: "Atlas",
                            findTarget:
                                .entityNodes,
                            resultAmount:
                                .standard,
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let candidates = [
            searchCandidate(
                kind: .entity,
                id: projects.id,
                graphID: graph.id,
                title: "Projekte",
                nodeKind: .entity,
                score: 4
            ),
            searchCandidate(
                kind: .attribute,
                id: atlas.id,
                graphID: graph.id,
                title: atlas.displayName,
                nodeKind: .attribute,
                ownerID: projects.id,
                score: 3
            ),
            searchCandidate(
                kind: .attribute,
                id: archivedAtlas.id,
                graphID: otherGraph.id,
                title:
                    archivedAtlas.displayName,
                nodeKind: .attribute,
                ownerID:
                    archivedProjects.id,
                score: 10
            ),
        ]
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: candidates
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime
                        .orchestrator
                        .streamAnswer(
                            question:
                                "Ich suche den Projekteintrag namens Atlas.",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let answer = try completedAnswer(events)
        let presentation =
            await runtime.orchestrator
                .resolveAnswerPresentation(
                    artifactIDs:
                        answer.artifactIDs,
                    evidence: answer.evidence,
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        let artifact = try #require(
            presentation.artifacts.first?
                .artifact
        )
        guard
            case .resultList(let payload) =
                artifact.payload
        else {
            Issue.record(
                "Expected a local search result artifact."
            )
            return
        }
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let providerSnapshot =
            await runtime.provider.snapshot()
        let interpreterSnapshot =
            await interpreter.snapshot()
        let searchInputs =
            await runtime.searchExecutor.inputs()
        let semanticMetrics =
            await runtime.observability
                .semanticMetrics()

        #expect(
            payload.rows.map(\.primaryText)
                == ["Atlas"]
        )
        #expect(
            answer.evidence.map {
                $0.sourceReference.sourceID
            } == [atlas.id]
        )
        #expect(answer.artifactIDs.count == 1)
        #expect(
            state.resultContexts.last?.kind
                == .search
        )
        #expect(
            state.referenceTargets.plural
                == [
                    .node(
                        NodeRefKey(
                            kind: .attribute,
                            id: atlas.id
                        )
                    )
                ]
        )
        #expect(searchInputs.map(\.limit) == [20])
        #expect(
            providerSnapshot.createdSessions
                .isEmpty
        )
        #expect(
            providerSnapshot.streamedSessions
                .isEmpty
        )
        #expect(
            interpreterSnapshot.requests.count
                == 1
        )
        #expect(
            semanticMetrics.map(\.event)
                == [
                    .interpreterStarted,
                    .draftAccepted,
                    .findIntentCompiled,
                ]
        )
        #expect(
            semanticMetrics
                .reduce(0) {
                    $0
                        + $1
                            .interpreterCallCount
                } == 1
        )
        #expect(
            semanticMetrics
                .reduce(0) {
                    $0
                        + $1
                            .answerProviderCallCount
                } == 0
        )
        #expect(
            interpreterSnapshot.requests[0]
                .schemaEntities
                .contains {
                    $0.displayName
                        == "Projekte"
                }
        )
        #expect(
            interpreterSnapshot.requests[0]
                .schemaEntities
                .flatMap {
                    [$0.displayName]
                        + $0.fieldDisplayNames
                }
                .allSatisfy {
                    GraphChatSemanticSafety
                        .containsTechnicalIdentifier(
                            $0
                        ) == false
                }
        )
        #expect(terminalEventCount(events) == 1)
        #expect(
            visibleText(events)
                .contains(atlas.id.uuidString)
                == false
        )
        #expect(
            ["E1", "N1", "CURRENT", "CR_"]
                .allSatisfy {
                    visibleText(events)
                        .contains($0) == false
                }
        )
    }

    @MainActor
    @Test
    func freeEntityListCommitsArtifactAndCurrent()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Portfolio"
        )
        let projects = fixtures.makeEntity(
            name: "Projekte",
            in: graph
        )
        let zephyr = fixtures.makeAttribute(
            name: "Zephyr",
            owner: projects
        )
        let atlas = fixtures.makeAttribute(
            name: "Atlas",
            owner: projects
        )
        let migration = fixtures.makeAttribute(
            name: "Migration",
            owner: projects
        )
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .entityList,
                            entityTerm: "Projekte",
                            resultAmount: .all,
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime
                        .orchestrator
                        .streamAnswer(
                            question:
                                "Ich möchte die Projektübersicht sehen, ganz ohne Filter.",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let answer = try completedAnswer(events)
        let presentation =
            await runtime.orchestrator
                .resolveAnswerPresentation(
                    artifactIDs:
                        answer.artifactIDs,
                    evidence: answer.evidence,
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        let artifact = try #require(
            presentation.artifacts.first?
                .artifact
        )
        guard
            case .resultList(let payload) =
                artifact.payload
        else {
            Issue.record(
                "Expected a local entity-list artifact."
            )
            return
        }
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let expectedNodes = [
            atlas,
            migration,
            zephyr,
        ].map {
            NodeRefKey(
                kind: .attribute,
                id: $0.id
            )
        }
        let providerSnapshot =
            await runtime.provider.snapshot()

        #expect(
            payload.rows.map(\.primaryText)
                == [
                    "Atlas",
                    "Migration",
                    "Zephyr",
                ]
        )
        #expect(
            payload.resultMetadata
                .returnedCount == 3
        )
        #expect(
            payload.resultMetadata
                .truncation.isTruncated
                == false
        )
        #expect(
            state.lastValidatedQueryPlan?
                .projection
                == [.nodeIdentity]
        )
        #expect(
            state.lastValidatedQueryPlan?
                .sorting
                == [
                    GraphValidatedQuerySort(
                        key: .nodeName,
                        direction: .ascending
                    )
                ]
        )
        #expect(
            state.lastValidatedQueryPlan?
                .limit
                == GraphQueryPlanLimits
                    .maximumResultLimit
        )
        #expect(
            state.referenceTargets.plural
                == expectedNodes.map {
                    .node($0)
                }
        )
        #expect(answer.artifactIDs.count == 1)
        #expect(
            providerSnapshot.createdSessions
                .isEmpty
        )
        #expect(
            providerSnapshot.streamedSessions
                .isEmpty
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func allEntityListCapsAtMaximumAndPreservesTruncation()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Großes Portfolio"
        )
        let projects = fixtures.makeEntity(
            name: "Projekte",
            in: graph
        )
        for index in 0..<205 {
            fixtures.makeAttribute(
                name: String(
                    format:
                        "Projekt %03d",
                    index
                ),
                owner: projects
            )
        }
        try fixtures.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .entityList,
                            entityTerm: "Projekte",
                            resultAmount: .all,
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime
                        .orchestrator
                        .streamAnswer(
                            question:
                                "Eine freie Gesamtübersicht des Projektbestands wäre hilfreich.",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let answer = try completedAnswer(events)
        let presentation =
            await runtime.orchestrator
                .resolveAnswerPresentation(
                    artifactIDs:
                        answer.artifactIDs,
                    evidence: answer.evidence,
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        let artifact = try #require(
            presentation.artifacts.first?
                .artifact
        )
        guard
            case .resultList(let payload) =
                artifact.payload
        else {
            Issue.record(
                "Expected a truncated result-list artifact."
            )
            return
        }
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )

        #expect(
            state.lastValidatedQueryPlan?
                .limit
                == GraphQueryPlanLimits
                    .maximumResultLimit
        )
        #expect(
            payload.resultMetadata.totalCount
                == 205
        )
        #expect(
            payload.resultMetadata.returnedCount
                == GraphQueryPlanLimits
                    .maximumResultLimit
        )
        #expect(
            payload.resultMetadata
                .truncation.isTruncated
        )
        #expect(
            payload.resultMetadata
                .truncation.omittedCount
                == 5
        )
        #expect(
            answer.directAnswer
                .contains("Sicherheitslimit")
        )
        #expect(
            answer.directAnswer
                .contains("5")
        )
        #expect(
            state.resultContexts.last?
                .kind == .query
        )
        #expect(
            state.resultContexts.last?
                .references.isEmpty == false
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func duplicateEntitiesUsePendingSemanticClarification()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Portfolio"
        )
        let firstID = UUID(
            uuidString:
                "21000000-0000-0000-0000-000000000001"
        )!
        let secondID = UUID(
            uuidString:
                "21000000-0000-0000-0000-000000000002"
        )!
        let first = fixtures.makeEntity(
            name: "Projekte",
            in: graph,
            id: firstID
        )
        let second = fixtures.makeEntity(
            name: "Projekte",
            in: graph,
            id: secondID
        )
        fixtures.makeAttribute(
            name: "Atlas",
            owner: first
        )
        fixtures.makeAttribute(
            name: "Borealis",
            owner: second
        )
        try fixtures.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .entityList,
                            entityTerm: "Projekte",
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let firstEvents =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Eine frei formulierte Projektübersicht, bitte.",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let firstAnswer =
            try completedAnswer(firstEvents)
        guard
            case .clarification(
                let clarification
            ) = firstAnswer.state
        else {
            Issue.record(
                "Expected a semantic entity clarification."
            )
            return
        }
        let pendingState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )

        #expect(clarification.options.count == 2)
        #expect(
            pendingState
                .pendingClarification?
                .decision == .semanticIntent
        )
        #expect(
            await interpreter.snapshot()
                .requests.count == 1
        )

        let secondEvents =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question: "2",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let secondAnswer =
            try completedAnswer(secondEvents)
        let resolvedState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )

        #expect(
            resolvedState
                .pendingClarification == nil
        )
        #expect(
            resolvedState
                .lastValidatedQueryPlan?
                .entityID == secondID
        )
        #expect(secondAnswer.artifactIDs.count == 1)
        #expect(
            await interpreter.snapshot()
                .requests.count == 1
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
    func foundationalQuestionSkipsInterpreter()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Reisen"
        )
        let trips = fixtures.makeEntity(
            name: "Reisen",
            in: graph
        )
        fixtures.makeAttribute(
            name: "Berlin",
            owner: trips
        )
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .failure(
                        GraphChatIntentInterpreterError(
                            code: .unexpected,
                            message:
                                "Must not be invoked."
                        )
                    )
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime
                        .orchestrator
                        .streamAnswer(
                            question:
                                "Welche Reisen habe ich gemacht?",
                            graphScope:
                                graphScope,
                            chatScope:
                                .entireGraph(
                                    graphScope
                                )
                        )
                )

        #expect(
            await interpreter.snapshot()
                .requests.isEmpty
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(
            await runtime.observability
                .semanticMetrics()
                .isEmpty
        )
        #expect(
            try completedAnswer(events)
                .artifactIDs.count == 1
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func openEndedDraftUsesLegacyProvider()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Wissen"
        )
        try fixtures.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .openEnded,
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: []
        )
        await runtime.provider.enqueue(
            FakeGraphChatProviderScript(
                steps: [
                    .event(
                        .completed(
                            GraphChatProviderTestSupport
                                .makeFinalAnswer(
                                    directAnswer:
                                        "Lokale freie Antwort."
                                )
                        )
                    )
                ]
            )
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime
                        .orchestrator
                        .streamAnswer(
                            question:
                                "Was ist daran bemerkenswert?",
                            graphScope:
                                graphScope,
                            chatScope:
                                .entireGraph(
                                    graphScope
                                )
                        )
                )
        let snapshot =
            await runtime.provider.snapshot()
        let semanticMetrics =
            await runtime.observability
                .semanticMetrics()

        #expect(
            try completedAnswer(events)
                .directAnswer
                == "Lokale freie Antwort."
        )
        #expect(
            await interpreter.snapshot()
                .requests.count == 1
        )
        #expect(snapshot.createdSessions.count == 1)
        #expect(snapshot.streamedSessions.count == 1)
        #expect(
            semanticMetrics.map(\.event)
                == [
                    .interpreterStarted,
                    .draftAccepted,
                    .legacyProviderFallback,
                    .answerProviderStarted,
                ]
        )
        #expect(
            semanticMetrics
                .reduce(0) {
                    $0
                        + $1
                            .answerProviderCallCount
                } == 1
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func interpreterCancellationCommitsNothing()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Portfolio"
        )
        try fixtures.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [.waitForCancellation]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let stream =
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Suche bitte frei nach Atlas.",
                    graphScope: graphScope,
                    chatScope:
                        .entireGraph(graphScope)
                )
        let collection = Task {
            await GraphChatProviderTestSupport
                .collect(stream)
        }
        await GraphChatProviderTestSupport
            .waitUntil {
                await interpreter.snapshot()
                    .requests.count == 1
            }
        await runtime.orchestrator
            .cancelCurrentGeneration()
        let events = await collection.value
        let state =
            await runtime.orchestrator
                .conversationStateSnapshot()

        #expect(
            events.contains {
                if case .cancelled = $0 {
                    return true
                }
                return false
            }
        )
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
            state?.pendingClarification == nil
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    @MainActor
    @Test
    func localQueryFailureRollsBackTurnState()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Portfolio"
        )
        fixtures.makeEntity(
            name: "Projekte",
            in: graph
        )
        try fixtures.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .entityList,
                            entityTerm: "Projekte",
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: [],
            queryExecutorBase:
                SemanticFailingQueryExecutor()
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Zeige mir bitte frei formuliert die Projekte.",
                            graphScope:
                                graphScope,
                            chatScope:
                                .entireGraph(
                                    graphScope
                                )
                        )
                )
        let state =
            await runtime.orchestrator
                .conversationStateSnapshot()

        #expect(
            events.contains {
                if case .failure = $0 {
                    return true
                }
                return false
            }
        )
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
            state?.pendingClarification == nil
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    @MainActor
    @Test
    func localSearchFailureRollsBackTurnState()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let fixtures = BrainMeshFixtureBuilder(
            context: store.context
        )
        let graph = fixtures.makeGraph(
            name: "Portfolio"
        )
        try fixtures.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .findNodes,
                            searchTerm: "Atlas",
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: [],
            searchExecutorBase:
                SemanticFailingSearchExecutor()
        )
        let graphScope = GraphScope(
            graphID: graph.id
        )
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Suche frei nach Atlas.",
                            graphScope:
                                graphScope,
                            chatScope:
                                .entireGraph(
                                    graphScope
                                )
                        )
                )
        let state =
            await runtime.orchestrator
                .conversationStateSnapshot()

        #expect(
            events.contains {
                if case .failure = $0 {
                    return true
                }
                return false
            }
        )
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
            state?.pendingClarification == nil
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
    }

    private struct Runtime {
        let orchestrator: GraphChatOrchestrator
        let provider: FakeGraphChatModelProvider
        let searchExecutor:
            SemanticRecordingSearchExecutor
        let observability:
            SemanticIntentObservabilityRecorder
    }

    @MainActor
    private func makeRuntime(
        store: BrainMeshTestStore,
        graphID: UUID,
        interpreter:
            FakeGraphChatIntentInterpreter,
        candidates: [BrainMeshSearchCandidate],
        queryExecutorBase:
            (any GraphChatLocalIntentQueryExecuting)? =
                nil,
        searchExecutorBase:
            (any GraphChatLocalIntentSearchExecuting)? =
                nil
    ) -> Runtime {
        let repository = GraphReadRepository(
            container:
                AnyModelContainer(
                    store.container
                )
        )
        let validator =
            GraphEvidenceSourceValidator(
                repository: repository
            )
        let schemaService = GraphSchemaService(
            repository: repository
        )
        let queryEngine = GraphChatQueryEngine(
            repository: repository,
            evidenceValidator: validator
        )
        let readiness =
            GraphSearchIndexReadinessResult(
                graphID: graphID,
                reason: .chatSession,
                outcome: .ready,
                isIndexUsable: true,
                documentCount:
                    candidates.count,
                metrics: nil,
                failure: nil
            )
        let searchTool = SearchGraphTool(
            readinessProvider:
                SemanticSearchReadinessStub(
                    result: readiness
                ),
            indexedProvider:
                SemanticIndexedSearchStub(
                    candidates:
                        candidates
                ),
            sourceRepository: repository,
            evidenceValidator: validator,
            logger:
                NoOpGraphChatToolLogger()
        )
        let searchExecutor =
            SemanticRecordingSearchExecutor(
                base:
                    searchExecutorBase
                    ?? searchTool
            )
        let provider =
            FakeGraphChatModelProvider()
        let observability =
            SemanticIntentObservabilityRecorder()
        let orchestrator =
            GraphChatOrchestrator(
                provider: provider,
                intentInterpreter:
                    interpreter,
                schemaProvider:
                    schemaService,
                foundationalQueryExecutor:
                    queryExecutorBase
                    ?? queryEngine,
                semanticSearchExecutor:
                    searchExecutor,
                toolRunnerFactory:
                    EvidenceRegisteringFakeToolRunnerFactory(),
                responseLanguageSelector:
                    GraphChatResponseLanguageSelector(
                        fallback: .german
                    ),
                artifactRevalidator:
                    GraphChatLiveAnswerArtifactRevalidator(
                        evidenceValidator:
                            validator,
                        sourceRepository:
                            repository
                    ),
                evidenceValidator:
                    validator,
                observability:
                    observability,
                referenceDate: {
                    Date(
                        timeIntervalSince1970:
                            1_768_413_600
                    )
                },
                calendar:
                    Calendar(
                        identifier: .gregorian
                    ),
                timeZone:
                    TimeZone(
                        identifier:
                            "Europe/Berlin"
                    )!
            )
        return Runtime(
            orchestrator: orchestrator,
            provider: provider,
            searchExecutor: searchExecutor,
            observability: observability
        )
    }

    private func searchCandidate(
        kind: BrainMeshSearchResultKind,
        id: UUID,
        graphID: UUID,
        title: String,
        nodeKind: NodeKind,
        ownerID: UUID? = nil,
        score: Int
    ) -> BrainMeshSearchCandidate {
        BrainMeshSearchCandidate(
            result: BrainMeshSearchResult(
                kind: kind,
                id: id,
                graphID: graphID,
                title: title,
                subtitle: "",
                iconSymbolName:
                    kind.defaultIconSymbolName,
                matchReason: "Name",
                nodeKindRaw:
                    nodeKind.rawValue,
                nodeID: id,
                ownerKindRaw:
                    ownerID == nil
                    ? nil
                    : NodeKind.entity
                        .rawValue,
                ownerID: ownerID
            ),
            score: score
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

    private func terminalEventCount(
        _ events: [GraphChatStreamEvent]
    ) -> Int {
        events.filter {
            switch $0 {
            case .completed, .cancelled, .failure:
                return true
            case .started, .toolActivity,
                .partialAnswer:
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
            case .started, .toolActivity,
                .cancelled, .failure:
                return nil
            }
        }.joined(separator: "\n")
    }
}

private nonisolated struct SemanticSearchReadinessStub:
    BrainMeshSearchIndexReadinessProviding
{
    let result: GraphSearchIndexReadinessResult

    func ensureReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult {
        result.replacingReason(with: reason)
    }

    func invalidate(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async {}
}

private nonisolated struct SemanticIndexedSearchStub:
    BrainMeshIndexedSearchCandidateProviding
{
    let candidates: [BrainMeshSearchCandidate]

    func candidates(
        graphIDs: [UUID],
        foldedQuery: String,
        resultLimit: Int
    ) async throws
        -> BrainMeshIndexedSearchCandidateResponse
    {
        BrainMeshIndexedSearchCandidateResponse(
            candidates:
                Array(candidates.prefix(resultLimit)),
            indexDocumentCount: candidates.count
        )
    }
}

private actor SemanticRecordingSearchExecutor:
    GraphChatLocalIntentSearchExecuting
{
    private let base:
        any GraphChatLocalIntentSearchExecuting
    private var recordedInputs:
        [SearchGraphInput] = []

    init(
        base:
            any GraphChatLocalIntentSearchExecuting
    ) {
        self.base = base
    }

    func execute(
        _ input: SearchGraphInput,
        context: GraphChatToolContext
    ) async throws
        -> GraphChatToolResult<SearchGraphOutput>
    {
        recordedInputs.append(input)
        return try await base.execute(
            input,
            context: context
        )
    }

    func inputs() -> [SearchGraphInput] {
        recordedInputs
    }
}

private nonisolated struct SemanticFailingSearchExecutor:
    GraphChatLocalIntentSearchExecuting
{
    func execute(
        _ input: SearchGraphInput,
        context: GraphChatToolContext
    ) async throws
        -> GraphChatToolResult<SearchGraphOutput>
    {
        throw GraphChatToolError(
            code: .sourceUnavailable,
            message:
                "Injected local search failure."
        )
    }
}

private nonisolated struct SemanticFailingQueryExecutor:
    GraphChatLocalIntentQueryExecuting
{
    func execute(
        _ plan: ValidatedGraphQueryPlan
    ) async throws -> GraphChatQueryResult {
        throw GraphChatQueryEngineError
            .sourceUnavailable
    }
}

private actor SemanticIntentObservabilityRecorder:
    GraphChatObservabilityRecording
{
    private var events:
        [GraphChatObservabilityEvent] = []

    func record(
        _ event: GraphChatObservabilityEvent
    ) {
        events.append(event)
    }

    func semanticMetrics()
        -> [GraphChatSemanticIntentMetric]
    {
        events.compactMap {
            guard
                case .semanticIntent(
                    let metric
                ) = $0
            else {
                return nil
            }
            return metric
        }
    }
}
