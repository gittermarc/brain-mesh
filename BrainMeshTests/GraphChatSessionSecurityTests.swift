import Foundation
import Testing

@testable import BrainMesh

@MainActor
struct GraphChatSessionSecurityTests {
    @Test
    func evidenceRegistryCanBeExplicitlyClearedDuringSessionCleanup() async throws {
        let graphID = UUID()
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let evidence = GraphEvidence(
            sourceReference: GraphSourceReference(
                graphID: graphID,
                sourceKind: .entity,
                sourceID: UUID()
            ),
            summary: "Sensible Evidence"
        )
        let registry = GraphChatEvidenceRegistry(scope: scope)

        let appliedFilter = GraphChatAppliedFilter(
            fieldName: "Status",
            operationDescription: "ist gleich",
            valueDescription: "Offen"
        )
        try await registry.register([evidence])
        try await registry.registerAppliedFilters([appliedFilter, appliedFilter])
        #expect(await registry.contains(evidence.id))
        #expect(await registry.filtersForAnswer().count == 1)

        await registry.removeAll()

        #expect(await registry.contains(evidence.id) == false)
        #expect(await registry.snapshotForTesting().isEmpty)
        #expect(await registry.filtersForAnswer().isEmpty)
    }

    @Test
    func executionGatePreventsModelInvocationWithoutAuthorizedProScope() async {
        let graphID = UUID()
        let graphScope = GraphScope(graphID: graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let base = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Authorized"
                            )
                        )
                    ]
                )
            ]
        )
        let gate = GraphChatExecutionGate()
        let protected = AccessControlledGraphChatOrchestrator(
            base: base,
            gate: gate
        )

        let deniedStream = await protected.streamAnswer(
            question: "Denied",
            graphScope: graphScope,
            chatScope: chatScope
        )
        var deniedFailure: GraphChatError?
        for await event in deniedStream {
            if case .failure(let error) = event {
                deniedFailure = error
            }
        }

        #expect(deniedFailure?.code == .unavailable)
        #expect(await base.snapshot().questions.isEmpty)

        gate.update(
            GraphChatExecutionAuthorization(
                activeGraphID: graphID,
                authorizedScope: chatScope,
                hasProEntitlement: true,
                isGraphUnlocked: true
            )
        )
        let allowedStream = await protected.streamAnswer(
            question: "Allowed",
            graphScope: graphScope,
            chatScope: chatScope
        )
        for await _ in allowedStream {}

        #expect(await base.snapshot().questions == ["Allowed"])
    }

    @Test
    func freeAndUnknownAccessCannotStartGeneration() async {
        let graphID = UUID()
        let setup = makeSessionStore(graphID: graphID, scripts: [])
        let request = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID))
        )
        let viewModel = setup.store.viewModel(
            request: request,
            graphName: "Testgraph",
            navigationActions: .disabled
        )
        await viewModel.load()

        await setup.store.synchronizeAccess(
            activeGraphID: graphID,
            scope: request.scope,
            hasProEntitlement: false,
            isGraphUnlocked: true
        )
        viewModel.setComposerText("Darf nicht starten")

        #expect(viewModel.canSend == false)
        viewModel.send()
        #expect(viewModel.messages.isEmpty)
        #expect(await setup.orchestrator.snapshot().questions.isEmpty)
    }

    @Test
    func scopeChangeDiscardsRuntimeBeforeNewScopeIsAuthorized() async {
        let graphID = UUID()
        let setup = makeSessionStore(graphID: graphID, scripts: [])
        var derivedStateCleanupCount = 0
        let wholeGraphRequest = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            prefilledQuestion: "Whole Graph"
        )
        await setup.store.synchronizeAccess(
            activeGraphID: graphID,
            scope: wholeGraphRequest.scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let oldViewModel = setup.store.viewModel(
            request: wholeGraphRequest,
            graphName: "Testgraph",
            navigationActions: .disabled,
            sessionDerivedStateDidClear: {
                derivedStateCleanupCount += 1
            }
        )
        let nodeScope = GraphChatScope.node(
            NodeRefKey(kind: .entity, id: UUID()),
            in: GraphScope(graphID: graphID)
        )
        let nodeRequest = GraphChatLaunchRequest(
            scope: nodeScope,
            prefilledQuestion: "Node-Frage"
        )

        let newViewModel = setup.store.viewModel(
            request: nodeRequest,
            graphName: "Testgraph",
            navigationActions: .disabled,
            sessionDerivedStateDidClear: {
                derivedStateCleanupCount += 1
            }
        )

        #expect(derivedStateCleanupCount == 1)
        #expect(oldViewModel.composerState.text.isEmpty)
        #expect(newViewModel.composerState.text == "Node-Frage")
        #expect(setup.store.isGenerationAuthorized == false)

        await setup.store.synchronizeAccess(
            activeGraphID: graphID,
            scope: nodeScope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )

        #expect(setup.store.isGenerationAuthorized)
        let snapshot = await setup.orchestrator.snapshot()
        #expect(snapshot.discardCount > 0)
        #expect(snapshot.discardReasons.last == .scopeChanged)
    }

    @Test
    func entitlementRevocationImmediatelyBlocksAndClearsChatState() async {
        let graphID = UUID()
        let setup = makeSessionStore(graphID: graphID, scripts: [])
        let request = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            prefilledQuestion: "Sensible Frage"
        )
        await setup.store.synchronizeAccess(
            activeGraphID: graphID,
            scope: request.scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let viewModel = setup.store.viewModel(
            request: request,
            graphName: "Testgraph",
            navigationActions: .disabled
        )

        #expect(viewModel.composerState.text == "Sensible Frage")
        #expect(setup.store.isGenerationAuthorized)

        setup.store.handleEntitlementRevocation()

        #expect(viewModel.composerState.text.isEmpty)
        #expect(viewModel.messages.isEmpty)
        #expect(setup.store.isGenerationAuthorized == false)
        let snapshot = await waitForDiscard(on: setup.orchestrator)
        #expect(snapshot.discardCount > 0)
        #expect(snapshot.discardReasons.last == .accessRevoked)
    }

    @Test
    func lockingForeignGraphDoesNotDiscardActiveGraphSession() async {
        let graphID = UUID()
        let setup = makeSessionStore(graphID: graphID, scripts: [])
        let request = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID)),
            prefilledQuestion: "Aktive Frage"
        )
        await setup.store.synchronizeAccess(
            activeGraphID: graphID,
            scope: request.scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let viewModel = setup.store.viewModel(
            request: request,
            graphName: "Testgraph",
            navigationActions: .disabled
        )

        setup.store.handleSecurityLock(graphID: UUID())

        #expect(viewModel.composerState.text == "Aktive Frage")
        #expect(setup.store.isGenerationAuthorized)
        #expect(await setup.orchestrator.snapshot().discardCount == 0)

        setup.store.handleSecurityLock(graphID: graphID)

        #expect(viewModel.composerState.text.isEmpty)
        #expect(setup.store.isGenerationAuthorized == false)
        let lockedSnapshot = await waitForDiscard(on: setup.orchestrator)
        #expect(lockedSnapshot.discardCount > 0)
        #expect(lockedSnapshot.discardReasons.last == .graphLocked)
    }

    @Test
    func activeGraphChangeCancelsGenerationDiscardsSessionAndRemovesVisibleData() async {
        let graphID = UUID()
        let setup = makeSessionStore(
            graphID: graphID,
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .partialAnswer("Sensible Teilantwort"),
                    ],
                    waitsForCancellation: true
                )
            ]
        )
        let request = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID))
        )
        await setup.store.synchronizeAccess(
            activeGraphID: graphID,
            scope: request.scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let viewModel = setup.store.viewModel(
            request: request,
            graphName: "Testgraph",
            navigationActions: .disabled
        )
        await viewModel.load()
        viewModel.setComposerText("Sensible Frage")
        viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating && viewModel.messages.count == 2
        }

        setup.store.handleActiveGraphChange()

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.composerState.text.isEmpty)
        #expect(setup.store.isGenerationAuthorized == false)
        let snapshot = await waitForDiscard(on: setup.orchestrator)
        #expect(snapshot.cancellationCount > 0)
        #expect(snapshot.discardCount > 0)
        #expect(snapshot.discardReasons.last == .graphChanged)
    }

    @Test
    func activeGraphChangeCancelsInFlightIndexPreparation() async {
        let graphScope = GraphScope(graphID: UUID())
        let indexProvider = GraphChatBlockingIndexProbe()
        let bus = GraphMutationEventBus()
        let store = GraphChatSessionStore(
            baseOrchestrator: GraphChatUIFakeOrchestrator(scripts: []),
            availabilityProvider: GraphChatUIFakeAvailabilityProvider(value: .available),
            schemaProvider: GraphChatUIFakeSchemaProvider(
                contexts: [
                    GraphChatTestSupport.makeSchemaContext(
                        graphID: graphScope.graphID
                    )
                ]
            ),
            indexStatusProvider: indexProvider,
            mutationSubscriber: bus
        )
        let refresh = Task { @MainActor in
            await store.refreshIndex(
                for: graphScope,
                prepareIfNeeded: true
            )
        }
        for _ in 0..<2_000 {
            if await indexProvider.hasStarted {
                break
            }
            await Task.yield()
        }

        store.handleActiveGraphChange()
        await refresh.value

        #expect(await indexProvider.hasStarted)
        #expect(await indexProvider.cancellationCount == 1)
        await bus.finish()
    }

    @Test
    func graphLockAndBackgroundSecurityCleanupHideSensitiveState() async {
        let graphID = UUID()
        let setup = makeSessionStore(
            graphID: graphID,
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .completed(
                            GraphChatUITestSupport.finalAnswer(
                                directAnswer: "Sensible Antwort"
                            )
                        )
                    ]
                )
            ]
        )
        let request = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID))
        )
        await setup.store.synchronizeAccess(
            activeGraphID: graphID,
            scope: request.scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let viewModel = setup.store.viewModel(
            request: request,
            graphName: "Testgraph",
            navigationActions: .disabled
        )
        await viewModel.load()
        viewModel.setComposerText("Frage")
        viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating == false && viewModel.messages.count == 2
        }

        setup.store.handleSecurityLock()

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.composerState.text.isEmpty)
        #expect(setup.store.isGenerationAuthorized == false)
        let snapshot = await waitForDiscard(on: setup.orchestrator)
        #expect(snapshot.discardCount > 0)
        #expect(snapshot.discardReasons.last == .graphLocked)
    }

    @Test
    func activeGraphMutationRevalidatesVisibleArtifactsButForeignMutationDoesNot() async throws {
        let graphID = UUID()
        let foreignGraphID = UUID()
        let bus = GraphMutationEventBus()
        let setup = makeSessionStore(
            graphID: graphID,
            scripts: [],
            mutationSubscriber: bus
        )
        let request = GraphChatLaunchRequest(
            scope: .entireGraph(GraphScope(graphID: graphID))
        )
        await setup.store.synchronizeAccess(
            activeGraphID: graphID,
            scope: request.scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        _ = setup.store.viewModel(
            request: request,
            graphName: "Testgraph",
            navigationActions: .disabled
        )

        for _ in 0..<2_000 {
            if await bus.subscriberCountForTesting == 1 {
                break
            }
            await Task.yield()
        }
        #expect(await bus.subscriberCountForTesting == 1)

        let deletedNodeID = UUID()
        let activeBatch = try GraphMutationBatch(
            graphID: graphID,
            events: [
                GraphMutationEvent(
                    graphID: graphID,
                    kind: .entityDeleted,
                    references: [
                        .node(NodeRefKey(kind: .entity, id: deletedNodeID))
                    ]
                )
            ]
        )
        _ = await bus.publishCommitted(activeBatch)
        await GraphChatUITestSupport.waitUntil {
            setup.store.presentationRevalidationRevision == 1
        }

        #expect(setup.store.presentationRevalidationRevision == 1)
        #expect(setup.store.hasActiveSession)

        let foreignBatch = try GraphMutationBatch(
            graphID: foreignGraphID,
            events: [
                GraphMutationEvent(
                    graphID: foreignGraphID,
                    kind: .entityDeleted,
                    references: [.node(NodeRefKey(kind: .entity, id: UUID()))]
                )
            ]
        )
        _ = await bus.publishCommitted(foreignBatch)
        for _ in 0..<32 {
            await Task.yield()
        }

        #expect(setup.store.presentationRevalidationRevision == 1)
        #expect(setup.store.hasActiveSession)
        await bus.finish()
    }

    @Test
    func concurrentGraphChatHostsShareRuntimeRefreshTasks() async {
        let graphID = UUID()
        let graphScope = GraphScope(graphID: graphID)
        let availabilityProvider = GraphChatSessionAvailabilityProbe()
        let indexProvider = GraphChatSessionIndexProbe()
        let bus = GraphMutationEventBus()
        let store = GraphChatSessionStore(
            baseOrchestrator: GraphChatUIFakeOrchestrator(scripts: []),
            availabilityProvider: availabilityProvider,
            schemaProvider: GraphChatUIFakeSchemaProvider(
                contexts: [GraphChatTestSupport.makeSchemaContext(graphID: graphID)]
            ),
            indexStatusProvider: indexProvider,
            mutationSubscriber: bus
        )

        let availabilityTasks = (0..<8).map { _ in
            Task { @MainActor in
                await store.refreshAvailability()
            }
        }
        for task in availabilityTasks {
            await task.value
        }

        let indexTasks = (0..<8).map { _ in
            Task { @MainActor in
                await store.refreshIndex(
                    for: graphScope,
                    prepareIfNeeded: false
                )
            }
        }
        for task in indexTasks {
            await task.value
        }

        #expect(await availabilityProvider.callCount == 1)
        #expect(await indexProvider.presentationCallCount == 1)
        await bus.finish()
    }

    private func makeSessionStore(
        graphID: UUID,
        scripts: [GraphChatUIFakeScript],
        mutationSubscriber: any GraphMutationSubscribing = GraphMutationEventBus.shared
    ) -> (
        store: GraphChatSessionStore,
        orchestrator: GraphChatUIFakeOrchestrator
    ) {
        let context = GraphChatTestSupport.makeSchemaContext(graphID: graphID)
        let orchestrator = GraphChatUIFakeOrchestrator(scripts: scripts)
        let store = GraphChatSessionStore(
            baseOrchestrator: orchestrator,
            availabilityProvider: GraphChatUIFakeAvailabilityProvider(value: .available),
            schemaProvider: GraphChatUIFakeSchemaProvider(contexts: [context]),
            indexStatusProvider: GraphChatUIFakeIndexProvider(
                value: .ready(documentCount: 1)
            ),
            mutationSubscriber: mutationSubscriber
        )
        return (store, orchestrator)
    }

    private func waitForDiscard(
        on orchestrator: GraphChatUIFakeOrchestrator,
        maximumYields: Int = 2_000
    ) async -> GraphChatUIOrchestratorSnapshot {
        for _ in 0..<maximumYields {
            let snapshot = await orchestrator.snapshot()
            if snapshot.discardCount > 0 {
                return snapshot
            }
            await Task.yield()
        }
        return await orchestrator.snapshot()
    }
}

