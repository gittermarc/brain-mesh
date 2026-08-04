import Combine
import Foundation
import Testing
@testable import BrainMesh

@Suite("Graph Chat interaction hotpath")
@MainActor
struct GraphChatInteractionHotpathTests {
    @Test
    func oneHundredDraftChangesAndRepeatedReadsDoNotRebuildProductionSuggestions() async throws {
        let context = makeSuggestionContext()
        let scope = GraphChatScope.entireGraph(
            context.graphScope
        )
        let events = SuggestionsEventCounter()
        let schemaProvider = CountingSchemaProvider(
            context: context
        )
        let indexProvider = CountingIndexProvider()
        let coordinator = GraphChatLaunchCoordinator()
        coordinator.launch(scope: scope)
        let draftCheckpoints = DraftCheckpointRecorder()
        let coordinatorPublications = LockedIntCounter()
        let coordinatorObservation = coordinator.objectWillChange
            .sink {
                coordinatorPublications.increment()
            }
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .partialAnswer("Belegbare Teilantwort"),
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Belegbare Antwort"
                            )
                        ),
                    ]
                ),
            ]
        )
        let viewModel = GraphChatViewModel(
            graphScope: context.graphScope,
            chatScope: scope,
            graphName: context.snapshot.graphName,
            launchContext: .graph(name: context.snapshot.graphName),
            interfaceLanguage: .german,
            interfaceLocaleIdentifier: "de_DE",
            orchestrator: orchestrator,
            schemaProvider: schemaProvider,
            availabilityProvider:
                GraphChatUIFakeAvailabilityProvider(
                    value: .available
                ),
            indexStatusProvider: indexProvider,
            historyStore: InMemoryGraphChatHistoryStore(),
            navigationActions: .disabled,
            draftChangeHandler: { value in
                draftCheckpoints.record(value)
                coordinator.updateDraft(value, for: scope)
            },
            suggestionsSnapshotBuilder:
                GraphChatProductionSuggestionsSnapshotBuilder(
                    instrumentation:
                        GraphChatSuggestionsInstrumentation {
                            events.record($0)
                        }
                )
        )

        await viewModel.load()

        let initialSnapshot = try #require(
            viewModel.suggestionsSnapshot
        )
        let initialEvents = events.snapshot()
        let initialSchemaLoads = await schemaProvider.loadCount()
        let initialIndexChecks = await indexProvider.readinessCheckCount()
        #expect(initialSchemaLoads == 1)
        #expect(initialIndexChecks == 1)
        #expect(initialEvents[.snapshotBuild] == 1)
        #expect(initialEvents[.mentionCatalogBuild] == 1)
        #expect(
            initialEvents.count(matching: {
                if case .capabilityValidation(_) = $0 {
                    return true
                }
                return false
            }) > 0
        )
        #expect(
            initialEvents.count(matching: {
                if case .intentCompiler(_) = $0 {
                    return true
                }
                return false
            }) > 0
        )
        #expect(
            initialEvents.count(matching: {
                if case .readPlanValidation(_) = $0 {
                    return true
                }
                return false
            }) > 0
        )
        #expect(initialSnapshot.suggestions.isEmpty == false)
        let viewModelPublications = LockedIntCounter()
        let viewModelObservation = viewModel.objectWillChange
            .sink {
                viewModelPublications.increment()
            }

        for index in 0..<100 {
            switch index {
            case 97:
                viewModel.setComposerText("")
            case 98:
                viewModel.setComposerText("Teilweise")
            case 99:
                viewModel.setComposerText("")
            default:
                viewModel.setComposerText("Draft \(index)")
            }
            _ = viewModel.composerState
            _ = viewModel.suggestions
            _ = viewModel.suggestionsSnapshot
        }

        #expect(events.snapshot() == initialEvents)
        #expect(await schemaProvider.loadCount() == initialSchemaLoads)
        #expect(
            await indexProvider.readinessCheckCount()
                == initialIndexChecks
        )
        #expect(draftCheckpoints.values.isEmpty)
        #expect(coordinatorPublications.value == 0)
        #expect(viewModelPublications.value == 0)

        for _ in 0..<20 {
            await viewModel.refreshSuggestionsSnapshotIfNeeded()
            _ = viewModel.suggestions
        }
        #expect(events.snapshot() == initialEvents)
        #expect(viewModel.suggestionsSnapshot == initialSnapshot)
        #expect(viewModelPublications.value == 0)

        let presentationID = UUID()
        viewModel.presentationDidAppear(presentationID)
        viewModel.setComposerText("Neuester Draft beim Verlassen")
        viewModel.presentationDidDisappear(presentationID)
        #expect(
            coordinator.draft(for: scope)
                == "Neuester Draft beim Verlassen"
        )
        #expect(draftCheckpoints.values == [
            "Neuester Draft beim Verlassen",
        ])

        viewModel.presentationDidAppear(presentationID)
        viewModel.setComposerText("Neuester Draft beim Absenden")
        viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating == false
                && viewModel.messages.count == 2
        }
        #expect(
            await orchestrator.snapshot().questions
                == ["Neuester Draft beim Absenden"]
        )
        #expect(
            Array(draftCheckpoints.values.suffix(2)) == [
                "Neuester Draft beim Absenden",
                "",
            ]
        )
        #expect(coordinator.draft(for: scope) == nil)
        #expect(events.snapshot() == initialEvents)
        #expect(await schemaProvider.loadCount() == initialSchemaLoads)
        #expect(
            await indexProvider.readinessCheckCount()
                == initialIndexChecks
        )

        let catalog = GraphMentionCatalog(
            schemaContext: context
        )
        let validator = GraphChatCapabilityQuestionValidator()
        for suggestion in initialSnapshot.suggestions {
            let capability = try #require(
                GraphChatCapabilityCatalog.capability(
                    withID: suggestion.capabilityID
                )
            )
            #expect(
                validator.validate(
                    question: suggestion.prompt,
                    capability: capability,
                    schemaContext: context,
                    chatScope: scope,
                    language: .german,
                    mentionCatalog: catalog
                ) == suggestion.validation
            )
        }

        coordinator.updateDraft("identisch", for: scope)
        let publicationsAfterFirstUpdate =
            coordinatorPublications.value
        coordinator.updateDraft("identisch", for: scope)
        #expect(
            coordinatorPublications.value
                == publicationsAfterFirstUpdate
        )
        _ = coordinatorObservation
        _ = viewModelObservation
    }

    @Test
    func exactIdentityChangesInvalidateExactlyOnce() async throws {
        let builder = CountingSnapshotBuilder()
        let controller = GraphChatSuggestionsSnapshotController(
            builder: builder
        )
        let baseContext = makeSuggestionContext()
        let base = request(
            schema: baseContext,
            scope: .entireGraph(baseContext.graphScope),
            launchContext: .graph(name: "Test Graph")
        )

        try await assertSingleBuild(
            base,
            controller: controller,
            builder: builder
        )
        for _ in 0..<25 {
            _ = try await controller.snapshot(for: base)
        }
        #expect(await builder.buildCount() == 1)

        let otherGraphContext = makeSuggestionContext(
            graphID: GraphChatTestSupport.otherGraphID
        )
        let changedGraph = request(
            schema: otherGraphContext,
            scope: .entireGraph(otherGraphContext.graphScope),
            launchContext: .graph(name: "Test Graph")
        )
        let changedSchemaContext = makeSuggestionContext(
            choiceOptions: ["Neu", "Erledigt"]
        )
        let changedSchema = request(
            schema: changedSchemaContext,
            scope: .entireGraph(changedSchemaContext.graphScope),
            launchContext: .graph(name: "Test Graph")
        )
        let changedScope = request(
            schema: baseContext,
            scope: .entity(
                GraphChatTestSupport.projectEntityID,
                in: baseContext.graphScope
            ),
            launchContext: .graph(name: "Test Graph")
        )
        let changedLaunch = request(
            schema: baseContext,
            scope: .entireGraph(baseContext.graphScope),
            launchContext: .graph(name: "Anderer Launch")
        )
        let changedLocale = request(
            schema: baseContext,
            scope: .entireGraph(baseContext.graphScope),
            launchContext: .graph(name: "Test Graph"),
            localeIdentifier: "de_AT"
        )
        let changedLanguage = request(
            schema: baseContext,
            scope: .entireGraph(baseContext.graphScope),
            launchContext: .graph(name: "Test Graph"),
            language: .english,
            localeIdentifier: "en_GB"
        )
        let changedTools = request(
            schema: baseContext,
            scope: .entireGraph(baseContext.graphScope),
            launchContext: .graph(name: "Test Graph"),
            availableTools: [.queryDetailValues]
        )
        let changedModelAvailability = request(
            schema: baseContext,
            scope: .entireGraph(baseContext.graphScope),
            launchContext: .graph(name: "Test Graph"),
            modelAvailability:
                .unavailable(reason: .modelNotReady)
        )

        for changedRequest in [
            changedGraph,
            changedSchema,
            changedScope,
            changedLaunch,
            changedLocale,
            changedLanguage,
            changedTools,
            changedModelAvailability,
        ] {
            try await assertSingleBuild(
                changedRequest,
                controller: controller,
                builder: builder
            )
        }
        #expect(await builder.buildCount() == 9)
    }

    @Test
    func cancelledOrStaleBuildCannotPublishIntoNewIdentity() async throws {
        let gate = SnapshotBuildGate()
        let controller = GraphChatSuggestionsSnapshotController(
            builder: GatedSnapshotBuilder(gate: gate)
        )
        let context = makeSuggestionContext()
        let staleRequest = request(
            schema: context,
            scope: .entireGraph(context.graphScope),
            launchContext: .graph(name: "Alt")
        )
        let currentRequest = request(
            schema: context,
            scope: .entireGraph(context.graphScope),
            launchContext: .graph(name: "Neu")
        )

        let staleTask = Task {
            try await controller.snapshot(for: staleRequest)
        }
        await gate.waitUntilEntered(staleRequest.key)

        let currentTask = Task {
            try await controller.snapshot(for: currentRequest)
        }
        await gate.waitUntilEntered(currentRequest.key)
        await gate.release(currentRequest.key)
        let currentSnapshot = try await currentTask.value
        #expect(currentSnapshot.key == currentRequest.key)

        await gate.release(staleRequest.key)
        do {
            _ = try await staleTask.value
            Issue.record("A stale suggestions build was published.")
        } catch is CancellationError {
            // Expected: the builder deliberately ignored cancellation, while
            // the controller still rejected its stale result atomically.
        }

        #expect(
            controller.cachedSnapshot(for: currentRequest.key)
                == currentSnapshot
        )
        #expect(
            controller.cachedSnapshot(for: staleRequest.key)
                == nil
        )
    }

    private func assertSingleBuild(
        _ request: GraphChatSuggestionsSnapshotRequest,
        controller: GraphChatSuggestionsSnapshotController,
        builder: CountingSnapshotBuilder
    ) async throws {
        let countBefore = await builder.buildCount()
        let first = try await controller.snapshot(for: request)
        let second = try await controller.snapshot(for: request)
        #expect(first == second)
        #expect(await builder.buildCount() == countBefore + 1)
    }

    private func request(
        schema: GraphSchemaContext,
        scope: GraphChatScope,
        launchContext: GraphChatLaunchContext,
        language: GraphChatResponseLanguage = .german,
        localeIdentifier: String = "de_DE",
        availableTools: Set<GraphChatToolKind> =
            Set(GraphChatToolKind.allCases),
        modelAvailability:
            GraphChatAvailabilityPresentationState = .available
    ) -> GraphChatSuggestionsSnapshotRequest {
        GraphChatSuggestionsSnapshotRequest(
            context: GraphChatSuggestionContext(
                schema: schema,
                scope: scope,
                launchContext: launchContext,
                availableTools: availableTools,
                modelAvailability: modelAvailability,
                language: language,
                localeIdentifier: localeIdentifier
            )
        )
    }

    private func makeSuggestionContext(
        graphID: UUID = GraphChatTestSupport.graphID,
        choiceOptions: [String] = ["Offen", "In Arbeit", "Fertig"]
    ) -> GraphSchemaContext {
        let base = GraphChatTestSupport.makeSchemaContext(
            graphID: graphID,
            choiceOptions: choiceOptions
        )
        let aliases = base.foundationalAliases
        let projectNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.projectAttributeID
        )
        let personNode = NodeRefKey(
            kind: .attribute,
            id: GraphChatTestSupport.personAttributeID
        )
        let completeAliases = GraphSchemaAliasMap(
            graphScope: base.graphScope,
            entitiesByAlias: aliases.entitiesByAlias,
            fieldsByAlias: aliases.fieldsByAlias,
            nodeEntityIDs: aliases.nodeEntityIDs,
            nodesByKey: [
                projectNode: GraphSchemaNodeResolution(
                    node: projectNode,
                    ownerEntityID:
                        GraphChatTestSupport.projectEntityID,
                    displayName: "Projekt Atlas"
                ),
                personNode: GraphSchemaNodeResolution(
                    node: personNode,
                    ownerEntityID:
                        GraphChatTestSupport.personEntityID,
                    displayName: "Ada Lovelace"
                ),
            ]
        )
        return GraphSchemaContext(
            graphScope: base.graphScope,
            snapshot: base.snapshot,
            aliases: completeAliases,
            foundationalAliases: completeAliases
        )
    }
}

