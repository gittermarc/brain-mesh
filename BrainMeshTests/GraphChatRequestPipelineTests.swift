import Foundation
import Testing

@testable import BrainMesh

struct GraphChatRequestPipelineTests {
    @Test
    func localUnsupportedSkipsProviderSessionAndExecution() async throws {
        let provider = FakeGraphChatModelProvider(scripts: [])
        let recorder = PipelineEventRecorder()
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: recorder
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Lösche den Node Phoenix.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )
        let providerSnapshot = await provider.snapshot()

        #expect(providerSnapshot.createdSessions.isEmpty)
        #expect(events.contains { event in
            if case .completed(let answer) = event {
                return answer.state == .unsupported(.graphMutation)
            }
            return false
        })
        #expect(
            await recorder.count(
                stage: .providerExecution,
                phase: .started
            ) == 0
        )
        #expect(
            await recorder.count(
                stage: .answerFinalization,
                phase: .completed
            ) == 1
        )
        #expect(
            await recorder.count(
                stage: .turnCommit,
                phase: .completed
            ) == 1
        )
    }

    @Test
    func localClarificationSkipsProviderSessionAndExecution() async throws {
        let provider = FakeGraphChatModelProvider(scripts: [])
        let recorder = PipelineEventRecorder()
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: recorder
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        var state = GraphChatConversationState.initial(
            graphScope: graphScope,
            chatScope: chatScope
        )
        state.pendingClarification = GraphChatPendingClarification(
            id: UUID(),
            decision: .conversationReference,
            options: [
                GraphChatPendingClarificationOption(
                    id: "CI_ONE",
                    title: "Phoenix",
                    proposal: .alias("CI_ONE")
                )
            ],
            sourceTurnID: nil,
            graphScope: graphScope,
            chatScope: chatScope,
            continuationOperation: .openReference,
            continuationQuestion: "Öffne das ausgewählte Projekt.",
            createdAt: Date(timeIntervalSince1970: 1_735_732_000),
            expiresAt: Date(timeIntervalSince1970: 1_735_740_000)
        )
        try await orchestrator.restoreConversationState(
            from: .committed(state)
        )

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Bitte noch einmal erklären.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )

        #expect(await provider.snapshot().createdSessions.isEmpty)
        #expect(events.contains { event in
            if case .completed(let answer) = event,
               case .clarification = answer.state {
                return true
            }
            return false
        })
        #expect(
            await recorder.count(
                stage: .providerExecution,
                phase: .started
            ) == 0
        )
    }

    @Test
    func normalProviderTurnRunsEachPipelineBoundaryOnce() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [successfulScript("Provider answer")]
        )
        let recorder = PipelineEventRecorder()
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: recorder
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Beantworte die Frage.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        #expect(
            await recorder.count(stage: .preflight, phase: .completed) == 1
        )
        #expect(
            await recorder.count(
                stage: .sessionResources,
                phase: .completed
            ) == 1
        )
        #expect(
            await recorder.count(
                stage: .providerExecution,
                phase: .started
            ) == 1
        )
        #expect(
            await recorder.count(
                stage: .answerFinalization,
                phase: .completed
            ) == 1
        )
        #expect(
            await recorder.count(
                stage: .turnCommit,
                phase: .completed
            ) == 1
        )
        #expect(await provider.snapshot().createdSessions.count == 1)
        #expect(
            await orchestrator.conversationStateSnapshot()?.turnContexts.count
                == 1
        )
    }

    @Test
    func successfulTurnCommitsStateAndOneArtifactOnce() async throws {
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)
        let evidence = GraphChatProviderTestSupport.makeEvidence()
        let binding = GraphChatAnswerArtifactEvidenceBinding(
            evidenceIDs: [evidence.id]
        )
        let draft = GraphChatAnswerArtifactDraft(
            graphScope: graphScope,
            title: "Pipeline artifact",
            payload: .metric(
                GraphChatAnswerArtifactMetricPayload(
                    title: "Pipeline artifact",
                    value: .integer(1),
                    unit: nil,
                    contextDescription: nil,
                    evidence: binding
                )
            ),
            evidence: binding
        )
        let provider = PipelineArtifactEchoProvider()
        let recorder = PipelineEventRecorder()
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [evidence]],
                artifactDraftsByTool: [.searchGraph: [draft]]
            ),
            artifactRevalidator: GraphChatRegistryAnswerArtifactRevalidator(),
            pipelineObserver: observer(for: recorder)
        )

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Commit state and one artifact.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let answer = try #require(events.compactMap { event in
            if case .completed(let answer) = event {
                return answer
            }
            return nil
        }.last)
        let presentation = await orchestrator.resolveAnswerPresentation(
            artifactIDs: answer.artifactIDs,
            evidence: answer.evidence,
            graphScope: graphScope,
            chatScope: chatScope
        )

        #expect(answer.artifactIDs.count == 1)
        #expect(presentation.artifacts.count == 1)
        #expect(
            await orchestrator.conversationStateSnapshot()?.turnContexts.count
                == 1
        )
        #expect(
            await recorder.count(
                stage: .turnCommit,
                phase: .completed
            ) == 1
        )
    }

    @Test
    func contextRetryExecutesProviderTwiceAndFinalizesOnce() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .failure(
                            GraphChatProviderError(
                                code: .contextWindowExceeded,
                                message: "Context window exceeded"
                            )
                        )
                    ]
                ),
                successfulScript("Recovered"),
            ]
        )
        let recorder = PipelineEventRecorder()
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: recorder
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Retry exactly once.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        #expect(
            await recorder.count(
                stage: .providerExecution,
                phase: .started
            ) == 2
        )
        #expect(
            await recorder.count(
                stage: .answerFinalization,
                phase: .completed
            ) == 1
        )
        #expect(
            await recorder.count(
                stage: .turnCommit,
                phase: .completed
            ) == 1
        )
        #expect(await provider.snapshot().streamedSessions.count == 2)
    }

    @Test
    func failureBeforeFinalizationCommitsNothing() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .failure(
                            GraphChatProviderError(
                                code: .toolFailure,
                                message: "Expected provider failure"
                            )
                        )
                    ]
                )
            ]
        )
        let recorder = PipelineEventRecorder()
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: recorder
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Fail before finalization.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        #expect(events.contains { event in
            if case .failure = event { return true }
            return false
        })
        #expect(
            await recorder.count(
                stage: .answerFinalization,
                phase: .started
            ) == 0
        )
        #expect(
            await recorder.count(
                stage: .turnCommit,
                phase: .completed
            ) == 0
        )
        #expect(await orchestrator.conversationStateSnapshot() == nil)
    }

    @Test
    func failureDuringFinalizationCommitsNothing() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence()
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(
                            .searchGraph(query: "finalization", limit: 1)
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    evidenceIDs: [evidence.id]
                                )
                            )
                        ),
                    ]
                )
            ]
        )
        let recorder = PipelineEventRecorder()
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [evidence]]
            ),
            evidenceValidator: ThrowingPipelineEvidenceValidator(),
            pipelineObserver: observer(for: recorder)
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)

        let events = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Fail during finalization.",
                graphScope: graphScope,
                chatScope: .entireGraph(graphScope)
            )
        )

        #expect(events.contains { event in
            if case .failure = event { return true }
            return false
        })
        #expect(
            await recorder.count(
                stage: .answerFinalization,
                phase: .started
            ) == 1
        )
        #expect(
            await recorder.count(
                stage: .answerFinalization,
                phase: .completed
            ) == 0
        )
        #expect(
            await recorder.count(
                stage: .turnCommit,
                phase: .completed
            ) == 0
        )
        #expect(await orchestrator.conversationStateSnapshot() == nil)
    }

    @Test
    func oldRequestCannotCommitAfterNewRequestStarts() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(steps: [.waitForCancellation]),
                successfulScript("Current answer"),
            ]
        )
        let recorder = PipelineEventRecorder()
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: recorder
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        let firstStream = await orchestrator.streamAnswer(
            question: "Old request",
            graphScope: graphScope,
            chatScope: chatScope
        )
        let firstCollector = Task {
            await GraphChatProviderTestSupport.collect(firstStream)
        }
        await GraphChatProviderTestSupport.waitUntil {
            await provider.snapshot().streamedSessions.count == 1
        }
        let secondEvents = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "New request",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let firstEvents = await firstCollector.value

        #expect(firstEvents.contains(.cancelled))
        #expect(secondEvents.contains { event in
            if case .completed(let answer) = event {
                return answer.directAnswer == "Current answer"
            }
            return false
        })
        #expect(
            await recorder.count(
                stage: .turnCommit,
                phase: .completed
            ) == 1
        )
        #expect(
            await orchestrator.conversationStateSnapshot()?.turnContexts.count
                == 1
        )
    }

    @Test
    func prepareAndStreamUseTheSamePreparedProviderSession() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [successfulScript("Prepared answer")]
        )
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: PipelineEventRecorder()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let chatScope = GraphChatScope.entireGraph(graphScope)

        try await orchestrator.prepare(
            graphScope: graphScope,
            chatScope: chatScope
        )
        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Nutze die vorbereitete Session.",
                graphScope: graphScope,
                chatScope: chatScope
            )
        )
        let snapshot = await provider.snapshot()

        #expect(snapshot.createdSessions.count == 1)
        #expect(snapshot.prewarmedSessions.count == 1)
        #expect(snapshot.streamedSessions == snapshot.prewarmedSessions)
    }

    @Test
    func repeatedCancelIsIdempotentForTheProviderSession() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(steps: [.waitForCancellation])
            ]
        )
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: PipelineEventRecorder()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let stream = await orchestrator.streamAnswer(
            question: "Wait for cancellation.",
            graphScope: graphScope,
            chatScope: .entireGraph(graphScope)
        )
        let collector = Task {
            await GraphChatProviderTestSupport.collect(stream)
        }
        await GraphChatProviderTestSupport.waitUntil {
            await provider.snapshot().streamedSessions.count == 1
        }

        async let firstCancel: Void = orchestrator.cancelCurrentGeneration()
        async let secondCancel: Void = orchestrator.cancelCurrentGeneration()
        _ = await (firstCancel, secondCancel)
        let events = await collector.value
        let snapshot = await provider.snapshot()
        let sessionID = try #require(snapshot.streamedSessions.first)

        #expect(events.filter(\.isTerminal).count == 1)
        #expect(events.contains(.cancelled))
        #expect(
            snapshot.cancelledSessions.filter { $0 == sessionID }.count == 1
        )
    }

    @Test
    func foreignCheckpointIsRejectedBeforeRestoreCleanup() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [successfulScript("Committed")]
        )
        let orchestrator = GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(),
            graphIDs: [
                GraphChatTestSupport.graphID,
                GraphChatTestSupport.otherGraphID,
            ]
        )
        let firstGraphScope = GraphScope(
            graphID: GraphChatTestSupport.graphID
        )
        _ = await GraphChatProviderTestSupport.collect(
            await orchestrator.streamAnswer(
                question: "Commit the first graph.",
                graphScope: firstGraphScope,
                chatScope: .entireGraph(firstGraphScope)
            )
        )
        let foreignGraphScope = GraphScope(
            graphID: GraphChatTestSupport.otherGraphID
        )
        let checkpoint = GraphChatConversationCheckpoint.initial(
            graphScope: foreignGraphScope,
            chatScope: .entireGraph(foreignGraphScope)
        )

        await #expect(throws: GraphChatError.self) {
            try await orchestrator.restoreConversationState(from: checkpoint)
        }
        #expect(
            await orchestrator.conversationStateSnapshot()?.graphScope
                == firstGraphScope
        )
    }

    @Test
    func presentationResolutionRemainsScopeSafe() async {
        let provider = FakeGraphChatModelProvider(scripts: [])
        let orchestrator = makeOrchestrator(
            provider: provider,
            pipelineRecorder: PipelineEventRecorder()
        )
        let graphScope = GraphScope(graphID: GraphChatTestSupport.graphID)
        let foreignGraphScope = GraphScope(
            graphID: GraphChatTestSupport.otherGraphID
        )
        let artifactID = GraphChatAnswerArtifactID()

        let resolution = await orchestrator.resolveAnswerPresentation(
            artifactIDs: [artifactID],
            evidence: [],
            graphScope: graphScope,
            chatScope: .entireGraph(foreignGraphScope)
        )

        #expect(resolution.artifacts.isEmpty)
        #expect(
            resolution.unavailableArtifactReasons[artifactID]
                == .scopeMismatch
        )
    }

    private func makeOrchestrator(
        provider: FakeGraphChatModelProvider,
        pipelineRecorder: PipelineEventRecorder
    ) -> GraphChatOrchestrator {
        GraphChatProviderTestSupport.makeOrchestrator(
            provider: provider,
            factory: EvidenceRegisteringFakeToolRunnerFactory(),
            pipelineObserver: observer(for: pipelineRecorder)
        )
    }

    private func observer(
        for recorder: PipelineEventRecorder
    ) -> GraphChatRequestPipelineObserver {
        GraphChatRequestPipelineObserver { event in
            await recorder.record(event)
        }
    }

    private func successfulScript(
        _ answer: String
    ) -> FakeGraphChatProviderScript {
        FakeGraphChatProviderScript(
            steps: [
                .event(
                    .completed(
                        GraphChatProviderTestSupport.makeFinalAnswer(
                            directAnswer: answer,
                            hasInsufficientEvidence: true
                        )
                    )
                )
            ]
        )
    }
}

