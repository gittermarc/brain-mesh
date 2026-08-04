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

struct GraphChatProviderExecutorTests {
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
