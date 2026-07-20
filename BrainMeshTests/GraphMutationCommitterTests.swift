import Foundation
import SwiftData
import Testing
@testable import BrainMesh

struct GraphMutationCommitterTests {
    @Test
    @MainActor
    func successfulSavePublishesExactlyOneExpectedBatch() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = testUUID(1)
        let entityID = testUUID(2)
        let entity = MetaEntity(name: "Persisted", graphID: graphID)
        entity.id = entityID
        store.context.insert(entity)

        let batch = try GraphMutationBatchFactory.entityCreated(
            graphID: graphID,
            entityID: entityID
        )
        let publisher = GraphMutationReceiptPublisher(
            receipts: [.published(sequenceNumber: 11)]
        )
        let committer = GraphMutationCommitter(publisher: publisher)

        let receipt = try await committer.commit(batch, in: store.context)

        #expect(receipt.disposition == .published)
        #expect(receipt.sequenceNumber == 11)
        #expect(receipt.hasPublicationProblem == false)
        #expect(await publisher.recordedBatches == [batch])

        let descriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { candidate in
                candidate.id == entityID
            }
        )
        #expect(try store.context.fetchCount(descriptor) == 1)
    }

    @Test
    @MainActor
    func failedSavePublishesNothingAndRethrowsTheSaveError() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = testUUID(10)
        let entityID = testUUID(11)
        let entity = MetaEntity(name: "Pending", graphID: graphID)
        entity.id = entityID
        store.context.insert(entity)

        let batch = try GraphMutationBatchFactory.entityCreated(
            graphID: graphID,
            entityID: entityID
        )
        let publisher = GraphMutationReceiptPublisher(
            receipts: [.busFinished]
        )
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                throw GraphMutationCommitterTestError.saveFailed
            }
        )

        var receivedExpectedError = false
        do {
            _ = try await committer.commit(batch, in: store.context)
        } catch GraphMutationCommitterTestError.saveFailed {
            receivedExpectedError = true
        }

        #expect(receivedExpectedError)
        #expect(await publisher.recordedBatches.isEmpty)

        let descriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { candidate in
                candidate.id == entityID
            }
        )
        #expect(try store.context.fetchCount(descriptor) == 0)
    }

    @Test
    @MainActor
    func saveFailureAndPublishProblemRemainDistinguishable() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = testUUID(20)
        let batch = try GraphMutationBatchFactory.detailSchemaChanged(
            graphID: graphID,
            ownerEntityID: testUUID(21),
            definitionIDs: [testUUID(22)]
        )

        let publishProblemPublisher = GraphMutationReceiptPublisher(
            receipts: [.busFinished]
        )
        let successfulCommitter = GraphMutationCommitter(
            publisher: publishProblemPublisher
        )
        let publishReceipt = try await successfulCommitter.commit(
            batch,
            in: store.context
        )

        #expect(publishReceipt.disposition == .busFinished)
        #expect(publishReceipt.hasPublicationProblem)
        #expect(await publishProblemPublisher.recordedBatches == [batch])

        let saveFailurePublisher = GraphMutationReceiptPublisher(
            receipts: [.published(sequenceNumber: 1)]
        )
        let failingCommitter = GraphMutationCommitter(
            publisher: saveFailurePublisher,
            saveOperation: { _ in
                throw GraphMutationCommitterTestError.saveFailed
            }
        )

        await #expect(throws: GraphMutationCommitterTestError.saveFailed) {
            _ = try await failingCommitter.commit(batch, in: store.context)
        }
        #expect(await saveFailurePublisher.recordedBatches.isEmpty)
    }

    @Test
    @MainActor
    func publishReceiptsDoNotRetroactivelyFailSuccessfulSaves() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = testUUID(30)
        let batch = try GraphMutationBatchFactory.detailSchemaChanged(
            graphID: graphID,
            ownerEntityID: testUUID(31),
            definitionIDs: [testUUID(32)]
        )
        let expectedReceipts: [GraphMutationPublishReceipt] = [
            .busFinished,
            .sequenceExhausted(subscriberCount: 2),
            GraphMutationPublishReceipt(
                disposition: .published,
                sequenceNumber: 41,
                subscriberCount: 2,
                enqueuedSubscriberCount: 1,
                droppedSubscriberCount: 1,
                terminatedSubscriberCount: 0
            ),
            GraphMutationPublishReceipt(
                disposition: .published,
                sequenceNumber: 42,
                subscriberCount: 2,
                enqueuedSubscriberCount: 1,
                droppedSubscriberCount: 0,
                terminatedSubscriberCount: 1
            )
        ]
        let publisher = GraphMutationReceiptPublisher(receipts: expectedReceipts)
        let committer = GraphMutationCommitter(publisher: publisher)

        var actualReceipts: [GraphMutationPublishReceipt] = []
        for _ in expectedReceipts {
            actualReceipts.append(
                try await committer.commit(batch, in: store.context)
            )
        }

        #expect(actualReceipts == expectedReceipts)
        #expect(actualReceipts.allSatisfy { $0.hasPublicationProblem })
        #expect(await publisher.recordedBatches == Array(repeating: batch, count: 4))
    }

    @Test
    @MainActor
    func cancellationAfterSuccessfulSaveStillPublishes() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = testUUID(50)
        let entityID = testUUID(51)
        let entity = MetaEntity(name: "Cancellation Boundary", graphID: graphID)
        entity.id = entityID
        store.context.insert(entity)

        let batch = try GraphMutationBatchFactory.entityCreated(
            graphID: graphID,
            entityID: entityID
        )
        let publisher = GraphMutationReceiptPublisher(
            receipts: [.published(sequenceNumber: 51)]
        )
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { context in
                try context.save()
                withUnsafeCurrentTask { task in
                    task?.cancel()
                }
            }
        )

        let task = Task { @MainActor in
            try await committer.commit(batch, in: store.context)
        }
        let receipt = try await task.value

        #expect(task.isCancelled)
        #expect(receipt.disposition == .published)
        #expect(await publisher.recordedBatches == [batch])

        let descriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { candidate in
                candidate.id == entityID
            }
        )
        #expect(try store.context.fetchCount(descriptor) == 1)
    }

    @Test
    @MainActor
    func cancellationBeforeSaveRollsBackAndPublishesNothing() async throws {
        let store = try BrainMeshTestContainer.makeInMemoryStore()
        let graphID = testUUID(55)
        let entityID = testUUID(56)
        let entity = MetaEntity(name: "Cancelled Before Save", graphID: graphID)
        entity.id = entityID
        store.context.insert(entity)

        let batch = try GraphMutationBatchFactory.entityCreated(
            graphID: graphID,
            entityID: entityID
        )
        let publisher = GraphMutationReceiptPublisher(
            receipts: [.published(sequenceNumber: 55)]
        )
        var saveCallCount = 0
        let committer = GraphMutationCommitter(
            publisher: publisher,
            saveOperation: { _ in
                saveCallCount += 1
            }
        )

        let task = Task { @MainActor in
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await committer.commit(batch, in: store.context)
        }

        var receivedCancellation = false
        do {
            _ = try await task.value
        } catch is CancellationError {
            receivedCancellation = true
        }

        #expect(receivedCancellation)
        #expect(saveCallCount == 0)
        #expect(await publisher.recordedBatches.isEmpty)

        let descriptor = FetchDescriptor<MetaEntity>(
            predicate: #Predicate { candidate in
                candidate.id == entityID
            }
        )
        #expect(try store.context.fetchCount(descriptor) == 0)
    }

    @Test
    func mixedGraphBatchIsRejectedBeforeItCanBeCommitted() {
        let firstGraphID = testUUID(60)
        let secondGraphID = testUUID(61)
        let events = [
            GraphMutationEvent(
                graphID: firstGraphID,
                kind: .entityCreated,
                references: [.node(NodeRefKey(kind: .entity, id: testUUID(62)))]
            ),
            GraphMutationEvent(
                graphID: secondGraphID,
                kind: .attributeCreated,
                references: [.node(NodeRefKey(kind: .attribute, id: testUUID(63)))]
            )
        ]

        #expect(throws: GraphMutationBatchError.mixedGraphScopes) {
            _ = try GraphMutationBatch(
                graphID: firstGraphID,
                events: events
            )
        }
    }
}

private enum GraphMutationCommitterTestError: Error {
    case saveFailed
}

private actor GraphMutationReceiptPublisher: GraphMutationPublishing {
    private var receipts: [GraphMutationPublishReceipt]
    private var batches: [GraphMutationBatch] = []

    init(receipts: [GraphMutationPublishReceipt]) {
        self.receipts = receipts
    }

    var recordedBatches: [GraphMutationBatch] {
        batches
    }

    func publishCommitted(
        _ batch: GraphMutationBatch
    ) async -> GraphMutationPublishReceipt {
        batches.append(batch)
        guard !receipts.isEmpty else {
            return .published(sequenceNumber: UInt64(batches.count))
        }
        return receipts.removeFirst()
    }
}

private extension GraphMutationPublishReceipt {
    static func published(
        sequenceNumber: UInt64
    ) -> GraphMutationPublishReceipt {
        GraphMutationPublishReceipt(
            disposition: .published,
            sequenceNumber: sequenceNumber,
            subscriberCount: 1,
            enqueuedSubscriberCount: 1,
            droppedSubscriberCount: 0,
            terminatedSubscriberCount: 0
        )
    }
}

private func testUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
}
