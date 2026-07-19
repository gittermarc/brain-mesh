import Foundation
import Testing

@testable import BrainMesh

@Suite(.serialized)
@MainActor
struct AppLoadersConfiguratorReadinessTests {

    @Test
    func callBeforeConfigurationCompletionWaitsUntilTheSharedOperationFinishes() async throws {
        try await withFreshConfigurator {
            let store = try BrainMeshTestContainer.makeInMemoryStore()
            let gate = ReadinessTestGate()
            let completionCounter = ReadinessTestCounter()

            AppLoadersConfigurator.setConfigurationOperationForTesting { _ in
                try await gate.suspendUntilReleased()
            }
            AppLoadersConfigurator.configureAllLoaders(with: store.container)
            await gate.waitUntilEntered()

            let waiterStarted = ReadinessTestSignal()
            let waiter = Task {
                await waiterStarted.signal()
                try await AppLoadersConfigurator.waitUntilReady()
                await completionCounter.increment()
            }
            await waiterStarted.wait()
            await Task.yield()

            #expect(AppLoadersConfigurator.readinessStatus == .configuring)
            #expect(await completionCounter.value == 0)

            await gate.release()
            try await waiter.value

            #expect(AppLoadersConfigurator.readinessStatus == .ready)
            #expect(await completionCounter.value == 1)
        }
    }

    @Test
    func configuredRepositoryReadStillWaitsForTheGlobalBarrier() async throws {
        try await withFreshConfigurator {
            let store = try BrainMeshTestContainer.makeInMemoryStore()
            let fixtures = BrainMeshFixtureBuilder(context: store.context)
            let graph = fixtures.makeGraph(name: "Readiness Graph")
            try fixtures.save()

            let gate = ReadinessTestGate()
            let completionCounter = ReadinessTestCounter()
            let repository = GraphReadRepository(
                container: AnyModelContainer(store.container)
            )
            AppLoadersConfigurator.setConfigurationOperationForTesting { _ in
                try await gate.suspendUntilReleased()
            }
            AppLoadersConfigurator.configureAllLoaders(with: store.container)
            await gate.waitUntilEntered()

            let scope = GraphScope(graphID: graph.id)
            let readTask = Task {
                let metadata = try await repository.graphMetadata(in: scope)
                await completionCounter.increment()
                return metadata
            }
            await Task.yield()

            #expect(AppLoadersConfigurator.readinessStatus == .configuring)
            #expect(await completionCounter.value == 0)

            await gate.release()
            let metadata = try await readTask.value

            #expect(metadata?.name == "Readiness Graph")
            #expect(await completionCounter.value == 1)
        }
    }

    @Test
    func parallelReadinessWaitersAreReleasedByTheSameConfiguration() async throws {
        try await withFreshConfigurator {
            let store = try BrainMeshTestContainer.makeInMemoryStore()
            let gate = ReadinessTestGate()
            let completionCounter = ReadinessTestCounter()

            AppLoadersConfigurator.setConfigurationOperationForTesting { _ in
                try await gate.suspendUntilReleased()
            }
            AppLoadersConfigurator.configureAllLoaders(with: store.container)
            await gate.waitUntilEntered()

            let waiters = (0..<8).map { _ in
                Task {
                    try await AppLoadersConfigurator.waitUntilReady()
                    await completionCounter.increment()
                }
            }
            await Task.yield()
            #expect(await completionCounter.value == 0)

            await gate.release()
            for waiter in waiters {
                try await waiter.value
            }

            #expect(AppLoadersConfigurator.readinessStatus == .ready)
            #expect(await completionCounter.value == 8)
        }
    }

