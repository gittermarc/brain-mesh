//
//  GraphMutationEventBus.swift
//  BrainMesh
//
//  Actor-safe multicast delivery for committed graph mutation batches.
//

import Foundation

#if canImport(os)
import os
#endif

/// Buffering selected independently for each subscriber.
///
/// The default is unbounded because the bus has no persistent replay history in this slice and
/// silently losing an incremental mutation could make a future index inconsistent. Consumers
/// that choose a bounded policy must be able to reconcile after observed overflow diagnostics.
/// Non-positive bounded capacities are normalized to one.
nonisolated enum GraphMutationBufferingPolicy: Hashable, Sendable {
    case unbounded
    case bufferingNewest(Int)
    case bufferingOldest(Int)

    static let `default`: GraphMutationBufferingPolicy = .unbounded

    fileprivate var asyncStreamPolicy:
        AsyncStream<GraphMutationDelivery>.Continuation.BufferingPolicy
    {
        switch self {
        case .unbounded:
            return .unbounded
        case .bufferingNewest(let limit):
            return .bufferingNewest(max(1, limit))
        case .bufferingOldest(let limit):
            return .bufferingOldest(max(1, limit))
        }
    }
}

nonisolated enum GraphMutationPublishDisposition: Hashable, Sendable {
    case published
    case busFinished
    case sequenceExhausted
}

/// Technical delivery diagnostics. No graph identifiers or user data are included.
nonisolated struct GraphMutationPublishReceipt: Hashable, Sendable {
    let disposition: GraphMutationPublishDisposition
    let sequenceNumber: UInt64?
    let subscriberCount: Int
    let enqueuedSubscriberCount: Int
    let droppedSubscriberCount: Int
    let terminatedSubscriberCount: Int

    static let busFinished = GraphMutationPublishReceipt(
        disposition: .busFinished,
        sequenceNumber: nil,
        subscriberCount: 0,
        enqueuedSubscriberCount: 0,
        droppedSubscriberCount: 0,
        terminatedSubscriberCount: 0
    )

    static func sequenceExhausted(
        subscriberCount: Int
    ) -> GraphMutationPublishReceipt {
        GraphMutationPublishReceipt(
            disposition: .sequenceExhausted,
            sequenceNumber: nil,
            subscriberCount: subscriberCount,
            enqueuedSubscriberCount: 0,
            droppedSubscriberCount: 0,
            terminatedSubscriberCount: 0
        )
    }
}

/// Narrow post-commit publisher boundary for write services and test recorders.
///
/// Callers must invoke this API only after their `ModelContext.save()` has completed successfully.
/// There is intentionally no pre-commit publication API.
nonisolated protocol GraphMutationPublishing: Sendable {
    @discardableResult
    func publishCommitted(
        _ batch: GraphMutationBatch
    ) async -> GraphMutationPublishReceipt
}

extension GraphMutationPublishing {
    /// Runs the persistence commit first and publishes only when the commit returns successfully.
    ///
    /// Production callers pass `ModelContext.save()` through `save`. There is deliberately no
    /// cancellation check between the successful commit and publication: once data is durable,
    /// local consumers still need the corresponding event batch.
    @MainActor
    @discardableResult
    func saveAndPublish(
        _ batch: GraphMutationBatch,
        save: () throws -> Void
    ) async throws -> GraphMutationPublishReceipt {
        try save()
        return await publishCommitted(batch)
    }
}

/// Narrow subscriber boundary for cache, index, and reconciliation consumers.
nonisolated protocol GraphMutationSubscribing: Sendable {
    func mutationBatches(
        bufferingPolicy: GraphMutationBufferingPolicy
    ) async -> AsyncStream<GraphMutationDelivery>
}

extension GraphMutationSubscribing {
    func mutationBatches() async -> AsyncStream<GraphMutationDelivery> {
        await mutationBatches(bufferingPolicy: .default)
    }
}