private final class SuggestionsEventCounter:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values:
        [GraphChatSuggestionsInstrumentationEvent: Int] = [:]

    func record(
        _ event: GraphChatSuggestionsInstrumentationEvent
    ) {
        lock.lock()
        values[event, default: 0] += 1
        lock.unlock()
    }

    func snapshot()
        -> [GraphChatSuggestionsInstrumentationEvent: Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class LockedIntCounter:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }
}

private extension Dictionary
where Key == GraphChatSuggestionsInstrumentationEvent,
      Value == Int
{
    func count(
        matching predicate:
            (GraphChatSuggestionsInstrumentationEvent) -> Bool
    ) -> Int {
        reduce(into: 0) { result, element in
            if predicate(element.key) {
                result += element.value
            }
        }
    }
}

@MainActor
private final class DraftCheckpointRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}

private actor CountingSchemaProvider:
    GraphSchemaSnapshotProviding
{
    private let context: GraphSchemaContext
    private var count = 0

    init(context: GraphSchemaContext) {
        self.context = context
    }

    func makeSnapshot(
        in scope: GraphScope,
        exampleFieldIDs: Set<UUID>
    ) async throws -> GraphSchemaContext {
        count += 1
        guard scope == context.graphScope else {
            throw GraphChatError(
                code: .schemaUnavailable,
                message: "Unexpected graph scope."
            )
        }
        return context
    }

    func loadCount() -> Int {
        count
    }
}

