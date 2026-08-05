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

    var hasPublicationProblem: Bool {
        disposition != .published ||
        droppedSubscriberCount > 0 ||
        terminatedSubscriberCount > 0
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

/// Narrow subscriber boundary for cache, index, and reconciliation consumers.
nonisolated protocol GraphMutationSubscribing: Sendable {
    func mutationBatches(
        bufferingPolicy: GraphMutationBufferingPolicy
    ) async -> AsyncStream<GraphMutationDelivery>
}

nonisolated struct GraphSchemaRevisionToken: Hashable, Sendable {
    let generation: UUID
    let value: UInt64
}

nonisolated struct GraphSchemaExampleFieldRevision: Hashable, Sendable {
    let fieldID: UUID
    let token: GraphSchemaRevisionToken
}

/// Cheap, graph-specific authority used by the schema cache key.
nonisolated struct GraphSchemaRevision: Hashable, Sendable {
    let graphID: UUID
    let structure: GraphSchemaRevisionToken
    let exampleFields: [GraphSchemaExampleFieldRevision]
}

nonisolated protocol GraphSchemaRevisionProviding: Sendable {
    func schemaRevision(
        in scope: GraphScope,
        sourceScope: GraphSchemaSourceScope
    ) async -> GraphSchemaRevision

    func recordExternalSchemaChange(in scope: GraphScope) async

    func recordExternalExampleValueChanges(
        fieldIDs: Set<UUID>,
        in scope: GraphScope
    ) async
}

/// Process-local search-source revision authority.
///
/// Search readiness must not add operational metadata to the deployed
/// SwiftData/CloudKit domain schema. A fresh process therefore starts with a
/// fresh revision and performs one authoritative foreground reconciliation.
/// Committed local mutation batches advance the revision to their batch ID,
/// which keeps subsequent search and chat readiness checks constant-size.
nonisolated protocol GraphSearchSourceRevisionProviding: Sendable {
    func searchSourceRevision(in scope: GraphScope) async -> UUID
    func recordExternalSearchSourceChange() async
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
actor GraphMutationEventBus:
    GraphMutationPublishing,
    GraphMutationSubscribing,
    GraphSchemaRevisionProviding,
    GraphSearchSourceRevisionProviding
{
    static let shared = GraphMutationEventBus()

    private var continuations: [UUID: AsyncStream<GraphMutationDelivery>.Continuation] = [:]
    private var nextSequenceNumber: UInt64?
    private var isFinished = false
    private var schemaRevisionGeneration = UUID()
    private var schemaRevisionStates: [UUID: SchemaRevisionState] = [:]
    private var searchSourceRevisions: [UUID: UUID] = [:]

    private struct SchemaRevisionState {
        var structure: GraphSchemaRevisionToken
        var exampleFields: [UUID: GraphSchemaRevisionToken]
    }

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
        advanceSchemaRevision(for: batch)
        searchSourceRevisions[batch.graphID] = batch.id
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

    func schemaRevision(
        in scope: GraphScope,
        sourceScope: GraphSchemaSourceScope
    ) -> GraphSchemaRevision {
        let state = schemaRevisionState(for: scope.graphID)
        return GraphSchemaRevision(
            graphID: scope.graphID,
            structure: state.structure,
            exampleFields: sourceScope.exampleFieldIDs.map { fieldID in
                GraphSchemaExampleFieldRevision(
                    fieldID: fieldID,
                    token: state.exampleFields[fieldID]
                        ?? GraphSchemaRevisionToken(
                            generation: schemaRevisionGeneration,
                            value: 0
                        )
                )
            }
        )
    }

    func recordExternalSchemaChange(in scope: GraphScope) {
        var state = schemaRevisionState(for: scope.graphID)
        state.structure = advanced(state.structure)
        schemaRevisionStates[scope.graphID] = state
    }

    func recordExternalExampleValueChanges(
        fieldIDs: Set<UUID>,
        in scope: GraphScope
    ) {
        guard fieldIDs.isEmpty == false else { return }
        var state = schemaRevisionState(for: scope.graphID)
        for fieldID in fieldIDs {
            let token = state.exampleFields[fieldID]
                ?? GraphSchemaRevisionToken(
                    generation: schemaRevisionGeneration,
                    value: 0
                )
            state.exampleFields[fieldID] = advanced(token)
        }
        schemaRevisionStates[scope.graphID] = state
    }

    func searchSourceRevision(in scope: GraphScope) -> UUID {
        if let revision = searchSourceRevisions[scope.graphID] {
            return revision
        }
        let revision = UUID()
        searchSourceRevisions[scope.graphID] = revision
        return revision
    }

    /// A persistent-store remote-change notification does not expose the
    /// affected graph. Clearing every process-local token is conservative: the
    /// active graph is reconciled immediately, while every other graph receives
    /// a new token before its next readiness check.
    func recordExternalSearchSourceChange() {
        searchSourceRevisions.removeAll(keepingCapacity: false)
    }

    /// Reopens an instance with a fresh sequence for deterministic isolated tests.
    func resetForTesting() {
        finishActiveSubscriptions()
        nextSequenceNumber = 1
        isFinished = false
        schemaRevisionGeneration = UUID()
        schemaRevisionStates.removeAll(keepingCapacity: false)
        searchSourceRevisions.removeAll(keepingCapacity: false)
        logReset()
    }

    private func schemaRevisionState(
        for graphID: UUID
    ) -> SchemaRevisionState {
        if let state = schemaRevisionStates[graphID] {
            return state
        }
        let state = SchemaRevisionState(
            structure: GraphSchemaRevisionToken(
                generation: schemaRevisionGeneration,
                value: 0
            ),
            exampleFields: [:]
        )
        schemaRevisionStates[graphID] = state
        return state
    }

    private func advanceSchemaRevision(
        for batch: GraphMutationBatch
    ) {
        var changesStructure = false
        var changedExampleFieldIDs = Set<UUID>()
        for event in batch.events {
            switch event.schemaImpact {
            case .none:
                continue
            case .structure:
                changesStructure = true
            case .exampleFields(let fieldIDs):
                changedExampleFieldIDs.formUnion(fieldIDs)
            }
        }
        guard changesStructure || changedExampleFieldIDs.isEmpty == false else {
            return
        }

        var state = schemaRevisionState(for: batch.graphID)
        if changesStructure {
            state.structure = advanced(state.structure)
        }
        for fieldID in changedExampleFieldIDs {
            let token = state.exampleFields[fieldID]
                ?? GraphSchemaRevisionToken(
                    generation: schemaRevisionGeneration,
                    value: 0
                )
            state.exampleFields[fieldID] = advanced(token)
        }
        schemaRevisionStates[batch.graphID] = state
    }

    private func advanced(
        _ token: GraphSchemaRevisionToken
    ) -> GraphSchemaRevisionToken {
        if token.value == UInt64.max {
            return GraphSchemaRevisionToken(
                generation: UUID(),
                value: 0
            )
        }
        return GraphSchemaRevisionToken(
            generation: token.generation,
            value: token.value + 1
        )
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