/// In-memory multicast bus for committed graph mutation batches.
///
/// Each subscription owns an independent `AsyncStream` and buffer. Publishing only performs
/// synchronous `yield` calls while actor-isolated and never awaits subscriber work. The bus keeps
/// no persistent history, and local delivery does not replace reconciliation for CloudKit changes
/// received from another device.
actor GraphMutationEventBus: GraphMutationPublishing, GraphMutationSubscribing {
    static let shared = GraphMutationEventBus()

    private var continuations: [UUID: AsyncStream<GraphMutationDelivery>.Continuation] = [:]
    private var nextSequenceNumber: UInt64?
    private var isFinished = false

    init(startingSequenceNumber: UInt64 = 1) {
        nextSequenceNumber = startingSequenceNumber
    }

    func mutationBatches(
        bufferingPolicy: GraphMutationBufferingPolicy = .default
    ) async -> AsyncStream<GraphMutationDelivery> {
        let subscriberID = UUID()
        let pair = AsyncStream<GraphMutationDelivery>.makeStream(
            bufferingPolicy: bufferingPolicy.asyncStreamPolicy
        )

        pair.continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeSubscriber(id: subscriberID)
            }
        }

        guard isFinished == false else {
            pair.continuation.finish()
            return pair.stream
        }

        continuations[subscriberID] = pair.continuation
        logSubscriberCount(action: "added", count: continuations.count)
        return pair.stream
    }

    /// Publishes one already committed batch to every currently active subscriber.
    ///
    /// Delivery order is actor-serialized. Every subscriber receives the same delivery value for
    /// a publication unless that subscriber's explicitly selected bounded buffer drops an item.
    /// This post-commit path intentionally performs no cancellation check.
    @discardableResult
    func publishCommitted(
        _ batch: GraphMutationBatch
    ) async -> GraphMutationPublishReceipt {
        guard isFinished == false else {
            logFinishedPublishIgnored()
            return .busFinished
        }

        guard let sequenceNumber = nextSequenceNumber else {
            logSequenceExhausted()
            return .sequenceExhausted(
                subscriberCount: continuations.count
            )
        }
        if sequenceNumber == UInt64.max {
            nextSequenceNumber = nil
        } else {
            nextSequenceNumber = sequenceNumber + 1
        }

        let delivery = GraphMutationDelivery(
            sequenceNumber: sequenceNumber,
            publishedAt: Date(),
            batch: batch
        )
        let activeContinuations = continuations
        var enqueuedCount = 0
        var droppedCount = 0
        var terminatedCount = 0

        for (subscriberID, continuation) in activeContinuations {
            switch continuation.yield(delivery) {
            case .enqueued:
                enqueuedCount += 1
            case .dropped(let droppedDelivery):
                droppedCount += 1
                if droppedDelivery != delivery {
                    enqueuedCount += 1
                }
            case .terminated:
                terminatedCount += 1
                continuations.removeValue(forKey: subscriberID)
            @unknown default:
                terminatedCount += 1
                continuations.removeValue(forKey: subscriberID)
            }
        }

        let receipt = GraphMutationPublishReceipt(
            disposition: .published,
            sequenceNumber: sequenceNumber,
            subscriberCount: activeContinuations.count,
            enqueuedSubscriberCount: enqueuedCount,
            droppedSubscriberCount: droppedCount,
            terminatedSubscriberCount: terminatedCount
        )
        logPublication(
            sequenceNumber: sequenceNumber,
            eventCount: batch.events.count,
            subscriberCount: activeContinuations.count,
            droppedCount: droppedCount
        )
        return receipt
    }

    /// Finishes all active streams. A finished instance rejects subsequent publications and
    /// immediately finishes new subscriptions until it is reset for a test.
    func finish() {
        finishActiveSubscriptions()
        isFinished = true
        logFinished()
    }

    var subscriberCountForTesting: Int {
        continuations.count
    }

    var isFinishedForTesting: Bool {
        isFinished
    }

    var nextSequenceNumberForTesting: UInt64? {
        nextSequenceNumber
    }

    /// Reopens an instance with a fresh sequence for deterministic isolated tests.
    func resetForTesting() {
        finishActiveSubscriptions()
        nextSequenceNumber = 1
        isFinished = false
        logReset()
    }

    private func removeSubscriber(id: UUID) {
        guard continuations.removeValue(forKey: id) != nil else {
            return
        }
        logSubscriberCount(action: "removed", count: continuations.count)
    }

    private func finishActiveSubscriptions() {
        let activeContinuations = Array(continuations.values)
        continuations.removeAll(keepingCapacity: false)
        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func logSubscriberCount(action: String, count: Int) {
        #if canImport(os)
        BMLog.mutationEvents.debug(
            "Subscriber \(action, privacy: .public) active=\(count, privacy: .public)"
        )
        #endif
    }

    private func logPublication(
        sequenceNumber: UInt64,
        eventCount: Int,
        subscriberCount: Int,
        droppedCount: Int
    ) {
        #if canImport(os)
        BMLog.mutationEvents.debug(
            "Committed batch published sequence=\(sequenceNumber, privacy: .public) events=\(eventCount, privacy: .public) subscribers=\(subscriberCount, privacy: .public) dropped=\(droppedCount, privacy: .public)"
        )
        #endif
    }

    private func logFinishedPublishIgnored() {
        #if canImport(os)
        BMLog.mutationEvents.notice("Committed batch ignored because the bus is finished")
        #endif
    }

    private func logSequenceExhausted() {
        #if canImport(os)
        BMLog.mutationEvents.error("Mutation publication sequence exhausted")
        #endif
    }

    private func logFinished() {
        #if canImport(os)
        BMLog.mutationEvents.info("Mutation event bus finished")
        #endif
    }

    private func logReset() {
        #if canImport(os)
        BMLog.mutationEvents.debug("Mutation event bus reset")
        #endif
    }
}
