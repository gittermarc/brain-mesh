//
//  GraphSearchIndexReconciler.swift
//  BrainMesh
//
//  Coalesced graph-scoped reconciliation for changes that bypass local mutation events.
//

import Foundation
import os

nonisolated enum GraphSearchIndexReconciliationReason: String, Codable, CaseIterable, Sendable {
    case firstSearch
    case chatSession
    case foreground
    case importOrReplace
    case dedupe
    case indexFailure
    case explicit
}

nonisolated enum GraphSearchIndexReadinessOutcome: String, Codable, CaseIterable, Sendable {
    case ready
    case reconciled
    case rebuilt
    case unavailable
    case cancelled
    case failed
}

nonisolated struct GraphSearchIndexReconciliationMetrics: Equatable, Sendable {
    let checkedSourceCount: Int
    let addedSourceCount: Int
    let changedSourceCount: Int
    let deletedSourceCount: Int
    let fullRebuild: Bool
    let durationMilliseconds: Double

    var changedSourceTotal: Int {
        addedSourceCount + changedSourceCount + deletedSourceCount
    }
}

nonisolated struct GraphSearchIndexReadinessResult: Equatable, Sendable {
    let graphID: UUID
    let reason: GraphSearchIndexReconciliationReason
    let outcome: GraphSearchIndexReadinessOutcome
    let isIndexUsable: Bool
    let documentCount: Int?
    let metrics: GraphSearchIndexReconciliationMetrics?
    let failure: GraphSearchIndexFailure?

    func replacingReason(
        with reason: GraphSearchIndexReconciliationReason
    ) -> GraphSearchIndexReadinessResult {
        GraphSearchIndexReadinessResult(
            graphID: graphID,
            reason: reason,
            outcome: outcome,
            isIndexUsable: isIndexUsable,
            documentCount: documentCount,
            metrics: metrics,
            failure: failure
        )
    }

    static func cancelled(
        graphID: UUID,
        reason: GraphSearchIndexReconciliationReason,
        isIndexUsable: Bool = false,
        documentCount: Int? = nil
    ) -> GraphSearchIndexReadinessResult {
        GraphSearchIndexReadinessResult(
            graphID: graphID,
            reason: reason,
            outcome: .cancelled,
            isIndexUsable: isIndexUsable,
            documentCount: documentCount,
            metrics: nil,
            failure: nil
        )
    }
}

nonisolated enum GraphSearchIndexOperationalState: String, Codable, CaseIterable, Sendable {
    case notReady
    case reconciling
    case ready
    case unavailable
}

nonisolated struct GraphSearchIndexReadinessSnapshot: Equatable, Sendable {
    let graphID: UUID
    let state: GraphSearchIndexOperationalState
    let isIndexUsable: Bool
    let documentCount: Int?
}

