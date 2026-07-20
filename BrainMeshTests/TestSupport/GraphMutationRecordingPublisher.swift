import Foundation
@testable import BrainMesh

/// Thread-safe test publisher for committed graph mutation batches.
///
/// The nonisolated protocol conformance lives on a regular final class. Mutable recorder state is
/// protected by a private actor, so the test double remains fully checked by Swift concurrency.
nonisolated final class GraphMutationRecordingPublisher: GraphMutationPublishing {
    private actor Storage {
        private var batches: [GraphMutationBatch] = []
        private var receipts: [GraphMutationPublishReceipt]

        init(receipts: [GraphMutationPublishReceipt]) {
            self.receipts = receipts
        }

        func publishCommitted(
            _ batch: GraphMutationBatch
        ) -> GraphMutationPublishReceipt {
            batches.append(batch)

            if receipts.isEmpty == false {
                return receipts.removeFirst()
            }

            return GraphMutationPublishReceipt(
                disposition: .published,
                sequenceNumber: UInt64(batches.count),
                subscriberCount: 1,
                enqueuedSubscriberCount: 1,
                droppedSubscriberCount: 0,
                terminatedSubscriberCount: 0
            )
        }

        var recordedBatches: [GraphMutationBatch] {
            batches
        }
    }

    private let storage: Storage

    init(receipts: [GraphMutationPublishReceipt] = []) {
        storage = Storage(receipts: receipts)
    }

    func publishCommitted(
        _ batch: GraphMutationBatch
    ) async -> GraphMutationPublishReceipt {
        await storage.publishCommitted(batch)
    }

    var recordedBatches: [GraphMutationBatch] {
        get async {
            await storage.recordedBatches
        }
    }
}

enum GraphMutationServiceTestError: Error, Equatable {
    case saveFailed
}
