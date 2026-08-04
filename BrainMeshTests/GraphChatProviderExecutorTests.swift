import Foundation
import Testing
@testable import BrainMesh

private final class GraphChatProviderForwardedEventRecorder: @unchecked Sendable {
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

private actor GraphChatCountingPresentationStreamFirewall:
    GraphChatPresentationStreamValidating
{
    private var evaluatedTexts: [String] = []

    func presentCumulativeText(_ text: String) -> String? {
        evaluatedTexts.append(text)
        return text
    }

    func snapshot() -> [String] {
        evaluatedTexts
    }
}

private actor GraphChatFilteringPresentationStreamFirewall:
    GraphChatPresentationStreamValidating
{
    private var evaluationCount = 0

    func presentCumulativeText(_ text: String) -> String? {
        evaluationCount += 1
        return text == "Rejected raw snapshot" ? nil : text
    }

    func count() -> Int {
        evaluationCount
    }
}

private actor GraphChatProviderExecutorObservabilityRecorder:
    GraphChatObservabilityRecording
{
    private var events: [GraphChatObservabilityEvent] = []

    func record(_ event: GraphChatObservabilityEvent) {
        events.append(event)
    }

    func providerStreamingMetrics() -> [GraphChatProviderStreamingMetric] {
        events.compactMap { event in
            guard case .providerStreaming(let metric) = event else {
                return nil
            }
            return metric
        }
    }
}

struct GraphChatProviderExecutorTests {
    @Test
    func rejectedProviderSnapshotNeverCrossesTheSafeEventBoundary() async throws {
        let finalAnswer = GraphChatProviderTestSupport.makeFinalAnswer(
            directAnswer: "Safe final answer",
            hasInsufficientEvidence: true
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "Rejected raw snapshot",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "Safe cumulative snapshot",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(.completed(finalAnswer)),
                    ]
                )
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let firewall = GraphChatFilteringPresentationStreamFirewall()
        let observability = GraphChatProviderExecutorObservabilityRecorder()
        let executor = GraphChatProviderExecutor(
            provider: provider,
            sessionFactory: setup.sessionFactory,
            observability: observability,
            presentationStreamFirewallFactory: { _, _ in firewall }
        )
        let recorder = GraphChatProviderForwardedEventRecorder()

        _ = try await executor.execute(
            resources: setup.resources,
            request: setup.request,
            onEvent: { event in
                recorder.record(event)
            }
        )

