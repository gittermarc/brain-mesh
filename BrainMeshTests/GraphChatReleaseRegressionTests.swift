import Foundation
import Testing
@testable import BrainMesh

@MainActor
struct GraphChatReleaseRegressionTests {
    @Test
    func paywallDraftRemainsInMemoryWithoutAutomaticGenerationAndClearsOnLock() async {
        let graphID = UUID()
        let graphScope = GraphScope(graphID: graphID)
        let scope = GraphChatScope.entireGraph(graphScope)
        let coordinator = GraphChatLaunchCoordinator()
        coordinator.launch(
            scope: scope,
            prefilledQuestion: "Welche offenen Punkte sind wichtig?"
        )
        coordinator.updateDraft(
            "Welche offenen Punkte sind wichtig und überfällig?",
            for: scope
        )

        coordinator.resetToWholeGraph(graphID)
        let request = coordinator.requestForActiveGraph(graphID)
        #expect(request.prefilledQuestion == "Welche offenen Punkte sind wichtig und überfällig?")

        let orchestrator = GraphChatUIFakeOrchestrator(scripts: [])
        let store = makeStore(
            graphID: graphID,
            orchestrator: orchestrator,
            mutationBus: GraphMutationEventBus()
        )
        let decision = GraphChatAccessPolicy.evaluate(
            GraphChatAccessPolicyInput(
                activeGraphID: graphID,
                graphExists: true,
                requestedScope: scope,
                entitlement: .pro,
                graphRequiresUnlock: false,
                isGraphUnlocked: true,
                availability: .available,
                indexState: .ready(documentCount: 10)
            )
        )
        await store.synchronizeAccess(
            decision: decision,
            activeGraphID: graphID,
            scope: scope,
            isGraphUnlocked: true
        )
        let viewModel = store.viewModel(
            request: request,
            graphName: "Release Graph",
            navigationActions: .disabled,
            draftChangeHandler: { text in
                coordinator.updateDraft(text, for: scope)
            }
        )
        await viewModel.load()

        #expect(viewModel.composerState.text == request.prefilledQuestion)
        #expect(viewModel.messages.isEmpty)
        #expect(await orchestrator.snapshot().questions.isEmpty)

        coordinator.handleSecurityLock(graphID: graphID)
        store.handleSecurityLock(graphID: graphID)
        #expect(coordinator.request == nil)
        #expect(coordinator.draftText.isEmpty)
        #expect(viewModel.composerState.text.isEmpty)
    }