    @Test
    func repeatedConfigurationWithTheSameContainerIsIdempotent() async throws {
        try await withFreshConfigurator {
            let store = try BrainMeshTestContainer.makeInMemoryStore()
            let gate = ReadinessTestGate()
            let operationCounter = ReadinessTestCounter()

            AppLoadersConfigurator.setConfigurationOperationForTesting { _ in
                await operationCounter.increment()
                try await gate.suspendUntilReleased()
            }

            for _ in 0..<12 {
                AppLoadersConfigurator.configureAllLoaders(with: store.container)
            }
            await gate.waitUntilEntered()

            #expect(await operationCounter.value == 1)
            #expect(AppLoadersConfigurator.configurationRunCountForTesting == 1)
            #expect(AppLoadersConfigurator.readinessStatus == .configuring)

            await gate.release()
            try await AppLoadersConfigurator.waitUntilReady()

            for _ in 0..<12 {
                AppLoadersConfigurator.configureAllLoaders(with: store.container)
            }
            await Task.yield()

            #expect(await operationCounter.value == 1)
            #expect(AppLoadersConfigurator.configurationRunCountForTesting == 1)
            #expect(AppLoadersConfigurator.readinessStatus == .ready)
        }
    }

    @Test
    func replacementConfigurationDoesNotOverlapItsCancelledPredecessor() async throws {
        try await withFreshConfigurator {
            let firstStore = try BrainMeshTestContainer.makeInMemoryStore()
            let secondStore = try BrainMeshTestContainer.makeInMemoryStore()
            let tracker = ReadinessReplacementTracker(
                firstContainerID: ObjectIdentifier(firstStore.container),
                secondContainerID: ObjectIdentifier(secondStore.container)
            )

            AppLoadersConfigurator.setConfigurationOperationForTesting { container in
                try await tracker.run(containerID: container.identity)
            }

            AppLoadersConfigurator.configureAllLoaders(with: firstStore.container)
            await tracker.waitUntilFirstRunStarted()
            AppLoadersConfigurator.configureAllLoaders(with: secondStore.container)
            try await AppLoadersConfigurator.waitUntilReady()

            let snapshot = await tracker.snapshot()
            #expect(snapshot.startedRuns == [.first, .second])
            #expect(snapshot.maximumConcurrentRuns == 1)
            #expect(AppLoadersConfigurator.configurationRunCountForTesting == 2)
            #expect(AppLoadersConfigurator.readinessStatus == .ready)
        }
    }

    @Test
    func failureAndCancellationProduceStableReadinessStates() async throws {
        try await withFreshConfigurator {
            let failureStore = try BrainMeshTestContainer.makeInMemoryStore()
            AppLoadersConfigurator.setConfigurationOperationForTesting { _ in
                throw ReadinessTestError.expectedFailure
            }
            AppLoadersConfigurator.configureAllLoaders(with: failureStore.container)

            var receivedFailure = false
            do {
                try await AppLoadersConfigurator.waitUntilReady()
            } catch AppLoadersConfiguratorError.configurationFailed(_, _) {
                receivedFailure = true
            }

            #expect(receivedFailure)
            #expect(AppLoadersConfigurator.readinessStatus == .failed)

            await AppLoadersConfigurator.resetForTesting()

            let cancellationStore = try BrainMeshTestContainer.makeInMemoryStore()
            let started = ReadinessTestSignal()
            AppLoadersConfigurator.setConfigurationOperationForTesting { _ in
                await started.signal()
                try await Task.sleep(nanoseconds: 60_000_000_000)
            }
            AppLoadersConfigurator.configureAllLoaders(with: cancellationStore.container)
            await started.wait()
            AppLoadersConfigurator.cancelConfigurationForTesting()

            var receivedCancellation = false
            do {
                try await AppLoadersConfigurator.waitUntilReady()
            } catch AppLoadersConfiguratorError.configurationCancelled {
                receivedCancellation = true
            }

            #expect(receivedCancellation)
            #expect(AppLoadersConfigurator.readinessStatus == .cancelled)
        }
    }

    @Test
    func waitBeforeAnyConfigurationReturnsDefinedError() async throws {
        try await withFreshConfigurator {
            var receivedNotStarted = false
            do {
                try await AppLoadersConfigurator.waitUntilReady()
            } catch AppLoadersConfiguratorError.notStarted {
                receivedNotStarted = true
            }

            #expect(receivedNotStarted)
            #expect(AppLoadersConfigurator.readinessStatus == .notStarted)
        }
    }