        #expect(await firewall.count() == 2)
        #expect(
            recorder.snapshot()
                == [.partialAnswer("Safe cumulative snapshot")]
        )
        let metrics = await observability.providerStreamingMetrics()
        let metric = try #require(metrics.first)
        #expect(metric.providerPartialSnapshotCount == 2)
        #expect(metric.safePartialEventCount == 1)
        await setup.sessionFactory.cleanupFailedAttempt(
            setup.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func everyNonemptyProviderSnapshotCrossesTheStreamingFirewall() async throws {
        let partialCount = 1_000
        let partialSteps = (0..<partialCount).map { index in
            FakeGraphChatProviderStep.event(
                .partialAnswer(
                    GraphChatProviderPartialAnswer(
                        directAnswer: "Safe cumulative answer \(index)",
                        hasInsufficientEvidence: nil
                    )
                )
            )
        }
        let finalAnswer = GraphChatProviderTestSupport.makeFinalAnswer(
            directAnswer: "Safe final answer",
            hasInsufficientEvidence: true
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: partialSteps + [.event(.completed(finalAnswer))]
                )
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let firewall = GraphChatCountingPresentationStreamFirewall()
        let observability = GraphChatProviderExecutorObservabilityRecorder()
        let executor = GraphChatProviderExecutor(
            provider: provider,
            sessionFactory: setup.sessionFactory,
            observability: observability,
            presentationStreamFirewallFactory: { _, _ in firewall }
        )
        let recorder = GraphChatProviderForwardedEventRecorder()

        _ = try await executor.execute(
            resources: setup.resources,
            request: setup.request,
            onEvent: { event in
                recorder.record(event)
            }
        )

        let evaluatedTexts = await firewall.snapshot()
        let metrics = await observability.providerStreamingMetrics()
        let forwardedTexts = recorder.snapshot().compactMap { event -> String? in
            guard case .partialAnswer(let text) = event else {
                return nil
            }
            return text
        }
        #expect(evaluatedTexts.count == partialCount)
        #expect(forwardedTexts == evaluatedTexts)
        #expect(metrics.count == 1)
        #expect(metrics.first?.providerEventCount == partialCount + 1)
        #expect(metrics.first?.providerPartialSnapshotCount == partialCount)
        #expect(metrics.first?.safePartialEventCount == partialCount)
        #expect(
            String(reflecting: metrics).contains("Safe cumulative answer")
                == false
        )
        await setup.sessionFactory.cleanupFailedAttempt(
            setup.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func toolActivitiesAndPartialAnswersRemainInProviderOrder() async throws {
        let firstActivity = GraphChatToolActivity(
            tool: .searchGraph,
            state: .started
        )
        let secondActivity = GraphChatToolActivity(
            tool: .searchGraph,
            state: .finished
        )
        let finalAnswer = GraphChatProviderTestSupport.makeFinalAnswer(
            directAnswer: "Raw final answer",
            hasInsufficientEvidence: true
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(.toolActivity(firstActivity)),
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "First",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(.toolActivity(secondActivity)),
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: "Second",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(.completed(finalAnswer)),
                    ]
                )
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let recorder = GraphChatProviderForwardedEventRecorder()

        let received = try await setup.executor.execute(
            resources: setup.resources,
            request: setup.request,
            onEvent: { event in
                recorder.record(event)
            }
        )

        #expect(received == finalAnswer)
        #expect(
            recorder.snapshot()
                == [
                    .toolActivity(firstActivity),
                    .partialAnswer("First"),
                    .toolActivity(secondActivity),
                    .partialAnswer("Second"),
                ]
        )
        await setup.sessionFactory.cleanupFailedAttempt(
            setup.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func whitespacePartialAnswersAreIgnored() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [
                        .event(
                            .partialAnswer(
                                GraphChatProviderPartialAnswer(
                                    directAnswer: " \n\t ",
                                    hasInsufficientEvidence: nil
                                )
                            )
                        ),
                        .event(
                            .completed(
                                GraphChatProviderTestSupport.makeFinalAnswer(
                                    hasInsufficientEvidence: true
                                )
                            )
                        ),
                    ]
                )
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let recorder = GraphChatProviderForwardedEventRecorder()

        _ = try await setup.executor.execute(
            resources: setup.resources,
            request: setup.request,
            onEvent: { event in
                recorder.record(event)
            }
        )

        #expect(recorder.snapshot().isEmpty)
        await setup.sessionFactory.cleanupFailedAttempt(
            setup.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func finalAnswerIsReturnedButNeverForwardedAsAnAppAnswer() async throws {
        let finalAnswer = GraphChatProviderTestSupport.makeFinalAnswer(
            directAnswer: "Unvalidated provider text",
            hasInsufficientEvidence: false
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [.event(.completed(finalAnswer))]
                )
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let recorder = GraphChatProviderForwardedEventRecorder()

        let received = try await setup.executor.execute(
            resources: setup.resources,
            request: setup.request,
            onEvent: { event in
                recorder.record(event)
            }
        )

        #expect(received == finalAnswer)
        #expect(recorder.snapshot().isEmpty)
        await setup.sessionFactory.requestCancellation(setup.resources)
        #expect(await provider.snapshot().cancelledSessions.isEmpty)
        await setup.sessionFactory.cleanupFailedAttempt(
            setup.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func missingFinalAnswerKeepsTheExistingUnexpectedError() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [FakeGraphChatProviderScript(steps: [])]
        )
        let setup = try await makeSetup(provider: provider)

        do {
            _ = try await setup.executor.execute(
                resources: setup.resources,
                request: setup.request,
                onEvent: { _ in }
            )
            Issue.record("Expected missing final answer failure.")
        } catch let error as GraphChatProviderError {
            #expect(error.code == .unexpected)
            #expect(
                error.message
                    == "Das Modell hat keine vollständige strukturierte Antwort geliefert."
            )
        }
        await setup.sessionFactory.cleanupFailedAttempt(
            setup.resources,
            requestProviderCancellation: false
        )
    }

    @Test
    func cancellationRequestsProviderCancellation() async throws {
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(steps: [.waitForCancellation])
            ]
        )
        let setup = try await makeSetup(provider: provider)
        let task = Task {
            try await setup.executor.execute(
                resources: setup.resources,
                request: setup.request,
                onEvent: { _ in }
            )
        }
        await GraphChatProviderTestSupport.waitUntil {
            await provider.snapshot().streamedSessions.count == 1
        }

        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Expected cancellation.")
        } catch is CancellationError {
        }

        let snapshot = await provider.snapshot()
        #expect(snapshot.cancelledSessions.contains(setup.resources.sessionID))
        await setup.sessionFactory.cleanupFailedAttempt(
            setup.resources,
            requestProviderCancellation: true
        )
    }

    @Test
    func providerFailureIsPropagatedWithoutPrematureAppMapping() async throws {
        let expected = GraphChatProviderError(
            code: .toolFailure,
            message: "Synthetic provider failure"
        )
        let provider = FakeGraphChatModelProvider(
            scripts: [
                FakeGraphChatProviderScript(
                    steps: [.failure(expected)]
                )
            ]
        )
        let setup = try await makeSetup(provider: provider)

        do {
            _ = try await setup.executor.execute(
                resources: setup.resources,
                request: setup.request,
                onEvent: { _ in }
            )
            Issue.record("Expected provider failure.")
        } catch let error as GraphChatProviderError {
            #expect(error == expected)
        }
        await setup.sessionFactory.cleanupFailedAttempt(
            setup.resources,
            requestProviderCancellation: false
        )
    }

    private func makeSetup(
        provider: FakeGraphChatModelProvider
    ) async throws -> (
        sessionFactory: GraphChatProviderSessionFactory,
        executor: GraphChatProviderExecutor,
        resources: GraphChatProviderSessionResources,
        request: GraphChatModelRequest
    ) {
        let sessionFactory = GraphChatProviderTestSupport.makeProviderSessionFactory(
            provider: provider,
            toolRunnerFactory: EvidenceRegisteringFakeToolRunnerFactory()
        )
        let resources = try await GraphChatProviderTestSupport
            .makeInitialProviderResources(sessionFactory: sessionFactory)
        let request = GraphChatProviderRequestBuilder().makeRequest(
            resources: resources,
            question: "Read the active graph.",
            continuationOperation: nil,
            contextProfile: .standard
        )
        return (
            sessionFactory,
            GraphChatProviderExecutor(
                provider: provider,
                sessionFactory: sessionFactory
            ),
            resources,
            request
        )
    }
}