private actor GraphChatSessionAvailabilityProbe: GraphChatAvailabilityProviding {
    private(set) var callCount = 0

    func availability() async -> GraphChatModelAvailability {
        callCount += 1
        for _ in 0..<64 {
            await Task.yield()
        }
        return .available
    }
}

private actor GraphChatSessionIndexProbe: GraphChatIndexStatusProviding {
    private(set) var presentationCallCount = 0

    func presentationState(
        for _: GraphScope
    ) async -> GraphChatIndexPresentationState {
        presentationCallCount += 1
        for _ in 0..<64 {
            await Task.yield()
        }
        return .ready(documentCount: 1)
    }
}

private actor GraphChatBlockingIndexProbe: GraphChatIndexStatusProviding {
    private(set) var hasStarted = false
    private(set) var cancellationCount = 0

    func presentationState(
        for _: GraphScope
    ) async -> GraphChatIndexPresentationState {
        .notReady(documentCount: nil)
    }

    func prepareIndex(
        for _: GraphScope
    ) async -> GraphChatIndexPresentationState {
        hasStarted = true
        do {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return .ready(documentCount: 0)
        } catch is CancellationError {
            cancellationCount += 1
            return .notReady(documentCount: nil)
        } catch {
            return .failed(
                message: error.localizedDescription,
                isUsable: false,
                documentCount: nil
            )
        }
    }
}
