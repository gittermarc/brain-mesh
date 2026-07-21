import Foundation
import Testing
@testable import BrainMesh

struct GraphSearchIndexerStatusTests {
    @Test
    func statusMovesFromNotInitializedThroughBuildingToReady() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, _ in
            #expect(await indexer.status(for: fixture.scope) == .notInitialized)
            await source.setSnapshotDelay(nanoseconds: 200_000_000)

            let build = Task {
                try await indexer.ensureIndexed(scope: fixture.scope)
            }
            try await waitForGraphSearchIndexerCondition {
                await source.readCount(for: .snapshot(fixture.graphID)) == 1
            }

            let building = await indexer.status(for: fixture.scope)
            #expect(building.state == .building)
            #expect(building.progress?.processedSources == 0)
            #expect(building.documentCount == nil)

            try await build.value
            let ready = await indexer.status(for: fixture.scope)
            #expect(ready == .ready(documentCount: 22))
        }
    }

    @Test
    func progressFractionIsValueOnlyAndClamped() {
        let half = GraphSearchIndexProgress(
            processedSources: 5,
            estimatedSources: 10
        )
        let complete = GraphSearchIndexProgress(
            processedSources: 15,
            estimatedSources: 10
        )
        let unknown = GraphSearchIndexProgress(
            processedSources: 5,
            estimatedSources: nil
        )

        #expect(half.fractionCompleted == 0.5)
        #expect(complete.fractionCompleted == 1)
        #expect(unknown.fractionCompleted == nil)
    }

    @Test
    func failureIsVisibleAndLaterEnsureIndexedHealsIt() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, source, store in
            await source.setFailure(true, graphID: fixture.graphID)
            await #expect(throws: GraphSearchIndexerTestFailure.self) {
                try await indexer.ensureIndexed(scope: fixture.scope)
            }

            let failed = await indexer.status(for: fixture.scope)
            #expect(failed.state == .failed)
            #expect(failed.failure?.errorType.contains("GraphSearchIndexerTestFailure") == true)
            #expect(failed.failure?.message.isEmpty == false)
            #expect(try await store.documentCount(in: fixture.graphID) == 0)

            await source.setFailure(false, graphID: fixture.graphID)
            try await indexer.ensureIndexed(scope: fixture.scope)

            #expect(await indexer.status(for: fixture.scope) == .ready(documentCount: 22))
            #expect(try await store.documentCount(in: fixture.graphID) == 22)
        }
    }

    @Test
    func stoppingTheConsumerMarksKnownGraphsStaleWithoutDeletingDocuments() async throws {
        let fixture = GraphSearchIndexerFixture()

        try await withGraphSearchIndexerTestEnvironment(
            snapshots: [fixture.snapshot]
        ) { indexer, _, store in
            try await indexer.ensureIndexed(scope: fixture.scope)
            await indexer.startEventConsumer()
            await indexer.stop()

            #expect(await indexer.status(for: fixture.scope) == .stale(documentCount: 22))
            #expect(try await store.documentCount(in: fixture.graphID) == 22)
        }
    }

    @Test
    func startingTheEventConsumerTwiceCreatesExactlyOneSubscription() async throws {
        let fixture = GraphSearchIndexerFixture()
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback
        )
        let source = GraphSearchIndexerTestSource(snapshots: [fixture.snapshot])
        let bus = GraphMutationEventBus()
        let indexer = GraphSearchIndexer(
            sourceReader: source,
            store: store,
            subscriber: bus
        )

        do {
            await indexer.startEventConsumer()
            await indexer.startEventConsumer()
            try await waitForGraphSearchIndexerCondition {
                await bus.subscriberCountForTesting == 1
            }

            #expect(await indexer.hasActiveSubscriptionForTesting())
            #expect(await bus.subscriberCountForTesting == 1)

            await indexer.stop()
            try await waitForGraphSearchIndexerCondition {
                await bus.subscriberCountForTesting == 0
            }
            #expect(await bus.subscriberCountForTesting == 0)

            try await store.close()
            location.remove()
        } catch {
            await indexer.resetForTesting()
            do {
                try await store.close()
            } catch let closeError {
                Issue.record("Failed to close status test store: \(closeError)")
            }
            location.remove()
            throw error
        }
    }

    @Test
    func startedEventConsumerProcessesCommittedBusDeliveries() async throws {
        var fixture = GraphSearchIndexerFixture()
        let location = try GraphSearchIndexTestSupport.makeLocation()
        let store = GraphSearchIndexStore(
            databaseURL: location.databaseURL,
            backendPreference: .indexedFallback
        )
        let source = GraphSearchIndexerTestSource(snapshots: [fixture.snapshot])
        let bus = GraphMutationEventBus()
        let indexer = GraphSearchIndexer(
            sourceReader: source,
            store: store,
            subscriber: bus
        )

        do {
            try await indexer.ensureIndexed(scope: fixture.scope)
            await indexer.startEventConsumer()
            try await waitForGraphSearchIndexerCondition {
                await bus.subscriberCountForTesting == 1
            }

            fixture.updatePrimaryEntityNotes("Delivered through the bus")
            await source.setSnapshot(fixture.snapshot)
            let batch = try GraphMutationBatchFactory.nodeUpdated(
                graphID: fixture.graphID,
                node: NodeRefKey(
                    kind: .entity,
                    id: fixture.primaryEntityID
                )
            )
            let receipt = await bus.publishCommitted(batch)
            try await waitForGraphSearchIndexerCondition {
                await indexer.processedBatchCountForTesting() == 1
            }

            #expect(receipt.disposition == .published)
            #expect(receipt.subscriberCount == 1)
            #expect(try await store.documents(in: fixture.graphID).contains {
                $0.documentKind == .entityNotes
                    && $0.normalizedSearchText.contains(
                        BMSearch.fold("Delivered through the bus")
                    )
            })

            await indexer.resetForTesting()
            try await store.close()
            location.remove()
        } catch {
            await indexer.resetForTesting()
            do {
                try await store.close()
            } catch let closeError {
                Issue.record("Failed to close event-consumer test store: \(closeError)")
            }
            location.remove()
            throw error
        }
    }
}