    @Test
    func backgroundLockDuringStreamingCancelsGenerationAndPurgesMemoryHistory() async {
        let graphID = UUID()
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let history = InMemoryGraphChatHistoryStore()
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [
                        .started(requestID: UUID()),
                        .partialAnswer("Sensitive partial state")
                    ],
                    waitsForCancellation: true
                )
            ]
        )
        let store = GraphChatSessionStore(
            baseOrchestrator: orchestrator,
            availabilityProvider: GraphChatUIFakeAvailabilityProvider(value: .available),
            schemaProvider: GraphChatUIFakeSchemaProvider(
                contexts: [GraphChatTestSupport.makeSchemaContext(graphID: graphID)]
            ),
            indexStatusProvider: GraphChatUIFakeIndexProvider(
                value: .ready(documentCount: 10)
            ),
            historyStore: history,
            mutationSubscriber: GraphMutationEventBus()
        )
        await store.synchronizeAccess(
            activeGraphID: graphID,
            scope: scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let viewModel = store.viewModel(
            request: GraphChatLaunchRequest(scope: scope),
            graphName: "Background Graph",
            navigationActions: .disabled
        )
        await viewModel.load()
        viewModel.setComposerText("Sensitive question")
        viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating && viewModel.messages.count == 2
        }

        store.handleSecurityLock()
        let cleanup = await waitForCleanup(on: orchestrator)
        await GraphChatProviderTestSupport.waitUntil {
            await history.messages(for: scope).isEmpty
        }

        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.composerState.text.isEmpty)
        #expect(await history.messages(for: scope).isEmpty)
        #expect(cleanup.cancellationCount > 0)
        #expect(cleanup.discardCount > 0)
    }

    @Test
    func graphChangeLockAndTerminationPurgeRetainedSessionHistory() async {
        for boundary in SecurityBoundary.allCases {
            let graphID = UUID()
            let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
            let history = InMemoryGraphChatHistoryStore()
            await history.save(
                [
                    GraphChatTranscriptMessage(
                        state: .userQuestion("Memory-only sentinel")
                    )
                ],
                for: scope
            )
            let store = GraphChatSessionStore(
                baseOrchestrator: GraphChatUIFakeOrchestrator(scripts: []),
                availabilityProvider: GraphChatUIFakeAvailabilityProvider(value: .available),
                schemaProvider: GraphChatUIFakeSchemaProvider(
                    contexts: [GraphChatTestSupport.makeSchemaContext(graphID: graphID)]
                ),
                indexStatusProvider: GraphChatUIFakeIndexProvider(
                    value: .ready(documentCount: 1)
                ),
                historyStore: history,
                mutationSubscriber: GraphMutationEventBus()
            )
            await store.synchronizeAccess(
                activeGraphID: graphID,
                scope: scope,
                hasProEntitlement: true,
                isGraphUnlocked: true
            )
            _ = store.viewModel(
                request: GraphChatLaunchRequest(scope: scope),
                graphName: "Privacy Boundary Graph",
                navigationActions: .disabled
            )

            switch boundary {
            case .graphChange:
                store.handleActiveGraphChange()
            case .lock:
                store.handleSecurityLock(graphID: graphID)
            case .termination:
                store.handleAppTermination()
            }
            await GraphChatProviderTestSupport.waitUntil {
                await history.messages(for: scope).isEmpty
            }

            #expect(await history.messages(for: scope).isEmpty)
        }
    }

    @Test
    func deleteImportAndReplaceDuringStreamingCancelAndDiscardTheSession() async throws {
        let kinds: [GraphMutationKind] = [
            .graphDeleted,
            .graphImported,
            .graphReplaced
        ]

        for kind in kinds {
            let graphID = UUID()
            let bus = GraphMutationEventBus()
            let orchestrator = GraphChatUIFakeOrchestrator(
                scripts: [
                    GraphChatUIFakeScript(
                        events: [
                            .started(requestID: UUID()),
                            .partialAnswer("Technische Teilantwort")
                        ],
                        waitsForCancellation: true
                    )
                ]
            )
            let store = makeStore(
                graphID: graphID,
                orchestrator: orchestrator,
                mutationBus: bus
            )
            await waitForSubscriber(on: bus)
            let graphScope = GraphScope(graphID: graphID)
            let scope = GraphChatScope.entireGraph(graphScope)
            await store.synchronizeAccess(
                activeGraphID: graphID,
                scope: scope,
                hasProEntitlement: true,
                isGraphUnlocked: true
            )
            let viewModel = store.viewModel(
                request: GraphChatLaunchRequest(scope: scope),
                graphName: "Mutation Graph",
                navigationActions: .disabled
            )
            await viewModel.load()
            viewModel.setComposerText("Laufende Frage")
            viewModel.send()
            await GraphChatUITestSupport.waitUntil {
                viewModel.isGenerating && viewModel.messages.count == 2
            }

            let event = GraphMutationEvent(graphID: graphID, kind: kind)
            let batch = try GraphMutationBatch(
                graphID: graphID,
                events: [event]
            )
            _ = await bus.publishCommitted(batch)
            await GraphChatUITestSupport.waitUntil {
                viewModel.messages.isEmpty
                    && store.isGenerationAuthorized == false
            }
            let snapshot = await waitForCleanup(on: orchestrator)

            #expect(viewModel.messages.isEmpty)
            #expect(viewModel.composerState.text.isEmpty)
            #expect(store.accessDecision == .denied)
            #expect(snapshot.cancellationCount > 0)
            #expect(snapshot.discardCount > 0)
        }
    }

    @Test
    func foreignGraphMutationIsIgnoredButGraphSwitchEntitlementAndBackgroundClearSession() async throws {
        let graphID = UUID()
        let bus = GraphMutationEventBus()
        let orchestrator = GraphChatUIFakeOrchestrator(
            scripts: [
                GraphChatUIFakeScript(
                    events: [.started(requestID: UUID())],
                    waitsForCancellation: true
                )
            ]
        )
        let store = makeStore(
            graphID: graphID,
            orchestrator: orchestrator,
            mutationBus: bus
        )
        await waitForSubscriber(on: bus)
        let graphScope = GraphScope(graphID: graphID)
        let scope = GraphChatScope.entireGraph(graphScope)
        await store.synchronizeAccess(
            activeGraphID: graphID,
            scope: scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let viewModel = store.viewModel(
            request: GraphChatLaunchRequest(scope: scope),
            graphName: "Isolation Graph",
            navigationActions: .disabled
        )
        await viewModel.load()
        viewModel.setComposerText("Graphisolierte Frage")
        viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating && viewModel.messages.count == 2
        }

        let foreignID = UUID()
        let foreignBatch = try GraphMutationBatch(
            graphID: foreignID,
            events: [
                GraphMutationEvent(graphID: foreignID, kind: .graphDeleted)
            ]
        )
        _ = await bus.publishCommitted(foreignBatch)
        for _ in 0..<20 {
            await Task.yield()
        }
        #expect(viewModel.messages.count == 2)
        #expect(store.isGenerationAuthorized)

        store.handleEntitlementRevocation()
        await GraphChatUITestSupport.waitUntil {
            viewModel.messages.isEmpty
        }
        #expect(store.isGenerationAuthorized == false)

        let secondOrchestrator = GraphChatUIFakeOrchestrator(scripts: [])
        let secondStore = makeStore(
            graphID: graphID,
            orchestrator: secondOrchestrator,
            mutationBus: GraphMutationEventBus()
        )
        await secondStore.synchronizeAccess(
            activeGraphID: graphID,
            scope: scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let secondViewModel = secondStore.viewModel(
            request: GraphChatLaunchRequest(
                scope: scope,
                prefilledQuestion: "Nur im Speicher"
            ),
            graphName: "Lifecycle Graph",
            navigationActions: .disabled
        )
        secondStore.handleActiveGraphChange()
        #expect(secondViewModel.composerState.text.isEmpty)
        #expect(secondStore.isGenerationAuthorized == false)

        let thirdOrchestrator = GraphChatUIFakeOrchestrator(scripts: [])
        let thirdStore = makeStore(
            graphID: graphID,
            orchestrator: thirdOrchestrator,
            mutationBus: GraphMutationEventBus()
        )
        await thirdStore.synchronizeAccess(
            activeGraphID: graphID,
            scope: scope,
            hasProEntitlement: true,
            isGraphUnlocked: true
        )
        let thirdViewModel = thirdStore.viewModel(
            request: GraphChatLaunchRequest(
                scope: scope,
                prefilledQuestion: "Background Draft"
            ),
            graphName: "Background Graph",
            navigationActions: .disabled
        )
        thirdStore.handleSecurityLock()
        #expect(thirdViewModel.composerState.text.isEmpty)
        #expect(thirdStore.isGenerationAuthorized == false)
    }

    @Test
    func staleIndexAndModelLossBlockGenerationWithConcreteState() async throws {
        let graphID = UUID()
        let scope = GraphChatScope.entireGraph(GraphScope(graphID: graphID))
        let stale = GraphChatAccessPolicy.evaluate(
            GraphChatAccessPolicyInput(
                activeGraphID: graphID,
                graphExists: true,
                requestedScope: scope,
                entitlement: .pro,
                graphRequiresUnlock: false,
                isGraphUnlocked: true,
                availability: .available,
                indexState: .stale(documentCount: 91)
            )
        )
        #expect(stale.route == .indexPreparing(.stale(documentCount: 91)))
        #expect(stale.canStartGeneration == false)

        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .failure(
                            GraphChatProviderError(
                                code: .unavailable,
                                message: "System model became unavailable"
                            )
                        )
                    ],
                    delayNanoseconds: 100_000_000
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(),
            graphIDs: [graphID]
        )
        let viewModel = GraphChatViewModel(
            graphScope: scope.graphScope,
            chatScope: scope,
            graphName: "Model Loss Graph",
            orchestrator: orchestrator,
            schemaProvider: FakeGraphSchemaSnapshotProvider(
                contexts: [GraphChatTestSupport.makeSchemaContext(graphID: graphID)]
            ),
            availabilityProvider: GraphChatModelAvailabilityAdapter(provider: provider),
            indexStatusProvider: GraphChatUIFakeIndexProvider(
                value: .ready(documentCount: 10)
            ),
            historyStore: InMemoryGraphChatHistoryStore(),
            navigationActions: .disabled
        )
        await viewModel.load()
        viewModel.setComposerText("Frage während Modellverlust")
        viewModel.send()
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating
                && viewModel.messages.count == 2
        }
        await provider.setAvailability(.unavailable(.modelNotReady))
        await GraphChatUITestSupport.waitUntil {
            viewModel.isGenerating == false
                && viewModel.messages.count == 2
        }
        let finalMessage = try #require(viewModel.messages.last)
        guard case .assistant(let assistant) = finalMessage.state else {
            Issue.record("Expected the final transcript message to be an assistant response.")
            return
        }
        #expect(assistant.phase == GraphChatAssistantPhase.availabilityError)
        #expect(viewModel.availabilityState == .unavailable(reason: .unknown))

        await viewModel.refreshRuntimeStates()
        #expect(viewModel.availabilityState == .unavailable(reason: .modelNotReady))
        #expect(viewModel.canSend == false)
    }

    @Test
    nonisolated func cancellationDuringToolExecutionStopsProviderAndToolWithoutFinalAnswer() async throws {
        let recorder = GraphChatFakeToolRunnerRecorder()
        let executionGate = GraphChatFakeToolExecutionGate()
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "cancel-me", limit: 1)),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Must not complete"
                                )
                            )
                        )
                    ]
                )
            ]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                recorder: recorder,
                executionGate: executionGate
            )
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let stream = await orchestrator.streamAnswer(
            question: "Cancel during tool",
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )
        var iterator = stream.makeAsyncIterator()
        var events: [GraphChatStreamEvent] = []
        var observedToolStart = false
        while let event = await iterator.next() {
            events.append(event)
            if case .toolActivity(let activity) = event,
                activity.tool == .searchGraph,
                activity.state == .started
            {
                observedToolStart = true
                break
            }
        }
        try #require(observedToolStart)
        await recorder.waitUntilRequestCount(1)

        let cancellationTask = Task {
            await orchestrator.cancelCurrentGeneration()
        }
        // Prevent a broken cancellation path from hanging the regression suite forever.
        let watchdogTask = Task {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            await executionGate.release()
        }

        await cancellationTask.value
        watchdogTask.cancel()
        await executionGate.release()

        while let event = await iterator.next() {
            events.append(event)
        }
        let runnerSnapshot = await recorder.snapshot()
        let providerSnapshot = await provider.snapshot()

        #expect(events.contains(.cancelled))
        #expect(events.contains { event in
            if case .completed = event {
                return true
            }
            return false
        } == false)
        #expect(runnerSnapshot.cancellationCount == 1)
        #expect(providerSnapshot.cancelledSessions.isEmpty == false)
    }

    private enum SecurityBoundary: CaseIterable {
        case graphChange
        case lock
        case termination
    }

    private func makeStore(
        graphID: UUID,
        orchestrator: GraphChatUIFakeOrchestrator,
        mutationBus: GraphMutationEventBus
    ) -> GraphChatSessionStore {
        GraphChatSessionStore(
            baseOrchestrator: orchestrator,
            availabilityProvider: GraphChatUIFakeAvailabilityProvider(
                value: .available
            ),
            schemaProvider: GraphChatUIFakeSchemaProvider(
                contexts: [GraphChatTestSupport.makeSchemaContext(graphID: graphID)]
            ),
            indexStatusProvider: GraphChatUIFakeIndexProvider(
                value: .ready(documentCount: 100)
            ),
            mutationSubscriber: mutationBus
        )
    }

    private func waitForSubscriber(
        on bus: GraphMutationEventBus,
        maximumYields: Int = 2_000
    ) async {
        for _ in 0..<maximumYields {
            if await bus.subscriberCountForTesting > 0 {
                return
            }
            await Task.yield()
        }
    }

    private func waitForCleanup(
        on orchestrator: GraphChatUIFakeOrchestrator,
        maximumYields: Int = 2_000
    ) async -> GraphChatUIOrchestratorSnapshot {
        for _ in 0..<maximumYields {
            let snapshot = await orchestrator.snapshot()
            if snapshot.cancellationCount > 0 && snapshot.discardCount > 0 {
                return snapshot
            }
            await Task.yield()
        }
        return await orchestrator.snapshot()
    }
}
