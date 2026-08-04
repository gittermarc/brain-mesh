//
//  GraphChatStreamingBackpressureTests.swift
//  BrainMeshTests
//

import Foundation
import Testing

@testable import BrainMesh

private actor GraphChatManualStreamingClock {
    private struct Sleeper {
        let deadline: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private var currentInstant: UInt64 = 0
    private var sleepers: [UUID: Sleeper] = [:]

    func now() -> UInt64 {
        currentInstant
    }

    func sleep(until deadline: UInt64) async throws {
        guard deadline > currentInstant else {
            return
        }
        let sleeperID = UUID()
        try await withTaskCancellationHandler(
            operation: {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    registerSleeper(
                        id: sleeperID,
                        deadline: deadline,
                        continuation: continuation
                    )
                }
            },
            onCancel: {
                Task {
                    await self.cancelSleeper(sleeperID)
                }
            }
        )
    }

    func advance(to instant: UInt64) {
        precondition(instant >= currentInstant)
        currentInstant = instant
        let readyIDs = sleepers.compactMap { id, sleeper in
            sleeper.deadline <= instant ? id : nil
        }
        for id in readyIDs {
            sleepers.removeValue(forKey: id)?.continuation.resume()
        }
    }

    func sleeperCount() -> Int {
        sleepers.count
    }

    private func cancelSleeper(_ id: UUID) {
        sleepers.removeValue(forKey: id)?.continuation.resume(
            throwing: CancellationError()
        )
    }

    private func registerSleeper(
        id: UUID,
        deadline: UInt64,
        continuation: CheckedContinuation<Void, Error>
    ) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
        } else if deadline <= currentInstant {
            continuation.resume()
        } else {
            sleepers[id] = Sleeper(
                deadline: deadline,
                continuation: continuation
            )
        }
    }
}

@MainActor
private final class GraphChatStreamingPublicationRecorder {
    private(set) var publications: [GraphChatStreamingUIPublication] = []

    func accept(_ publication: GraphChatStreamingUIPublication) -> Bool {
        publications.append(publication)
        return true
    }
}