private actor PipelineEventRecorder {
    private var events: [GraphChatRequestPipelineEvent] = []

    func record(_ event: GraphChatRequestPipelineEvent) {
        events.append(event)
    }

    func count(
        stage: GraphChatRequestPipelineStage,
        phase: GraphChatRequestPipelineStagePhase
    ) -> Int {
        events.filter {
            $0.stage == stage && $0.phase == phase
        }.count
    }
}

private struct ThrowingPipelineEvidenceValidator: GraphEvidenceValidating {
    func validatedEvidence(
        _ evidence: [GraphEvidence],
        in scope: GraphChatScope
    ) async throws -> [GraphEvidence] {
        throw PipelineFinalizationError.expected
    }
}

private enum PipelineFinalizationError: Error {
    case expected
}

private actor PipelineArtifactEchoProvider: GraphChatModelProvider {
    private var configurations: [
        GraphChatModelSessionID: GraphChatModelSessionConfiguration
    ] = [:]

    func availability() async -> GraphChatModelAvailability {
        .available
    }

    func createSession(
        configuration: GraphChatModelSessionConfiguration
    ) async throws -> GraphChatModelSessionID {
        let sessionID = GraphChatModelSessionID()
        configurations[sessionID] = configuration
        return sessionID
    }

    func prewarm(
        sessionID: GraphChatModelSessionID,
        promptPrefix: String?
    ) async throws {
        guard configurations[sessionID] != nil else {
            throw GraphChatProviderError(
                code: .invalidSession,
                message: "Missing test session."
            )
        }
    }

    func streamResponse(
        sessionID: GraphChatModelSessionID,
        request: GraphChatModelRequest
    ) async throws -> GraphChatProviderEventStream {
        guard let configuration = configurations[sessionID] else {
            throw GraphChatProviderError(
                code: .invalidSession,
                message: "Missing test session."
            )
        }
        return GraphChatProviderEventStream { continuation in
            let task = Task {
                do {
                    let response = try await configuration.toolRunner.run(
                        .searchGraph(query: "pipeline artifact", limit: 1)
                    )
                    continuation.yield(
                        .completed(
                            GraphChatProviderTestSupport.makeFinalAnswer(
                                evidenceIDs: response.evidenceIDs,
                                artifactIDs: response.artifactIDs
                            )
                        )
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func cancelGeneration(sessionID: GraphChatModelSessionID) async {
    }

    func discardSession(sessionID: GraphChatModelSessionID) async {
        configurations.removeValue(forKey: sessionID)
    }
}

private extension GraphChatStreamEvent {
    var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failure:
            return true
        case .started, .toolActivity, .partialAnswer:
            return false
        }
    }
}
