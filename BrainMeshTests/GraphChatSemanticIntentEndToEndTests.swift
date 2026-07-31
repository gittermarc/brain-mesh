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
    func contextWindowRetryUsesOneCompactRequestAndStillRunsLocally()
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
            name: "A Projekte",
            in: graph
        )
        fixtures.makeAttribute(
            name: "Atlas",
            owner: projects
        )
        for index in 0..<30 {
            let entity = fixtures.makeEntity(
                name: "Bereich \(index)",
                in: graph
            )
            for fieldIndex in 0..<14 {
                fixtures.makeDetailField(
                    owner: entity,
                    name:
                        "Feld \(fieldIndex)",
                    type: .singleLineText,
                    sortIndex: fieldIndex
                )
            }
        }
        try fixtures.save()

        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .failure(
                        GraphChatIntentInterpreterError(
                            code:
                                .contextWindowExceeded,
                            message:
                                "Injected standard profile overflow."
                        )
                    ),
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .entityList,
                            entityTerm:
                                "A Projekte",
                            resultAmount:
                                .standard,
                            responseLanguage:
                                .german
                        )
                    ),
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Zeige mir die Projekte.",
                            graphScope:
                                graphScope,
                            chatScope:
                                .entireGraph(
                                    graphScope
                                )
                        )
                )
        let requests =
            await interpreter.snapshot()
                .requests
        let plannerMetrics =
            await runtime.observability
                .plannerMetrics()

        #expect(requests.count == 2)
        #expect(
            requests[0].schemaEntities.count
                == GraphChatIntentLimitPolicy
                    .default
                    .standardInterpreterContext
                    .maximumEntities
        )
        #expect(
            requests[1].schemaEntities.count
                == GraphChatIntentLimitPolicy
                    .default
                    .compactInterpreterContext
                    .maximumEntities
        )
        #expect(
            requests[0].schemaEntities
                .allSatisfy {
                    $0.fieldDisplayNames.count
                        <= GraphChatIntentLimitPolicy
                            .default
                            .standardInterpreterContext
                            .maximumFieldsPerEntity
                }
        )
        #expect(
            requests[1].schemaEntities
                .allSatisfy {
                    $0.fieldDisplayNames.count
                        <= GraphChatIntentLimitPolicy
                            .default
                            .compactInterpreterContext
                            .maximumFieldsPerEntity
                }
        )
        #expect(
            plannerMetrics.contains(
                GraphChatTypedPlannerMetric(
                    event: .interpreterRetry
                )
            )
        )
        #expect(
            plannerMetrics.filter {
                $0.event == .interpreterRetry
            }.count == 1
        )
        #expect(
            plannerMetrics.filter {
                if case .terminalOutcome =
                    $0.event
                {
                    return true
                }
                return false
            }.count == 1
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(
            try completedAnswer(events)
                .artifactIDs.count == 1
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func compactRetryFailureFallsBackOnceWithoutRepairLoop()
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
            name: "Wissen"
        )
        try fixtures.save()
        let contextFailure =
            GraphChatIntentInterpreterError(
                code: .contextWindowExceeded,
                message:
                    "Injected context overflow."
            )
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .failure(contextFailure),
                    .failure(contextFailure),
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .findNodes,
                            searchTerm: "Must not run",
                            responseLanguage:
                                .german
                        )
                    ),
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
                                        "Freie Antwort."
                                )
                        )
                    )
                ]
            )
        )
        let graphScope =
            GraphScope(graphID: graph.id)
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Erkläre den Graphen frei.",
                            graphScope:
                                graphScope,
                            chatScope:
                                .entireGraph(
                                    graphScope
                                )
                        )
                )
        let provider =
            await runtime.provider.snapshot()
        let plannerMetrics =
            await runtime.observability
                .plannerMetrics()

        #expect(
            await interpreter.snapshot()
                .requests.count == 2
        )
        #expect(provider.createdSessions.count == 1)
        #expect(provider.streamedSessions.count == 1)
        #expect(
            plannerMetrics.filter {
                $0.event == .interpreterRetry
            }.count == 1
        )
        #expect(
            plannerMetrics.filter {
                if case
                    .legacyProviderFallback(
                        .interpreterUnavailable
                    ) = $0.event
                {
                    return true
                }
                return false
            }.count == 1
        )
        #expect(
            try completedAnswer(events)
                .directAnswer
                == "Freie Antwort."
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func manipulatedRecognizedDraftFailsClosedWithoutProvider()
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
        _ = fixtures.makeEntity(
            name: "Projekte",
            in: graph
        )
        try fixtures.save()
        let injectedID = UUID()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .filteredCollection,
                            entityTerm:
                                "Projekte",
                            filters: [
                                GraphChatSemanticFilterDraft(
                                    fieldTerm:
                                        injectedID
                                            .uuidString,
                                    relation:
                                        .equals,
                                    values:
                                        ["offen"]
                                )
                            ],
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
        let graphScope =
            GraphScope(graphID: graph.id)
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Zeige offene Projekte.",
                            graphScope:
                                graphScope,
                            chatScope:
                                .entireGraph(
                                    graphScope
                                )
                        )
                )
        let plannerMetrics =
            await runtime.observability
                .plannerMetrics()

        #expect(
            events.contains {
                if case .failure = $0 {
                    return true
                }
                return false
            }
        )
        #expect(
            await interpreter.snapshot()
                .requests.count == 1
        )
        #expect(
            await runtime.provider.snapshot()
                .createdSessions.isEmpty
        )
        #expect(
            plannerMetrics.contains {
                if case
                    .legacyProviderFallback =
                        $0.event
                {
                    return true
                }
                return false
            } == false
        )
        #expect(
            plannerMetrics.filter {
                if case .terminalOutcome =
                    $0.event
                {
                    return true
                }
                return false
            }.count == 1
        )
        #expect(
            visibleText(events)
                .contains(
                    injectedID.uuidString
                ) == false
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func openProjectsSortedByDueDateThenRefineOnlyTheValidatedResultSet()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(
            context: store.context
        )
        let fixture =
            makeQueryIntentFixture(builder)
        try builder.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .filteredCollection,
                            entityTerm:
                                "Projekte",
                            filters: [
                                GraphChatSemanticFilterDraft(
                                    fieldTerm:
                                        "Status",
                                    relation:
                                        .equals,
                                    values:
                                        ["Offen"]
                                )
                            ],
                            sorting:
                                GraphChatSemanticSortDraft(
                                    target:
                                        .field,
                                    fieldTerm:
                                        "Fälligkeitsdatum",
                                    direction:
                                        .ascending
                                ),
                            responseLanguage:
                                .german
                        )
                    ),
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .refinement,
                            conversationReference:
                                .currentSelection,
                            filters: [
                                GraphChatSemanticFilterDraft(
                                    fieldTerm:
                                        "Fälligkeitsdatum",
                                    relation:
                                        .isOverdue,
                                    values: []
                                )
                            ],
                            responseLanguage:
                                .german
                        )
                    ),
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: fixture.graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: fixture.graph.id
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
                                "Zeige offene Projekte, sortiert nach Fälligkeitsdatum.",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let firstAnswer =
            try completedAnswer(firstEvents)
        let firstArtifact =
            try await resolvedArtifact(
                answer: firstAnswer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )
        guard
            case .resultList(let firstList) =
                firstArtifact.payload
        else {
            Issue.record(
                "Expected the sorted collection artifact."
            )
            return
        }
        let firstState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let sourceNodes = Set<NodeRefKey>(
            firstState.resultContexts
                .last?
                .references
                .compactMap { reference -> NodeRefKey? in
                    if case .node(let node) =
                        reference.reference {
                        return node
                    }
                    return nil
                } ?? []
        )

        let secondEvents =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Welche davon sind überfällig?",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let secondAnswer =
            try completedAnswer(secondEvents)
        let secondArtifact =
            try await resolvedArtifact(
                answer: secondAnswer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )
        guard
            case .resultList(let secondList) =
                secondArtifact.payload
        else {
            Issue.record(
                "Expected the refined collection artifact."
            )
            return
        }
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let plan = try #require(
            state.lastValidatedQueryPlan
        )
        guard case .selection(let planNodes) =
            plan.scope else {
            Issue.record(
                "Expected an exact source selection."
            )
            return
        }
        let returnedNodes = Set<NodeRefKey>(
            state.resultContexts.last?
                .references
                .compactMap { reference -> NodeRefKey? in
                    if case .node(let node) =
                        reference.reference {
                        return node
                    }
                    return nil
                } ?? []
        )
        let provider =
            await runtime.provider.snapshot()
        let metrics =
            await runtime.observability
                .semanticMetrics()

        #expect(
            firstList.rows.map(\.primaryText)
                == [
                    "Apollo",
                    "Carina",
                    "Borealis",
                ]
        )
        #expect(
            secondList.rows.map(\.primaryText)
                == ["Apollo", "Carina"]
        )
        #expect(Set(planNodes) == sourceNodes)
        #expect(
            returnedNodes.isSubset(
                of: sourceNodes
            )
        )
        #expect(
            returnedNodes.contains(
                fixture.closedOverdueNode
            ) == false
        )
        #expect(
            returnedNodes.contains(
                fixture.foreignOverdueNode
            ) == false
        )
        #expect(
            plan.filters.map(\.operation)
                == [.equals, .isOverdue]
        )
        #expect(
            plan.sorting == [
                GraphValidatedQuerySort(
                    key: .field(
                        fixture.dueField.id
                    ),
                    direction: .ascending
                )
            ]
        )
        #expect(
            provider.createdSessions.isEmpty
        )
        #expect(
            provider.streamedSessions.isEmpty
        )
        #expect(
            metrics.map(\.event) == [
                .interpreterStarted,
                .draftAccepted,
                .filteredCollectionCompiled,
                .interpreterStarted,
                .draftAccepted,
                .refinementIntentCompiled,
            ]
        )
        #expect(
            metrics.reduce(0) {
                $0 + $1.answerProviderCallCount
            } == 0
        )
        #expect(terminalEventCount(firstEvents) == 1)
        #expect(terminalEventCount(secondEvents) == 1)
        #expect(
            visibleText(firstEvents + secondEvents)
                .contains(
                    fixture.entity.id
                        .uuidString
                ) == false
        )
    }

    @MainActor
    @Test
    func openProjectCountProducesMetricArtifactWithoutProvider()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(
            context: store.context
        )
        let fixture =
            makeQueryIntentFixture(builder)
        try builder.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family: .count,
                            entityTerm:
                                "Projekte",
                            filters: [
                                GraphChatSemanticFilterDraft(
                                    fieldTerm:
                                        "Status",
                                    relation:
                                        .equals,
                                    values:
                                        ["Offen"]
                                )
                            ],
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: fixture.graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: fixture.graph.id
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let events =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Wie viele offene Projekte gibt es?",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let answer = try completedAnswer(events)
        let artifact =
            try await resolvedArtifact(
                answer: answer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )
        guard case .metric(let metric) =
            artifact.payload else {
            Issue.record(
                "Expected a metric artifact."
            )
            return
        }
        let state = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let provider =
            await runtime.provider.snapshot()
        let metrics =
            await runtime.observability
                .semanticMetrics()

        #expect(metric.value == .integer(3))
        #expect(
            state.lastValidatedQueryPlan?
                .aggregation == .count
        )
        #expect(
            state.resultContexts.last?
                .references.isEmpty == true
        )
        #expect(
            provider.createdSessions.isEmpty
        )
        #expect(
            provider.streamedSessions.isEmpty
        )
        #expect(
            metrics.map(\.event) == [
                .interpreterStarted,
                .draftAccepted,
                .countIntentCompiled,
            ]
        )
        #expect(terminalEventCount(events) == 1)
    }

    @MainActor
    @Test
    func groupingCreatesGroupArtifactReferencesAndSafeGroupContinuation()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(
            context: store.context
        )
        let fixture =
            makeQueryIntentFixture(builder)
        try builder.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .groupCount,
                            entityTerm:
                                "Projekte",
                            groupFieldTerm:
                                "Status",
                            responseLanguage:
                                .german
                        )
                    ),
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .refinement,
                            conversationReference:
                                .currentSelection,
                            sorting:
                                GraphChatSemanticSortDraft(
                                    target:
                                        .nodeName,
                                    fieldTerm: nil,
                                    direction:
                                        .ascending
                                ),
                            responseLanguage:
                                .german
                        )
                    ),
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: fixture.graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: fixture.graph.id
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let groupEvents =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Gruppiere Projekte nach Status.",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let groupAnswer =
            try completedAnswer(groupEvents)
        let artifact =
            try await resolvedArtifact(
                answer: groupAnswer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )
        guard case .grouping(let grouping) =
            artifact.payload else {
            Issue.record(
                "Expected a grouping artifact."
            )
            return
        }
        let groupedState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let openGroup = try #require(
            groupedState.groupReferences.first {
                $0.valueDescription == "Offen"
            }
        )

        let continuationEvents =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question:
                                "Sortiere diese Gruppe nach Name.",
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let continuationAnswer =
            try completedAnswer(
                continuationEvents
            )
        let continuationArtifact =
            try await resolvedArtifact(
                answer: continuationAnswer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )
        guard
            case .resultList(
                let continuationList
            ) = continuationArtifact.payload
        else {
            Issue.record(
                "Expected a group continuation list."
            )
            return
        }
        let finalState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let plan = try #require(
            finalState.lastValidatedQueryPlan
        )
        guard case .selection(let nodes) =
            plan.scope else {
            Issue.record(
                "Expected an exact group-member selection."
            )
            return
        }
        let provider =
            await runtime.provider.snapshot()

        #expect(
            grouping.groups.map(\.label)
                == ["Fertig", "Offen"]
        )
        #expect(
            grouping.groups.map(\.count)
                == [1, 3]
        )
        #expect(
            groupedState.groupReferences
                .allSatisfy {
                    $0.memberNodes.count
                        == $0.count
                }
        )
        #expect(Set(nodes) == Set(openGroup.memberNodes))
        #expect(
            continuationList.rows
                .map(\.primaryText) == [
                    "Apollo",
                    "Borealis",
                    "Carina",
                ]
        )
        #expect(
            provider.createdSessions.isEmpty
        )
        #expect(
            provider.streamedSessions.isEmpty
        )
        #expect(terminalEventCount(groupEvents) == 1)
        #expect(
            terminalEventCount(
                continuationEvents
            ) == 1
        )
    }

    @MainActor
    @Test
    func compiledQueryCancellationCommitsNothingAndEmitsOneTerminalEvent()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(
            context: store.context
        )
        let fixture =
            makeQueryIntentFixture(builder)
        try builder.save()
        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .filteredCollection,
                            entityTerm:
                                "Projekte",
                            filters: [
                                GraphChatSemanticFilterDraft(
                                    fieldTerm:
                                        "Status",
                                    relation:
                                        .equals,
                                    values:
                                        ["Offen"]
                                )
                            ],
                            responseLanguage:
                                .german
                        )
                    )
                ]
            )
        let blocker =
            SemanticBlockingQueryExecutor()
        let runtime = makeRuntime(
            store: store,
            graphID: fixture.graph.id,
            interpreter: interpreter,
            candidates: [],
            queryExecutorBase: blocker
        )
        let graphScope = GraphScope(
            graphID: fixture.graph.id
        )
        let stream =
            await runtime.orchestrator
                .streamAnswer(
                    question:
                        "Zeige offene Projekte.",
                    graphScope: graphScope,
                    chatScope:
                        .entireGraph(
                            graphScope
                        )
                )
        let collector = Task {
            await GraphChatProviderTestSupport
                .collect(stream)
        }
        await blocker.waitUntilStarted()
        await runtime.orchestrator
            .cancelCurrentGeneration()
        let events = await collector.value
        let state =
            await runtime.orchestrator
                .conversationStateSnapshot()
        let localMetrics =
            await runtime.observability
                .localMetrics()

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
        #expect(
            localMetrics.map(\.event)
                == [
                    .executionStarted,
                    .cancelledBeforeCommit,
                    .executionRolledBack,
                ]
        )
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

    @MainActor
    @Test
    func interpretationCorrectionReplacesNameSortWithDueDateLocally()
        async throws
    {
        let store =
            try BrainMeshTestContainer
                .makeInMemoryStore()
        let builder = BrainMeshFixtureBuilder(
            context: store.context
        )
        let fixture =
            makeQueryIntentFixture(builder)
        try builder.save()

        let interpreter =
            FakeGraphChatIntentInterpreter(
                steps: [
                    .draft(
                        GraphChatUntrustedSemanticIntentDraft(
                            family:
                                .filteredCollection,
                            entityTerm:
                                "Projekte",
                            filters: [
                                GraphChatSemanticFilterDraft(
                                    fieldTerm:
                                        "Status",
                                    relation:
                                        .equals,
                                    values:
                                        ["Offen"]
                                ),
                            ],
                            sorting:
                                GraphChatSemanticSortDraft(
                                    target:
                                        .nodeName,
                                    fieldTerm: nil,
                                    direction:
                                        .ascending
                                ),
                            responseLanguage:
                                .german
                        )
                    ),
                ]
            )
        let runtime = makeRuntime(
            store: store,
            graphID: fixture.graph.id,
            interpreter: interpreter,
            candidates: []
        )
        let graphScope = GraphScope(
            graphID: fixture.graph.id
        )
        let chatScope =
            GraphChatScope.entireGraph(
                graphScope
            )
        let question =
            "Offene Projekte, sortiert nach Name"

        let initialEvents =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamAnswer(
                            question: question,
                            graphScope:
                                graphScope,
                            chatScope:
                                chatScope
                        )
                )
        let initialAnswer =
            try completedAnswer(initialEvents)
        let initialArtifact =
            try await resolvedArtifact(
                answer: initialAnswer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )
        guard
            case .resultList(let initialList) =
                initialArtifact.payload
        else {
            Issue.record(
                "Expected the initial name-sorted result list."
            )
            return
        }
        let initialState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let initialResultID = try #require(
            initialState.resultContexts.last?.id
        )
        let interpretation = try #require(
            initialAnswer.interpretation
        )
        let origin = try #require(
            interpretation.correctionOrigin
        )

        #expect(interpretation.isCorrectionEditable)
        #expect(
            initialList.rows.map(\.primaryText)
                == [
                    "Apollo",
                    "Borealis",
                    "Carina",
                ]
        )
        #expect(
            initialState.lastValidatedQueryPlan?
                .sorting == [
                    GraphValidatedQuerySort(
                        key: .nodeName,
                        direction: .ascending
                    ),
                ]
        )

        let schemaContext =
            try await runtime.schemaService
                .makeSnapshot(
                    in: graphScope,
                    exampleFieldIDs: []
                )
        let editorSnapshot =
            GraphChatInterpretationCorrectionSchemaBuilder()
                .makeSnapshot(
                    context: schemaContext,
                    chatScope: chatScope,
                    language: .german
                )
        var selection =
            editorSnapshot.initialSelection(
                interpretation:
                    interpretation,
                origin: origin
            )
        selection.sorting = [
            GraphChatInterpretationCorrectionSort(
                key: .field(
                    fixture.dueField.id
                ),
                direction: .ascending
            ),
        ]

        let userMessage = GraphChatMessage(
            role: .user,
            text: question
        )
        let assistantMessage =
            GraphChatMessage(
                role: .assistant,
                text:
                    initialAnswer.directAnswer,
                evidenceIDs:
                    initialAnswer.evidenceIDs
            )
        let currentCheckpoint =
            GraphChatConversationCheckpoint
                .committed(initialState)
        let binding =
            try GraphChatInterpretationCorrectionBinding(
                originalUserMessage:
                    userMessage,
                originalAssistantMessage:
                    assistantMessage,
                originalRequest:
                    GraphChatRequest(
                        id:
                            interpretation
                                .turnBinding
                                .requestID,
                        scope: chatScope,
                        messages: [userMessage]
                    ),
                originalTurnID:
                    interpretation
                        .turnBinding
                        .turnID,
                conversationID:
                    interpretation
                        .turnBinding
                        .conversationID,
                graphScope: graphScope,
                chatScope: chatScope,
                intentDomainVersion:
                    origin.adaptation
                        .intent.version,
                originalInterpretation:
                    interpretation,
                artifactSessionID:
                    origin.artifactSessionID,
                checkpointBeforeOriginalTurn:
                    .initial(
                        graphScope:
                            graphScope,
                        chatScope:
                            chatScope
                    ),
                expectedCurrentCheckpoint:
                    currentCheckpoint,
                artifactIDsToReplace:
                    initialAnswer.artifactIDs
            )
        let correctionRequest =
            GraphChatInterpretationCorrectionRequest(
                binding: binding,
                selection: selection
            )

        #expect(
            editorSnapshot.validationState(
                for: correctionRequest,
                currentArtifactSessionID:
                    origin.artifactSessionID,
                currentCheckpoint:
                    currentCheckpoint,
                graphIsLocked: false
            ) == .ready
        )

        let correctionEvents =
            await GraphChatProviderTestSupport
                .collect(
                    await runtime.orchestrator
                        .streamCorrectedIntent(
                            correctionRequest
                        )
                )
        let correctedAnswer =
            try completedAnswer(
                correctionEvents
            )
        let correctedInterpretation =
            try #require(
                correctedAnswer.interpretation
            )
        let correctedOrigin = try #require(
            correctedInterpretation
                .correctionOrigin
        )
        guard
            case .field(let correctedSortField)? =
                correctedInterpretation
                    .sorting.first?.key
        else {
            Issue.record(
                "Expected a freshly rebuilt field-sort interpretation."
            )
            return
        }
        let correctedArtifact =
            try await resolvedArtifact(
                answer: correctedAnswer,
                runtime: runtime,
                graphScope: graphScope,
                chatScope: chatScope
            )
        guard
            case .resultList(let correctedList) =
                correctedArtifact.payload
        else {
            Issue.record(
                "Expected the corrected due-date-sorted result list."
            )
            return
        }

        let oldPresentation =
            await runtime.orchestrator
                .resolveAnswerPresentation(
                    artifactIDs:
                        initialAnswer.artifactIDs,
                    evidence:
                        initialAnswer.evidence,
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        let finalState = try #require(
            await runtime.orchestrator
                .conversationStateSnapshot()
        )
        let finalResult = try #require(
            finalState.resultContexts.last
        )
        let finalNodes =
            finalResult.references.compactMap {
                reference
                -> NodeRefKey? in
                if case .node(let node) =
                    reference.reference {
                    return node
                }
                return nil
            }

        let contextWithoutCurrent =
            GraphChatConversationContextBuilder()
                .makeSnapshot(
                    from: finalState.snapshot
                )
        let currentResolution =
            try await runtime.referenceResolver
                .resolveScope(
                    .latestResults,
                    in:
                        contextWithoutCurrent,
                    expectedGraphScope:
                        graphScope,
                    expectedChatScope:
                        chatScope
                )
        guard
            case .resolved(let currentScope) =
                currentResolution
        else {
            Issue.record(
                "Expected the replacement result set to resolve as CURRENT."
            )
            return
        }
        let contextWithCurrent =
            GraphChatConversationContextBuilder()
                .makeSnapshot(
                    from: finalState.snapshot,
                    currentResolvedScope:
                        currentScope
                )
        let current = try #require(
            contextWithCurrent.alias("CURRENT")
        )
        guard
            case .resultSet(
                let currentResultID,
                let currentNodes,
                _
            ) = current.target
        else {
            Issue.record(
                "Expected CURRENT to contain only the replacement result set."
            )
            return
        }

        let provider =
            await runtime.provider.snapshot()
        let interpreterSnapshot =
            await interpreter.snapshot()
        let semanticMetrics =
            await runtime.observability
                .semanticMetrics()
        let interpretationMetrics =
            await runtime.observability
                .interpretationMetrics()
        let interpretationEvents =
            interpretationMetrics.map(\.event)
        let correctionLifecycle =
            interpretationEvents.filter {
                [
                    GraphChatIntentInterpretationLifecycleEvent
                        .correctionValidated,
                    .localCorrectionRerunStarted,
                    .localCorrectionRerunCommitted,
                    .localCorrectionRerunRolledBack,
                ].contains($0)
            }

        #expect(
            correctedList.rows.map(\.primaryText)
                == [
                    "Apollo",
                    "Carina",
                    "Borealis",
                ]
        )
        #expect(correctedInterpretation != interpretation)
        #expect(
            correctedInterpretation
                .turnBinding.requestID
                != interpretation
                    .turnBinding.requestID
        )
        #expect(
            correctedSortField.id
                == fixture.dueField.id
        )
        #expect(
            correctedInterpretation.sorting
                .first?.direction
                == .ascending
        )
        #expect(
            correctedOrigin.matches(
                correctedInterpretation
            )
        )
        #expect(
            correctedOrigin.adaptation
                .readPlan.version
                == .current
        )
        #expect(
            correctedOrigin.adaptation
                .readPlan.binding.requestID
                == correctedInterpretation
                    .turnBinding.requestID
        )
        #expect(
            correctedOrigin.adaptation
                .readPlan
                != origin.adaptation
                    .readPlan
        )
        #expect(
            finalState.lastValidatedQueryPlan?
                .sorting == [
                    GraphValidatedQuerySort(
                        key: .field(
                            fixture.dueField.id
                        ),
                        direction: .ascending
                    ),
                ]
        )
        #expect(finalState.turnContexts.count == 1)
        #expect(finalState.resultContexts.count == 1)
        #expect(finalResult.id != initialResultID)
        #expect(
            correctedAnswer.artifactIDs.count
                == 1
        )
        #expect(
            correctedAnswer.artifactIDs
                != initialAnswer.artifactIDs
        )
        #expect(oldPresentation.artifacts.isEmpty)
        #expect(
            initialAnswer.artifactIDs
                .allSatisfy {
                    oldPresentation
                        .unavailableArtifactReasons[
                            $0
                        ] == .notRegisteredOrInvalidated
                }
        )
        let apollo = try #require(
            fixture.openNodesByName["Apollo"]
        )
        let carina = try #require(
            fixture.openNodesByName["Carina"]
        )
        let borealis = try #require(
            fixture.openNodesByName["Borealis"]
        )

        #expect(currentResultID == finalResult.id)
        #expect(currentNodes == finalNodes)
        #expect(
            currentNodes == [
                apollo,
                carina,
                borealis,
            ]
        )
        #expect(
            currentNodes != [
                apollo,
                borealis,
                carina,
            ]
        )
        #expect(interpreterSnapshot.requests.count == 1)
        #expect(provider.createdSessions.isEmpty)
        #expect(provider.streamedSessions.isEmpty)
        #expect(
            semanticMetrics.reduce(0) {
                $0 + $1.interpreterCallCount
            } == 1
        )
        #expect(
            semanticMetrics.reduce(0) {
                $0 + $1.answerProviderCallCount
            } == 0
        )
        #expect(
            correctionLifecycle == [
                .correctionValidated,
                .localCorrectionRerunStarted,
                .localCorrectionRerunCommitted,
            ]
        )
        #expect(
            terminalEventCount(initialEvents)
                == 1
        )
        #expect(
            terminalEventCount(correctionEvents)
                == 1
        )
    }

    private struct QueryIntentFixture {
        let graph: MetaGraph
        let entity: MetaEntity
        let dueField:
            MetaDetailFieldDefinition
        let openNodesByName:
            [String: NodeRefKey]
        let closedOverdueNode: NodeRefKey
        let foreignOverdueNode: NodeRefKey
    }

    @MainActor
    private func makeQueryIntentFixture(
        _ builder: BrainMeshFixtureBuilder
    ) -> QueryIntentFixture {
        let graph = builder.makeGraph(
            name: "Portfolio"
        )
        let entity = builder.makeEntity(
            name: "Projekte",
            in: graph
        )
        let status = builder.makeDetailField(
            owner: entity,
            name: "Status",
            type: .singleChoice,
            sortIndex: 0,
            options:
                ["Offen", "Fertig"],
            isPinned: true
        )
        let due = builder.makeDetailField(
            owner: entity,
            name: "Fälligkeitsdatum",
            type: .date,
            sortIndex: 1,
            isPinned: true
        )
        let budget = builder.makeDetailField(
            owner: entity,
            name: "Budget",
            type: .numberDouble,
            sortIndex: 2,
            unit: "EUR"
        )
        let important = builder.makeDetailField(
            owner: entity,
            name: "Wichtig",
            type: .toggle,
            sortIndex: 3
        )
        let timeZone = TimeZone(
            identifier: "Europe/Berlin"
        )!
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(
            for:
                Date(
                    timeIntervalSince1970:
                        1_768_413_600
                )
        )
        let rows: [(
            name: String,
            status: String,
            dueOffset: Int,
            budget: Double,
            important: Bool
        )] = [
            ("Apollo", "Offen", -3, 1_000, true),
            ("Carina", "Offen", -1, 750, true),
            ("Borealis", "Offen", 2, 2_000, false),
            ("Dormant", "Fertig", -4, 300, true),
        ]
        var attributes: [String: MetaAttribute] =
            [:]
        for row in rows {
            let attribute =
                builder.makeAttribute(
                    name: row.name,
                    owner: entity
                )
            attributes[row.name] = attribute
            builder.makeDetailValue(
                attribute: attribute,
                field: status,
                stringValue: row.status
            )
            builder.makeDetailValue(
                attribute: attribute,
                field: due,
                dateValue:
                    calendar.date(
                        byAdding: .day,
                        value: row.dueOffset,
                        to: dayStart
                    )!
            )
            builder.makeDetailValue(
                attribute: attribute,
                field: budget,
                doubleValue: row.budget
            )
            builder.makeDetailValue(
                attribute: attribute,
                field: important,
                boolValue: row.important
            )
        }

        let foreignGraph = builder.makeGraph(
            name: "Archiv"
        )
        let foreignEntity = builder.makeEntity(
            name: "Projekte",
            in: foreignGraph
        )
        let foreignStatus =
            builder.makeDetailField(
                owner: foreignEntity,
                name: "Status",
                type: .singleChoice,
                sortIndex: 0,
                options: ["Offen", "Fertig"]
            )
        let foreignDue = builder.makeDetailField(
            owner: foreignEntity,
            name: "Fälligkeitsdatum",
            type: .date,
            sortIndex: 1
        )
        let foreign = builder.makeAttribute(
            name: "Fremdprojekt",
            owner: foreignEntity
        )
        builder.makeDetailValue(
            attribute: foreign,
            field: foreignStatus,
            stringValue: "Offen"
        )
        builder.makeDetailValue(
            attribute: foreign,
            field: foreignDue,
            dateValue:
                calendar.date(
                    byAdding: .day,
                    value: -10,
                    to: dayStart
                )!
        )

        return QueryIntentFixture(
            graph: graph,
            entity: entity,
            dueField: due,
            openNodesByName:
                Dictionary(
                    uniqueKeysWithValues: [
                        "Apollo",
                        "Carina",
                        "Borealis",
                    ].map {
                        (
                            $0,
                            NodeRefKey(
                                kind: .attribute,
                                id:
                                    attributes[$0]!
                                        .id
                            )
                        )
                    }
                ),
            closedOverdueNode:
                NodeRefKey(
                    kind: .attribute,
                    id: attributes["Dormant"]!.id
                ),
            foreignOverdueNode:
                NodeRefKey(
                    kind: .attribute,
                    id: foreign.id
                )
        )
    }

    private func resolvedArtifact(
        answer: GraphChatAnswer,
        runtime: Runtime,
        graphScope: GraphScope,
        chatScope: GraphChatScope
    ) async throws -> GraphChatAnswerArtifact {
        let presentation =
            await runtime.orchestrator
                .resolveAnswerPresentation(
                    artifactIDs:
                        answer.artifactIDs,
                    evidence: answer.evidence,
                    graphScope: graphScope,
                    chatScope: chatScope
                )
        return try #require(
            presentation.artifacts.first?
                .artifact
        )
    }

    private struct Runtime {
        let orchestrator: GraphChatOrchestrator
        let provider: FakeGraphChatModelProvider
        let searchExecutor:
            SemanticRecordingSearchExecutor
        let observability:
            SemanticIntentObservabilityRecorder
        let schemaService: GraphSchemaService
        let referenceResolver:
            GraphChatConversationReferenceResolver
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
        let referenceResolver =
            GraphChatConversationReferenceResolver(
                revalidator:
                    GraphChatRepositoryConversationReferenceRevalidator(
                        repository: repository,
                        queryEngine: queryEngine
                    )
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
                referenceResolver:
                    referenceResolver,
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
            observability: observability,
            schemaService: schemaService,
            referenceResolver:
                referenceResolver
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
            case .failure(let error):
                return error.message
            case .started, .toolActivity,
                .cancelled:
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

private actor SemanticBlockingQueryExecutor:
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
        let currentWaiters = waiters
        waiters.removeAll()
        for waiter in currentWaiters {
            waiter.resume()
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
            continuation in
            waiters.append(continuation)
        }
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

    func localMetrics()
        -> [GraphChatLocalIntentMetric]
    {
        events.compactMap {
            guard case .localIntent(
                let metric
            ) = $0 else {
                return nil
            }
            return metric
        }
    }

    func interpretationMetrics()
        -> [GraphChatIntentInterpretationMetric]
    {
        events.compactMap {
            guard
                case .intentInterpretation(
                    let metric
                ) = $0
            else {
                return nil
            }
            return metric
        }
    }

    func plannerMetrics()
        -> [GraphChatTypedPlannerMetric]
    {
        events.compactMap {
            guard
                case .typedPlanner(
                    let metric
                ) = $0
            else {
                return nil
            }
            return metric
        }
    }
}
