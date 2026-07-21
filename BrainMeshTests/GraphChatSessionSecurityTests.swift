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

        try await registry.register([evidence])
        #expect(await registry.contains(evidence.id))

        await registry.removeAll()

        #expect(await registry.contains(evidence.id) == false)
        #expect(await registry.snapshotForTesting().isEmpty)
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
            navigationActions: .disabled
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
            navigationActions: .disabled
        )

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
        #expect((await setup.orchestrator.snapshot()).discardCount > 0)
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
        #expect((await waitForDiscard(on: setup.orchestrator)).discardCount > 0)
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
        #expect((await waitForDiscard(on: setup.orchestrator)).discardCount > 0)
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
                        .partialAnswer("Sensible Teilantwort")
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
        #expect((await waitForDiscard(on: setup.orchestrator)).discardCount > 0)
    }

    private func makeSessionStore(
        graphID: UUID,
        scripts: [GraphChatUIFakeScript]
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
            )
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