nonisolated protocol GraphSearchIndexReadinessInvalidating: Sendable {
    func invalidate(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async

    func didBecomeReady(
        scope: GraphScope,
        documentCount: Int
    ) async
}

extension GraphSearchIndexReadinessInvalidating {
    func didBecomeReady(
        scope: GraphScope,
        documentCount: Int
    ) async {}
}

actor GraphSearchIndexReconciler: GraphSearchIndexReadinessInvalidating {
    static let shared = GraphSearchIndexReconciler()
    static let defaultForegroundMinimumInterval: TimeInterval = 15 * 60

    private struct Waiter {
        let reason: GraphSearchIndexReconciliationReason
        let continuation: CheckedContinuation<GraphSearchIndexReadinessResult, Never>
    }

    private struct Operation {
        let id: UUID
        let consumedInvalidationReason: GraphSearchIndexReconciliationReason?
        var task: Task<Void, Never>?
        var waiters: [UUID: Waiter]
    }

    private let worker: GraphSearchIndexReconciliationWorker
    private let indexer: GraphSearchIndexer
    private let foregroundMinimumInterval: TimeInterval
    private let now: @Sendable () -> Date

    private var configuredContainerID: ObjectIdentifier?
    private var operations: [UUID: Operation] = [:]
    private var invalidationReasons: [UUID: GraphSearchIndexReconciliationReason] = [:]
    private var lastForegroundAttempts: [UUID: Date] = [:]
    private var completedOperationCounts: [UUID: Int] = [:]
    private var lastResults: [UUID: GraphSearchIndexReadinessResult] = [:]

    init(
        sourceReader: any GraphSearchSourceReading = GraphReadRepository.shared,
        store: GraphSearchIndexStore = GraphSearchIndexStore.shared,
        indexer: GraphSearchIndexer = GraphSearchIndexer.shared,
        builder: GraphSearchDocumentBuilder = GraphSearchDocumentBuilder(),
        foregroundMinimumInterval: TimeInterval = GraphSearchIndexReconciler.defaultForegroundMinimumInterval,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.worker = GraphSearchIndexReconciliationWorker(
            sourceReader: sourceReader,
            store: store,
            indexer: indexer,
            builder: builder
        )
        self.indexer = indexer
        self.foregroundMinimumInterval = max(0, foregroundMinimumInterval)
        self.now = now
    }

    func configure(container: AnyModelContainer) async {
        guard configuredContainerID != container.identity else { return }
        await stop()
        configuredContainerID = container.identity
    }

    func stop() async {
        configuredContainerID = nil
        let activeOperations = Array(operations)
        operations.removeAll(keepingCapacity: false)
        invalidationReasons.removeAll(keepingCapacity: false)
        lastForegroundAttempts.removeAll(keepingCapacity: false)
        lastResults.removeAll(keepingCapacity: false)

        for (graphID, operation) in activeOperations {
            operation.task?.cancel()
            for waiter in operation.waiters.values {
                waiter.continuation.resume(
                    returning: .cancelled(
                        graphID: graphID,
                        reason: waiter.reason
                    )
                )
            }
        }
        for (_, operation) in activeOperations {
            await operation.task?.value
        }
    }

    func ensureReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult {
        if reason == .foreground,
           shouldThrottleForeground(scope: scope) {
            return await currentResult(
                scope: scope,
                reason: reason
            )
        }
        if reason == .foreground {
            lastForegroundAttempts[scope.graphID] = now()
        }

        let waiterID = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerWaiter(
                    id: waiterID,
                    scope: scope,
                    reason: reason,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(
                    id: waiterID,
                    graphID: scope.graphID,
                    reason: reason
                )
            }
        }
        guard Task.isCancelled == false else {
            return .cancelled(
                graphID: scope.graphID,
                reason: reason,
                isIndexUsable: result.isIndexUsable,
                documentCount: result.documentCount
            )
        }
        return result
    }

    func readiness(
        for scope: GraphScope
    ) async -> GraphSearchIndexReadinessSnapshot {
        let status = await indexer.status(for: scope)
        let knownReadiness = await knownReadiness(
            scope: scope,
            status: status
        )
        if let operation = operations[scope.graphID] {
            return GraphSearchIndexReadinessSnapshot(
                graphID: scope.graphID,
                state: .reconciling,
                isIndexUsable: operation.consumedInvalidationReason == nil
                    && knownReadiness.isUsable,
                documentCount: knownReadiness.documentCount
            )
        }
        if let invalidationReason = invalidationReasons[scope.graphID] {
            let failedButUsable = lastResults[scope.graphID].map {
                $0.outcome == .failed && $0.isIndexUsable
            } ?? false
            return GraphSearchIndexReadinessSnapshot(
                graphID: scope.graphID,
                state: invalidationReason == .indexFailure
                    ? .unavailable
                    : .notReady,
                isIndexUsable: failedButUsable,
                documentCount: status.documentCount ?? knownReadiness.documentCount
            )
        }

        switch status.state {
        case .ready:
            return GraphSearchIndexReadinessSnapshot(
                graphID: scope.graphID,
                state: .ready,
                isIndexUsable: true,
                documentCount: status.documentCount
            )
        case .building, .stale, .notInitialized:
            return GraphSearchIndexReadinessSnapshot(
                graphID: scope.graphID,
                state: .notReady,
                isIndexUsable: knownReadiness.isUsable,
                documentCount: knownReadiness.documentCount
            )
        case .failed:
            return GraphSearchIndexReadinessSnapshot(
                graphID: scope.graphID,
                state: .unavailable,
                isIndexUsable: knownReadiness.isUsable,
                documentCount: knownReadiness.documentCount
            )
        }
    }

    func invalidate(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async {
        lastResults.removeValue(forKey: scope.graphID)
        if invalidationReasons[scope.graphID] != .indexFailure
            || reason == .indexFailure {
            invalidationReasons[scope.graphID] = reason
        }
        if reason != .indexFailure {
            await indexer.markStale(scope: scope)
        }
    }

    func didBecomeReady(
        scope: GraphScope,
        documentCount: Int
    ) {
        invalidationReasons.removeValue(forKey: scope.graphID)
        if operations[scope.graphID] == nil {
            lastResults[scope.graphID] = GraphSearchIndexReadinessResult(
                graphID: scope.graphID,
                reason: .explicit,
                outcome: .ready,
                isIndexUsable: true,
                documentCount: max(0, documentCount),
                metrics: nil,
                failure: nil
            )
        }
    }

    func completedOperationCountForTesting(graphID: UUID) -> Int {
        completedOperationCounts[graphID, default: 0]
    }

    func hasActiveOperationForTesting(graphID: UUID) -> Bool {
        operations[graphID] != nil
    }

    func resetForTesting() async {
        await stop()
        completedOperationCounts.removeAll(keepingCapacity: false)
    }

    private func registerWaiter(
        id: UUID,
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason,
        continuation: CheckedContinuation<GraphSearchIndexReadinessResult, Never>
    ) {
        if Task.isCancelled {
            continuation.resume(
                returning: .cancelled(graphID: scope.graphID, reason: reason)
            )
            return
        }

        if var operation = operations[scope.graphID] {
            operation.waiters[id] = Waiter(
                reason: reason,
                continuation: continuation
            )
            operations[scope.graphID] = operation
            return
        }

        let operationID = UUID()
        let forcedReason = invalidationReasons.removeValue(forKey: scope.graphID)
        operations[scope.graphID] = Operation(
            id: operationID,
            consumedInvalidationReason: forcedReason,
            task: nil,
            waiters: [
                id: Waiter(
                    reason: reason,
                    continuation: continuation
                )
            ]
        )

        let task = Task.detached(priority: .utility) { [worker] in
            let result = await worker.perform(
                scope: scope,
                reason: forcedReason ?? reason,
                forceFullRebuild: forcedReason == .indexFailure
            )
            await self.completeOperation(
                graphID: scope.graphID,
                operationID: operationID,
                result: result
            )
        }
        operations[scope.graphID]?.task = task
    }

    private func cancelWaiter(
        id: UUID,
        graphID: UUID,
        reason: GraphSearchIndexReconciliationReason
    ) {
        guard var operation = operations[graphID],
              let waiter = operation.waiters.removeValue(forKey: id)
        else {
            return
        }
        operations[graphID] = operation
        let lastResult = lastResults[graphID]
        waiter.continuation.resume(
            returning: .cancelled(
                graphID: graphID,
                reason: reason,
                isIndexUsable: lastResult?.isIndexUsable ?? false,
                documentCount: lastResult?.documentCount
            )
        )
    }

    private func completeOperation(
        graphID: UUID,
        operationID: UUID,
        result: GraphSearchIndexReadinessResult
    ) {
        guard let operation = operations[graphID],
              operation.id == operationID
        else {
            return
        }
        operations.removeValue(forKey: graphID)
        completedOperationCounts[graphID, default: 0] += 1
        lastResults[graphID] = result
        if let consumedReason = operation.consumedInvalidationReason,
           result.outcome == .failed
                || result.outcome == .cancelled
                || result.outcome == .unavailable,
           invalidationReasons[graphID] == nil {
            invalidationReasons[graphID] = consumedReason
        }
        for waiter in operation.waiters.values {
            waiter.continuation.resume(
                returning: result.replacingReason(with: waiter.reason)
            )
        }
    }

    private func shouldThrottleForeground(scope: GraphScope) -> Bool {
        guard invalidationReasons[scope.graphID] == nil else {
            return false
        }
        guard let lastAttempt = lastForegroundAttempts[scope.graphID] else {
            return false
        }
        return now().timeIntervalSince(lastAttempt) < foregroundMinimumInterval
    }

    private func currentResult(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult {
        let status = await indexer.status(for: scope)
        if status.state == .ready {
            return GraphSearchIndexReadinessResult(
                graphID: scope.graphID,
                reason: reason,
                outcome: .ready,
                isIndexUsable: true,
                documentCount: status.documentCount,
                metrics: nil,
                failure: nil
            )
        }
        if let lastResult = lastResults[scope.graphID] {
            return GraphSearchIndexReadinessResult(
                graphID: scope.graphID,
                reason: reason,
                outcome: status.state == .failed ? .failed : lastResult.outcome,
                isIndexUsable: lastResult.isIndexUsable,
                documentCount: status.documentCount ?? lastResult.documentCount,
                metrics: lastResult.metrics,
                failure: status.failure ?? lastResult.failure
            )
        }

        let knownReadiness = await knownReadiness(
            scope: scope,
            status: status
        )
        return GraphSearchIndexReadinessResult(
            graphID: scope.graphID,
            reason: reason,
            outcome: status.state == .failed ? .failed : .unavailable,
            isIndexUsable: knownReadiness.isUsable,
            documentCount: knownReadiness.documentCount,
            metrics: nil,
            failure: status.failure
        )
    }

    private func knownReadiness(
        scope: GraphScope,
        status: GraphSearchIndexStatus
    ) async -> GraphSearchStoredIndexReadiness {
        if let lastResult = lastResults[scope.graphID],
           lastResult.isIndexUsable {
            return GraphSearchStoredIndexReadiness(
                isUsable: true,
                documentCount: status.documentCount ?? lastResult.documentCount
            )
        }
        if status.hasUsableDocuments {
            return GraphSearchStoredIndexReadiness(
                isUsable: true,
                documentCount: status.documentCount
            )
        }
        return await worker.storedReadiness(scope: scope)
    }

}

private nonisolated struct GraphSearchStoredIndexReadiness: Sendable {
    let isUsable: Bool
    let documentCount: Int?
}

private nonisolated struct GraphSearchIndexReconciliationWorker: Sendable {
    let sourceReader: any GraphSearchSourceReading
    let store: GraphSearchIndexStore
    let indexer: GraphSearchIndexer
    let builder: GraphSearchDocumentBuilder

    func storedReadiness(
        scope: GraphScope
    ) async -> GraphSearchStoredIndexReadiness {
        do {
            if await store.isOpen == false {
                _ = try await store.open()
            }
            guard let manifest = try await store.sourceManifest(in: scope.graphID),
                  manifest.isCompatible
            else {
                return GraphSearchStoredIndexReadiness(
                    isUsable: false,
                    documentCount: nil
                )
            }
            return GraphSearchStoredIndexReadiness(
                isUsable: true,
                documentCount: manifest.documentCount
            )
        } catch {
            return GraphSearchStoredIndexReadiness(
                isUsable: false,
                documentCount: nil
            )
        }
    }

    func perform(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason,
        forceFullRebuild: Bool
    ) async -> GraphSearchIndexReadinessResult {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var previouslyUsable = false
        var previousDocumentCount: Int?

        do {
            try Task.checkCancellation()
            if await store.isOpen == false {
                _ = try await store.open()
            }
            try Task.checkCancellation()

            let storedManifest: GraphSearchSourceManifest?
            do {
                storedManifest = try await store.sourceManifest(in: scope.graphID)
                if let storedManifest {
                    previouslyUsable = storedManifest.isCompatible
                    previousDocumentCount = storedManifest.documentCount
                }
            } catch {
                return await rebuildResult(
                    scope: scope,
                    reason: reason,
                    checkedSourceCount: 0,
                    previousUsable: false,
                    previousDocumentCount: nil,
                    startedAt: startedAt
                )
            }

            guard forceFullRebuild == false,
                  let storedManifest,
                  storedManifest.isCompatible
            else {
                return await rebuildResult(
                    scope: scope,
                    reason: reason,
                    checkedSourceCount: 0,
                    previousUsable: previouslyUsable,
                    previousDocumentCount: previousDocumentCount,
                    startedAt: startedAt
                )
            }

            let snapshot = try await sourceReader.sourceSnapshot(in: scope)
            guard snapshot.scope == scope,
                  snapshot.graph.scope == scope,
                  snapshot.graph.id == scope.graphID
            else {
                throw GraphSearchIndexerError.mismatchedSnapshotScope(
                    expected: scope.graphID,
                    actual: snapshot.scope.graphID
                )
            }
            try Task.checkCancellation()
            let currentBuild = try builder.buildSnapshot(for: snapshot)
            let currentManifest = currentBuild.sourceManifest
            let checkedSourceCount = currentManifest.sourceCount

            if storedManifest == currentManifest {
                await indexer.acceptReconciledIndex(
                    scope: scope,
                    documentCount: currentManifest.documentCount
                )
                let result = makeResult(
                    scope: scope,
                    reason: reason,
                    outcome: .ready,
                    usable: true,
                    documentCount: currentManifest.documentCount,
                    checkedSourceCount: checkedSourceCount,
                    added: 0,
                    changed: 0,
                    deleted: 0,
                    fullRebuild: false,
                    startedAt: startedAt,
                    failure: nil
                )
                log(result)
                return result
            }

            let storedEntries = storedManifest.entryMap
            let currentEntries = currentManifest.entryMap
            let addedReferences = currentEntries.keys.filter {
                storedEntries[$0] == nil
            }.sorted(by: GraphSearchIndexStore.sourceReferenceSort)
            let changedReferences = currentEntries.keys.filter { reference in
                guard let storedEntry = storedEntries[reference],
                      let currentEntry = currentEntries[reference]
                else {
                    return false
                }
                return storedEntry != currentEntry
            }.sorted(by: GraphSearchIndexStore.sourceReferenceSort)
            let deletedReferences = storedEntries.keys.filter {
                currentEntries[$0] == nil
            }.sorted(by: GraphSearchIndexStore.sourceReferenceSort)

            let changedTotal = addedReferences.count
                + changedReferences.count
                + deletedReferences.count
            if shouldUseFullRebuild(
                storedManifest: storedManifest,
                currentManifest: currentManifest,
                changedSourceCount: changedTotal
            ) {
                return await rebuildResult(
                    scope: scope,
                    reason: reason,
                    checkedSourceCount: checkedSourceCount,
                    addedSourceCount: addedReferences.count,
                    changedSourceCount: changedReferences.count,
                    deletedSourceCount: deletedReferences.count,
                    previousUsable: previouslyUsable,
                    previousDocumentCount: previousDocumentCount,
                    startedAt: startedAt
                )
            }

            let buildMap = Dictionary(
                uniqueKeysWithValues: currentBuild.sourceBuilds.map {
                    ($0.reference, $0)
                }
            )
            let replacementReferences = addedReferences + changedReferences
            let replacements = try replacementReferences.map { reference in
                guard let build = buildMap[reference] else {
                    throw GraphSearchIndexStoreError.invalidSourceManifest(
                        reason: "A changed source is missing its value-only build snapshot."
                    )
                }
                return GraphSearchIndexSourceReplacement(
                    sourceReference: reference,
                    documents: build.documents,
                    manifestEntry: build.manifestEntry
                )
            }

            try Task.checkCancellation()
            try await store.reconcile(
                graphID: scope.graphID,
                replacements: replacements,
                deletions: deletedReferences,
                expectedSourceManifest: storedManifest,
                sourceManifest: currentManifest
            )
            await indexer.acceptReconciledIndex(
                scope: scope,
                documentCount: currentManifest.documentCount
            )

            let result = makeResult(
                scope: scope,
                reason: reason,
                outcome: .reconciled,
                usable: true,
                documentCount: currentManifest.documentCount,
                checkedSourceCount: checkedSourceCount,
                added: addedReferences.count,
                changed: changedReferences.count,
                deleted: deletedReferences.count,
                fullRebuild: false,
                startedAt: startedAt,
                failure: nil
            )
            log(result)
            return result
        } catch is CancellationError {
            let result = GraphSearchIndexReadinessResult.cancelled(
                graphID: scope.graphID,
                reason: reason,
                isIndexUsable: previouslyUsable,
                documentCount: previousDocumentCount
            )
            BMLog.search.notice(
                "Graph search reconciliation cancelled reason=\(reason.rawValue, privacy: .public) usable=\(previouslyUsable, privacy: .public)"
            )
            return result
        } catch {
            let result = makeResult(
                scope: scope,
                reason: reason,
                outcome: .failed,
                usable: previouslyUsable,
                documentCount: previousDocumentCount,
                checkedSourceCount: 0,
                added: 0,
                changed: 0,
                deleted: 0,
                fullRebuild: false,
                startedAt: startedAt,
                failure: GraphSearchIndexFailure(error: error)
            )
            log(result)
            return result
        }
    }

    private func rebuildResult(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason,
        checkedSourceCount: Int,
        addedSourceCount: Int = 0,
        changedSourceCount: Int = 0,
        deletedSourceCount: Int = 0,
        previousUsable: Bool,
        previousDocumentCount: Int?,
        startedAt: UInt64
    ) async -> GraphSearchIndexReadinessResult {
        do {
            try Task.checkCancellation()
            try await indexer.rebuild(scope: scope)
            let status = await indexer.status(for: scope)
            let result = makeResult(
                scope: scope,
                reason: reason,
                outcome: .rebuilt,
                usable: status.state == .ready,
                documentCount: status.documentCount,
                checkedSourceCount: checkedSourceCount,
                added: addedSourceCount,
                changed: changedSourceCount,
                deleted: deletedSourceCount,
                fullRebuild: true,
                startedAt: startedAt,
                failure: status.failure
            )
            log(result)
            return result
        } catch {
            let result = makeResult(
                scope: scope,
                reason: reason,
                outcome: error is CancellationError ? .cancelled : .failed,
                usable: previousUsable,
                documentCount: previousDocumentCount,
                checkedSourceCount: checkedSourceCount,
                added: addedSourceCount,
                changed: changedSourceCount,
                deleted: deletedSourceCount,
                fullRebuild: true,
                startedAt: startedAt,
                failure: error is CancellationError
                    ? nil
                    : GraphSearchIndexFailure(error: error)
            )
            log(result)
            return result
        }
    }

    private func shouldUseFullRebuild(
        storedManifest: GraphSearchSourceManifest,
        currentManifest: GraphSearchSourceManifest,
        changedSourceCount: Int
    ) -> Bool {
        let largestSourceCount = max(
            storedManifest.sourceCount,
            currentManifest.sourceCount
        )
        let broadChangeThreshold = max(128, (largestSourceCount + 1) / 2)
        guard changedSourceCount >= broadChangeThreshold else {
            return false
        }

        // Half of a large graph or at least 128 changed sources is intentionally
        // treated as broad structural drift. The atomic full rebuild is cheaper and
        // easier to validate than publishing hundreds of individual replacements.
        return true
    }

    private func makeResult(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason,
        outcome: GraphSearchIndexReadinessOutcome,
        usable: Bool,
        documentCount: Int?,
        checkedSourceCount: Int,
        added: Int,
        changed: Int,
        deleted: Int,
        fullRebuild: Bool,
        startedAt: UInt64,
        failure: GraphSearchIndexFailure?
    ) -> GraphSearchIndexReadinessResult {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt
        return GraphSearchIndexReadinessResult(
            graphID: scope.graphID,
            reason: reason,
            outcome: outcome,
            isIndexUsable: usable,
            documentCount: documentCount,
            metrics: GraphSearchIndexReconciliationMetrics(
                checkedSourceCount: max(0, checkedSourceCount),
                addedSourceCount: max(0, added),
                changedSourceCount: max(0, changed),
                deletedSourceCount: max(0, deleted),
                fullRebuild: fullRebuild,
                durationMilliseconds: Double(elapsed) / 1_000_000
            ),
            failure: failure
        )
    }

    private func log(_ result: GraphSearchIndexReadinessResult) {
        let metrics = result.metrics
        BMLog.search.info(
            "Graph search reconciliation completed graph=\(result.graphID.uuidString, privacy: .private(mask: .hash)) reason=\(result.reason.rawValue, privacy: .public) outcome=\(result.outcome.rawValue, privacy: .public) usable=\(result.isIndexUsable, privacy: .public) checked=\(metrics?.checkedSourceCount ?? 0, privacy: .public) added=\(metrics?.addedSourceCount ?? 0, privacy: .public) changed=\(metrics?.changedSourceCount ?? 0, privacy: .public) deleted=\(metrics?.deletedSourceCount ?? 0, privacy: .public) fullRebuild=\(metrics?.fullRebuild ?? false, privacy: .public) durationMS=\(metrics?.durationMilliseconds ?? 0, format: .fixed(precision: 2))"
        )
    }
}

private extension GraphSearchIndexStatus {
    nonisolated var hasUsableDocuments: Bool {
        guard documentCount != nil else { return false }
        switch state {
        case .ready, .building, .stale:
            return true
        case .notInitialized, .failed:
            return false
        }
    }
}