@Suite("Graph chat streaming backpressure")
@MainActor
struct GraphChatStreamingBackpressureTests {
    @Test
    func oneThousandPartialBurstStaysBelowTwentyPublicationsPerSimulatedSecond() async {
        let setup = makeSetup()
        let consumption = Task {
            await setup.coordinator.consume(setup.stream) { publication in
                setup.recorder.accept(publication)
            }
        }

        for index in 0..<1_000 {
            setup.continuation.yield(
                .partialAnswer("Safe cumulative answer \(index)")
            )
        }
        await waitUntil {
            setup.recorder.publications.isEmpty == false
        }
        await waitUntilAsync {
            await setup.clock.sleeperCount() > 0
        }
        await setup.clock.advance(to: 1_000_000_000)
        await Task.yield()
        setup.continuation.finish()

        let statistics = await consumption.value
        #expect(statistics.sourceEventCount == 1_000)
        #expect(statistics.partialEventCount == 1_000)
        #expect(statistics.safeUIPublicationCount <= 20)
        #expect(statistics.rateLimitedPublicationCount <= 20)
        #expect(setup.recorder.publications.count <= 20)
        #expect(
            setup.recorder.publications.allSatisfy {
                $0.reason != .terminal
            }
        )
    }

    @Test
    func terminalStateBypassesThrottleAndRetainsTheLatestSafeSnapshot() async throws {
        let setup = makeSetup()
        let artifactID = GraphChatAnswerArtifactID()
        let evidence = GraphChatProviderTestSupport.makeEvidence()
        let answer = GraphChatAnswer(
            state: .answer,
            directAnswer: "Complete safe final",
            sections: [
                GraphChatAnswerSection(
                    title: "Details",
                    text: "Grounded section",
                    evidenceIDs: [evidence.id],
                    artifactIDs: [artifactID]
                )
            ],
            evidence: [evidence],
            artifactIDs: [artifactID],
            hasInsufficientEvidence: false
        )
        let consumption = Task {
            await setup.coordinator.consume(setup.stream) { publication in
                setup.recorder.accept(publication)
            }
        }

        setup.continuation.yield(.partialAnswer("First safe partial"))
        await waitUntil {
            setup.recorder.publications.count == 1
        }
        setup.continuation.yield(.partialAnswer("Latest safe partial"))
        await waitUntilAsync {
            await setup.clock.sleeperCount() == 1
        }
        setup.continuation.yield(.completed(answer))
        setup.continuation.finish()

        let statistics = await consumption.value
        let terminal = try #require(setup.recorder.publications.last)
        #expect(setup.recorder.publications.count == 2)
        #expect(terminal.reason == .terminal)
        #expect(
            terminal.events
                == [
                    .partialAnswer("Latest safe partial"),
                    .completed(answer),
                ]
        )
        #expect(statistics.terminalEvent == .completed(answer))
        #expect(answer.evidence == [evidence])
        #expect(answer.sections.first?.artifactIDs == [artifactID])
        #expect(await setup.clock.now() == 0)
    }

    @Test
    func cancellationRejectsLatePartialsAndTerminalEvents() async {
        let setup = makeSetup()
        let consumption = Task {
            await setup.coordinator.consume(setup.stream) { publication in
                setup.recorder.accept(publication)
            }
        }

        setup.continuation.yield(.partialAnswer("Accepted"))
        await waitUntil {
            setup.recorder.publications.count == 1
        }
        await setup.coordinator.cancel()
        setup.continuation.yield(.partialAnswer("Must not publish"))
        setup.continuation.yield(
            .completed(
                GraphChatUITestSupport.finalAnswer(
                    directAnswer: "Must not complete"
                )
            )
        )
        setup.continuation.finish()

        let statistics = await consumption.value
        #expect(setup.recorder.publications.count == 1)
        #expect(statistics.terminalEvent == nil)
    }

    @Test
    func replacementTurnUsesAnIndependentAggregator() async {
        let oldTurn = makeSetup()
        let oldConsumption = Task {
            await oldTurn.coordinator.consume(oldTurn.stream) { publication in
                oldTurn.recorder.accept(publication)
            }
        }
        oldTurn.continuation.yield(.partialAnswer("Old safe partial"))
        await waitUntil {
            oldTurn.recorder.publications.count == 1
        }
        await oldTurn.coordinator.cancel()
        oldTurn.continuation.yield(.partialAnswer("Late old partial"))
        oldTurn.continuation.finish()

        let newTurn = makeSetup()
        let newAnswer = GraphChatUITestSupport.finalAnswer(
            directAnswer: "New safe final"
        )
        let newConsumption = Task {
            await newTurn.coordinator.consume(newTurn.stream) { publication in
                newTurn.recorder.accept(publication)
            }
        }
        newTurn.continuation.yield(.partialAnswer("New safe partial"))
        newTurn.continuation.yield(.completed(newAnswer))
        newTurn.continuation.finish()

        _ = await oldConsumption.value
        let newStatistics = await newConsumption.value
        #expect(
            newTurn.recorder.publications.flatMap(\.events).contains(
                .partialAnswer("Late old partial")
            ) == false
        )
        #expect(newStatistics.terminalEvent == .completed(newAnswer))
    }

    private func makeSetup() -> (
        coordinator: GraphChatStreamingBackpressureCoordinator,
        clock: GraphChatManualStreamingClock,
        recorder: GraphChatStreamingPublicationRecorder,
        stream: GraphChatEventStream,
        continuation: GraphChatEventStream.Continuation
    ) {
        let clock = GraphChatManualStreamingClock()
        let streamPair = GraphChatEventStream.makeStream()
        return (
            GraphChatStreamingBackpressureCoordinator(
                configuration: GraphChatStreamingBackpressureConfiguration(
                    maximumPublicationsPerSecond: 20
                ),
                clock: GraphChatStreamingClock(
                    now: {
                        await clock.now()
                    },
                    sleepUntil: { deadline in
                        try await clock.sleep(until: deadline)
                    }
                )
            ),
            clock,
            GraphChatStreamingPublicationRecorder(),
            streamPair.stream,
            streamPair.continuation
        )
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<20_000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Condition was not reached within deterministic yields.")
    }

    private func waitUntilAsync(
        _ condition: @escaping @MainActor () async -> Bool
    ) async {
        for _ in 0..<20_000 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Async condition was not reached within deterministic yields.")
    }
}