    private func withFreshConfigurator(
        _ body: @MainActor () async throws -> Void
    ) async throws {
        await AppLoadersConfigurator.resetForTesting()
        do {
            try await body()
            await AppLoadersConfigurator.resetForTesting()
        } catch {
            await AppLoadersConfigurator.resetForTesting()
            throw error
        }
    }
}

private enum ReadinessTestError: Error {
    case expectedFailure
    case unexpectedContainer
}

private nonisolated enum ReadinessReplacementRun: Equatable, Sendable {
    case first
    case second
}

private nonisolated struct ReadinessReplacementSnapshot: Equatable, Sendable {
    let startedRuns: [ReadinessReplacementRun]
    let maximumConcurrentRuns: Int
}

private actor ReadinessReplacementTracker {
    private let firstContainerID: ObjectIdentifier
    private let secondContainerID: ObjectIdentifier
    private var activeRunCount = 0
    private var maximumConcurrentRuns = 0
    private var startedRuns: [ReadinessReplacementRun] = []
    private var didStartFirstRun = false
    private var firstRunWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        firstContainerID: ObjectIdentifier,
        secondContainerID: ObjectIdentifier
    ) {
        self.firstContainerID = firstContainerID
        self.secondContainerID = secondContainerID
    }

    func run(containerID: ObjectIdentifier) async throws {
        activeRunCount += 1
        maximumConcurrentRuns = max(maximumConcurrentRuns, activeRunCount)
        defer { activeRunCount -= 1 }

        if containerID == firstContainerID {
            startedRuns.append(.first)
            didStartFirstRun = true
            let pending = firstRunWaiters
            firstRunWaiters.removeAll()
            for waiter in pending {
                waiter.resume()
            }
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return
        }

        guard containerID == secondContainerID else {
            throw ReadinessTestError.unexpectedContainer
        }
        startedRuns.append(.second)
    }

    func waitUntilFirstRunStarted() async {
        if didStartFirstRun {
            return
        }
        await withCheckedContinuation { continuation in
            firstRunWaiters.append(continuation)
        }
    }

    func snapshot() -> ReadinessReplacementSnapshot {
        ReadinessReplacementSnapshot(
            startedRuns: startedRuns,
            maximumConcurrentRuns: maximumConcurrentRuns
        )
    }
}

private actor ReadinessTestCounter {
    private(set) var value: Int = 0

    func increment() {
        value += 1
    }
}

private actor ReadinessTestSignal {
    private var isSignalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        guard isSignalled == false else { return }
        isSignalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func wait() async {
        if isSignalled {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor ReadinessTestGate {
    private var hasEntered = false
    private var isReleased = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    func suspendUntilReleased() async throws {
        if hasEntered == false {
            hasEntered = true
            let pending = entryWaiters
            entryWaiters.removeAll()
            for waiter in pending {
                waiter.resume()
            }
        }

        if isReleased {
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                registerReleaseWaiter(id: waiterID, continuation: continuation)
            }
        } onCancel: {
            Task {
                await self.cancelReleaseWaiter(id: waiterID)
            }
        }
    }

    func waitUntilEntered() async {
        if hasEntered {
            return
        }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func release() {
        guard isReleased == false else { return }
        isReleased = true
        let pending = Array(releaseWaiters.values)
        releaseWaiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    private func registerReleaseWaiter(
        id: UUID,
        continuation: CheckedContinuation<Void, Error>
    ) {
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
        } else if isReleased {
            continuation.resume()
        } else {
            releaseWaiters[id] = continuation
        }
    }

    private func cancelReleaseWaiter(id: UUID) {
        guard let continuation = releaseWaiters.removeValue(forKey: id) else {
            return
        }
        continuation.resume(throwing: CancellationError())
    }
}