private actor CountingIndexProvider:
    GraphChatIndexStatusProviding
{
    private var count = 0

    func presentationState(
        for scope: GraphScope
    ) async -> GraphChatIndexPresentationState {
        count += 1
        return .ready(documentCount: 12)
    }

    func readinessCheckCount() -> Int {
        count
    }
}

private actor CountingSnapshotBuilder:
    GraphChatSuggestionsSnapshotBuilding
{
    private var count = 0

    func makeSnapshot(
        for request: GraphChatSuggestionsSnapshotRequest
    ) async throws -> GraphChatSuggestionsSnapshot {
        count += 1
        return GraphChatSuggestionsSnapshot(
            key: request.key,
            suggestions: []
        )
    }

    func buildCount() -> Int {
        count
    }
}

private nonisolated struct GatedSnapshotBuilder:
    GraphChatSuggestionsSnapshotBuilding,
    Sendable
{
    let gate: SnapshotBuildGate

    func makeSnapshot(
        for request: GraphChatSuggestionsSnapshotRequest
    ) async throws -> GraphChatSuggestionsSnapshot {
        await gate.enterAndWait(request.key)
        return GraphChatSuggestionsSnapshot(
            key: request.key,
            suggestions: []
        )
    }
}

private actor SnapshotBuildGate {
    private var entered = Set<GraphChatSuggestionsSnapshotKey>()
    private var entryWaiters: [
        GraphChatSuggestionsSnapshotKey:
            [CheckedContinuation<Void, Never>]
    ] = [:]
    private var releaseContinuations: [
        GraphChatSuggestionsSnapshotKey:
            CheckedContinuation<Void, Never>
    ] = [:]
    private var released = Set<GraphChatSuggestionsSnapshotKey>()

    func enterAndWait(
        _ key: GraphChatSuggestionsSnapshotKey
    ) async {
        entered.insert(key)
        let waiters = entryWaiters.removeValue(forKey: key) ?? []
        for waiter in waiters {
            waiter.resume()
        }
        guard released.remove(key) == nil else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseContinuations[key] = continuation
        }
    }

    func waitUntilEntered(
        _ key: GraphChatSuggestionsSnapshotKey
    ) async {
        guard entered.contains(key) == false else {
            return
        }
        await withCheckedContinuation { continuation in
            entryWaiters[key, default: []].append(continuation)
        }
    }

    func release(
        _ key: GraphChatSuggestionsSnapshotKey
    ) {
        if let continuation = releaseContinuations
            .removeValue(forKey: key) {
            continuation.resume()
        } else {
            released.insert(key)
        }
    }
}
