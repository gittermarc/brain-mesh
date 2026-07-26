import Foundation
import Testing
@testable import BrainMesh

private actor GraphChatProviderAttemptRecorder {
    private var attempts: [GraphChatProviderSessionResources] = []

    func record(_ resources: GraphChatProviderSessionResources) {
        attempts.append(resources)
    }

    func snapshot() -> [GraphChatProviderSessionResources] {
        attempts
    }
}

private final class GraphChatProviderRetryEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [GraphChatProviderForwardedEvent] = []

    func record(_ event: GraphChatProviderForwardedEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [GraphChatProviderForwardedEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

struct GraphChatProviderContextRetryTests {
    @Test
    func successfulStandardAttemptDoesNotRetry() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [successfulScript("Standard")]
        )
        let setup = try await makeSetup(provider: provider)
        let attempts = GraphChatProviderAttemptRecorder()

        let result = try await setup.retry.execute(
            initialResources: setup.initialResources,
            question: "Use the standard attempt.",
            continuationOperation: nil,
            onAttemptResources: { resources in
                await attempts.record(resources)
            },
            onEvent: { _ in }
        )

        #expect(result.request.contextProfile != .recovery)
        #expect(await attempts.snapshot().count == 1)
        #expect(await provider.snapshot().createdSessions.count == 1)
        await setup.sessionFactory.cleanupFailedAttempt(
            result.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func oneContextFailureCreatesOneFullyIsolatedRecoveryAttempt() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                contextFailureScript(),
                successfulScript("Recovered"),
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let attempts = GraphChatProviderAttemptRecorder()

        let result = try await setup.retry.execute(
            initialResources: setup.initialResources,
            question: "Retry exactly once.",
            continuationOperation: nil,
            onAttemptResources: { resources in
                await attempts.record(resources)
            },
            onEvent: { _ in }
        )
        let recordedAttempts = await attempts.snapshot()
        let first = try #require(recordedAttempts.first)
        let recovery = try #require(recordedAttempts.last)
        let firstLifecycle = await first.lifecycle.snapshotForTesting()

        #expect(recordedAttempts.count == 2)
        #expect(result.request.contextProfile == .recovery)
        #expect(first.sessionID != recovery.sessionID)
        #expect(
            ObjectIdentifier(first.evidenceRegistry)
                != ObjectIdentifier(recovery.evidenceRegistry)
        )
        #expect(first.artifactTransactionID != recovery.artifactTransactionID)
        #expect(
            ObjectIdentifier(first.conversationTransaction)
                != ObjectIdentifier(recovery.conversationTransaction)
        )
        #expect(
            ObjectIdentifier(first.artifactRegistry)
                == ObjectIdentifier(recovery.artifactRegistry)
        )
        #expect(first.artifactSessionID == recovery.artifactSessionID)
        #expect(first.conversationBaseState == recovery.conversationBaseState)
        #expect(firstLifecycle.evidenceCleaned)
        #expect(firstLifecycle.artifactRolledBack)
        #expect(firstLifecycle.sessionDiscarded)
        await setup.sessionFactory.cleanupFailedAttempt(
            result.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func secondContextFailureIsPropagatedWithoutAThirdAttempt() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [contextFailureScript(), contextFailureScript()]
        )
        let setup = try await makeSetup(provider: provider)
        let attempts = GraphChatProviderAttemptRecorder()

        do {
            _ = try await setup.retry.execute(
                initialResources: setup.initialResources,
                question: "Do not start a third attempt.",
                continuationOperation: nil,
                onAttemptResources: { resources in
                    await attempts.record(resources)
                },
                onEvent: { _ in }
            )
            Issue.record("Expected the second context error.")
        } catch let error as GraphChatProviderError {
            #expect(error.code == .contextWindowExceeded)
        }

        #expect(await attempts.snapshot().count == 2)
        #expect(await provider.snapshot().createdSessions.count == 2)
    }

    @Test
    func failedAttemptConversationCandidateCannotReachRecovery() async throws {
        let evidence = GraphChatProviderTestSupport.makeEvidence()
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .toolRequest(.searchGraph(query: "partial", limit: 1)),
                        .failure(
                            GraphChatProviderError(
                                code: .contextWindowExceeded,
                                message: "Context window exceeded"
                            )
                        ),
                    ]
                ),
                successfulScript("Recovered without tools"),
            ]
        )
        let setup = try await makeSetup(
            provider: provider,
            runnerFactory: EvidenceRegisteringFakeToolRunnerFactory(
                evidenceByTool: [.searchGraph: [evidence]]
            )
        )

        let result = try await setup.retry.execute(
            initialResources: setup.initialResources,
            question: "Discard partial conversation state.",
            continuationOperation: nil,
            onAttemptResources: { _ in },
            onEvent: { _ in }
        )
        let recoveryState = await result.resources.conversationTransaction.snapshot()

        #expect(recoveryState == result.resources.conversationBaseState)
        #expect(recoveryState.resultContexts.isEmpty)
        #expect(recoveryState.nodeReferences.isEmpty)
        await setup.sessionFactory.cleanupFailedAttempt(
            result.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func cancellationDuringRecoveryTargetsTheRecoverySession() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                contextFailureScript(),
                FakeGraphChatProviderScript(steps: [.waitForCancellation]),
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let attempts = GraphChatProviderAttemptRecorder()
        let task = Task {
            try await setup.retry.execute(
                initialResources: setup.initialResources,
                question: "Cancel recovery.",
                continuationOperation: nil,
                onAttemptResources: { resources in
                    await attempts.record(resources)
                },
                onEvent: { _ in }
            )
        }
        await GraphChatProviderTestSupport.waitUntil {
            await provider.snapshot().streamedSessions.count == 2
        }

        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected recovery cancellation.")
        } catch is CancellationError {
        }

        let recordedAttempts = await attempts.snapshot()
        let recovery = try #require(recordedAttempts.last)
        let providerSnapshot = await provider.snapshot()
        #expect(providerSnapshot.cancelledSessions.contains(recovery.sessionID))
        #expect(await recovery.lifecycle.snapshotForTesting().artifactRolledBack)
        #expect(await recovery.lifecycle.snapshotForTesting().evidenceCleaned)
    }

    @Test
    func partialEventsStayInOrderAcrossRecovery() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "First attempt",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .failure(
                            GraphChatProviderError(
                                code: .contextWindowExceeded,
                                message: "Context window exceeded"
                            )
                        ),
                    ]
                ),
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "Recovery attempt",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    directAnswer: "Recovered",
                                    hasInsufficientEvidence: true
                                )
                            )
                        ),
                    ]
                ),
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let recorder = GraphChatProviderRetryEventRecorder()

        let result = try await setup.retry.execute(
            initialResources: setup.initialResources,
            question: "Keep partial ordering.",
            continuationOperation: nil,
            onAttemptResources: { _ in },
            onEvent: { recorder.record($0) }
        )

        #expect(
            recorder.snapshot()
                == [
                    .partialAnswer("First attempt"),
                    .partialAnswer("Recovery attempt"),
                ]
        )
        await setup.sessionFactory.cleanupFailedAttempt(
            result.resources,
            requestProviderCancellation: false
        )
    }

    private func makeSetup(
        provider: FakeGraphChatModelProvider,
        runnerFactory: any GraphChatModelToolRunnerFactory =
            EvidenceRegisteringFakeToolRunnerFactory()
    ) async throws -> (
        sessionFactory: GraphChatProviderSessionFactory,
        retry: GraphChatProviderContextRetry,
        initialResources: GraphChatProviderSessionResources
    ) {
        let sessionFactory = GraphChatProviderTestSupport.makeProviderSessionFactory(
            provider: provider,
            schemaProvider: FakeGraphSchemaSnapshotProvider(
                contexts: [
                    GraphChatTestSupport.makeSchemaContext(
                        graphID: GraphChatTestSupport.graphID
                    )
                ]
            ),
            toolRunnerFactory: runnerFactory
        )
        let executor = GraphChatProviderExecutor(
            provider: provider,
            sessionFactory: sessionFactory
        )
        let resources = try await GraphChatProviderTestSupport
            .makeInitialProviderResources(sessionFactory: sessionFactory)
        return (
            sessionFactory,
            GraphChatProviderContextRetry(
                sessionFactory: sessionFactory,
                requestBuilder: GraphChatProviderRequestBuilder(),
                executor: executor
            ),
            resources
        )
    }

    private func contextFailureScript() -> FakeGraphChatProviderScript {
        FakeGraphChatProviderScript(
            steps: [
                .failure(
                    GraphChatProviderError(
                        code: .contextWindowExceeded,
                        message: "Context window exceeded"
                    )
                )
            ]
        )
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
