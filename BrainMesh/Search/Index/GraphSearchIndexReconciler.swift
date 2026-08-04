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

    private enum WaiterOwnership: Sendable {
        case request
        case maintenance
    }

    private struct Waiter {
        let reason: GraphSearchIndexReconciliationReason
        let ownership: WaiterOwnership
        let continuation: CheckedContinuation<GraphSearchIndexReadinessResult, Never>
    }

    private struct Operation {
        let id: UUID
        let consumedInvalidationReason: GraphSearchIndexReconciliationReason?
        var task: Task<Void, Never>?
        var waiters: [UUID: Waiter]
    }

    private struct DrainingOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    private let worker: GraphSearchIndexReconciliationWorker
    private let indexer: GraphSearchIndexer

    private var configuredContainerID: ObjectIdentifier?
    private var operations: [UUID: Operation] = [:]
    private var drainingOperations: [UUID: DrainingOperation] = [:]
    private var invalidationReasons: [UUID: GraphSearchIndexReconciliationReason] = [:]
    private var completedOperationCounts: [UUID: Int] = [:]
    private var lastResults: [UUID: GraphSearchIndexReadinessResult] = [:]

    init(
        sourceReader: any GraphSearchSourceReading = GraphReadRepository.shared,
        store: GraphSearchIndexStore = GraphSearchIndexStore.shared,
        indexer: GraphSearchIndexer = GraphSearchIndexer.shared,
        builder: GraphSearchDocumentBuilder = GraphSearchDocumentBuilder()
    ) {
        self.worker = GraphSearchIndexReconciliationWorker(
            sourceReader: sourceReader,
            store: store,
            indexer: indexer,
            builder: builder
        )
        self.indexer = indexer
    }

    func configure(container: AnyModelContainer) async {
        guard configuredContainerID != container.identity else { return }
        await stop()
        configuredContainerID = container.identity
    }

    func stop() async {
        configuredContainerID = nil
        let activeOperations = Array(operations)
        let activeDrains = drainingOperations.values.map(\.task)
        operations.removeAll(keepingCapacity: false)
        drainingOperations.removeAll(keepingCapacity: false)
        invalidationReasons.removeAll(keepingCapacity: false)
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
        for task in activeDrains {
            task.cancel()
        }
        for (_, operation) in activeOperations {
            await operation.task?.value
        }
        for task in activeDrains {
            await task.value
        }
    }

    func ensureReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult {
        await waitUntilReady(
            scope: scope,
            reason: reason,
            ownership: .request,
            forceReconciliation: Self.requiresForcedReconciliation(reason)
        )
    }

    /// Explicit owner for work that is allowed to outlive ordinary request
    /// waiters. Cancellation of this owner still cancels the worker when no
    /// other owner remains.
    func performMaintenance(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason = .explicit
    ) async -> GraphSearchIndexReadinessResult {
        await waitUntilReady(
            scope: scope,
            reason: reason,
            ownership: .maintenance,
            forceReconciliation: true
        )
    }

    private func waitUntilReady(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason,
        ownership: WaiterOwnership,
        forceReconciliation: Bool
    ) async -> GraphSearchIndexReadinessResult {
        if Task.isCancelled {
            return .cancelled(graphID: scope.graphID, reason: reason)
        }

        if forceReconciliation == false,
           invalidationReasons[scope.graphID] == nil,
           let fastResult = await worker.fastPath(scope: scope, reason: reason) {
            lastResults[scope.graphID] = fastResult
            return fastResult
        }

        let waiterID = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerWaiter(
                    id: waiterID,
                    scope: scope,
                    reason: reason,
                    ownership: ownership,
                    forceReconciliation: forceReconciliation,
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

    private nonisolated static func requiresForcedReconciliation(
        _ reason: GraphSearchIndexReconciliationReason
    ) -> Bool {
        switch reason {
        case .explicit, .importOrReplace, .dedupe, .indexFailure:
            return true
        case .firstSearch, .chatSession, .foreground:
            return false
        }
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

        if let persistedReady = await worker.fastPath(
            scope: scope,
            reason: .chatSession
        ) {
            lastResults[scope.graphID] = persistedReady
            return GraphSearchIndexReadinessSnapshot(
                graphID: scope.graphID,
                state: .ready,
                isIndexUsable: true,
                documentCount: persistedReady.documentCount
            )
        }

        switch status.state {
        case .ready:
            return GraphSearchIndexReadinessSnapshot(
                graphID: scope.graphID,
                state: .notReady,
                isIndexUsable: knownReadiness.isUsable,
                documentCount: status.documentCount
                    ?? knownReadiness.documentCount
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
        do {
            try await worker.persistInvalidation(scope: scope, reason: reason)
        } catch {
            BMLog.searchReadiness.error(
                "index_readiness invalidation=persist_failed graph=\(scope.graphID.uuidString, privacy: .private(mask: .hash)) reason=\(reason.rawValue, privacy: .public)"
            )
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

    func waiterCountsForTesting(
        graphID: UUID
    ) -> (request: Int, maintenance: Int) {
        guard let operation = operations[graphID] else { return (0, 0) }
        var requestCount = 0
        var maintenanceCount = 0
        for waiter in operation.waiters.values {
            switch waiter.ownership {
            case .request:
                requestCount += 1
            case .maintenance:
                maintenanceCount += 1
            }
        }
        return (requestCount, maintenanceCount)
    }

    func resetForTesting() async {
        await stop()
        completedOperationCounts.removeAll(keepingCapacity: false)
    }

    private func registerWaiter(
        id: UUID,
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason,
        ownership: WaiterOwnership,
        forceReconciliation: Bool,
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
                ownership: ownership,
                continuation: continuation
            )
            operations[scope.graphID] = operation
            return
        }

        let operationID = UUID()
        let predecessor = drainingOperations[scope.graphID]?.task
        let forcedReason = invalidationReasons.removeValue(forKey: scope.graphID)
        operations[scope.graphID] = Operation(
            id: operationID,
            consumedInvalidationReason: forcedReason,
            task: nil,
            waiters: [
                id: Waiter(
                    reason: reason,
                    ownership: ownership,
                    continuation: continuation
                )
            ]
        )

        let task = Task(priority: .utility) { [worker] in
            if let predecessor {
                await predecessor.value
            }
            let result: GraphSearchIndexReadinessResult
            if Task.isCancelled {
                result = .cancelled(
                    graphID: scope.graphID,
                    reason: forcedReason ?? reason
                )
            } else {
                result = await worker.perform(
                    scope: scope,
                    reason: forcedReason ?? reason,
                    forceFullRebuild: (forcedReason ?? reason) == .indexFailure,
                    forceReconciliation: forceReconciliation || forcedReason != nil
                )
            }
            self.completeOperation(
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
        let lastResult = lastResults[graphID]
        waiter.continuation.resume(
            returning: .cancelled(
                graphID: graphID,
                reason: reason,
                isIndexUsable: lastResult?.isIndexUsable ?? false,
                documentCount: lastResult?.documentCount
            )
        )
        guard operation.waiters.isEmpty else {
            operations[graphID] = operation
            BMLog.searchCancellation.debug(
                "index_reconciliation waiter=cancelled worker=retained graph=\(graphID.uuidString, privacy: .private(mask: .hash)) remaining=\(operation.waiters.count, privacy: .public)"
            )
            return
        }

        operations.removeValue(forKey: graphID)
        if let consumedReason = operation.consumedInvalidationReason,
           invalidationReasons[graphID] == nil {
            invalidationReasons[graphID] = consumedReason
        }
        if let task = operation.task {
            drainingOperations[graphID] = DrainingOperation(
                id: operation.id,
                task: task
            )
            task.cancel()
        }
        BMLog.searchCancellation.notice(
            "index_reconciliation waiter=last_cancelled worker=cancelled graph=\(graphID.uuidString, privacy: .private(mask: .hash))"
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
            if drainingOperations[graphID]?.id == operationID {
                drainingOperations.removeValue(forKey: graphID)
            }
            return
        }
        operations.removeValue(forKey: graphID)
        completedOperationCounts[graphID, default: 0] += 1
        lastResults[graphID] = result
        if let consumedReason = operation.consumedInvalidationReason,
           (result.outcome == .failed
                || result.outcome == .cancelled
                || result.outcome == .unavailable),
           invalidationReasons[graphID] == nil {
            invalidationReasons[graphID] = consumedReason
        }
        for waiter in operation.waiters.values {
            waiter.continuation.resume(
                returning: result.replacingReason(with: waiter.reason)
            )
        }
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

    func fastPath(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async -> GraphSearchIndexReadinessResult? {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            try Task.checkCancellation()
            if await store.isOpen == false {
                _ = try await store.open()
            }
            let storedSourceRevision = try await sourceReader.searchSourceRevision(
                in: scope
            )
            guard let sourceRevision = storedSourceRevision else {
                return nil
            }
            try Task.checkCancellation()
            let storedToken = try await store.readinessToken(
                graphID: scope.graphID,
                sourceRevision: sourceRevision
            )
            guard let token = storedToken, token.isReady else {
                BMLog.searchReadiness.debug(
                    "index_readiness path=slow graph=\(scope.graphID.uuidString, privacy: .private(mask: .hash)) reason=token_mismatch"
                )
                return nil
            }
            await indexer.acceptReconciledIndex(
                scope: scope,
                documentCount: token.documentCount
            )
            let elapsed = DispatchTime.now().uptimeNanoseconds &- startedAt
            BMLog.searchReadiness.info(
                "index_readiness path=fast graph=\(scope.graphID.uuidString, privacy: .private(mask: .hash)) documents=\(token.documentCount, privacy: .public) duration_ms=\(Double(elapsed) / 1_000_000, format: .fixed(precision: 2))"
            )
            return GraphSearchIndexReadinessResult(
                graphID: scope.graphID,
                reason: reason,
                outcome: .ready,
                isIndexUsable: true,
                documentCount: token.documentCount,
                metrics: GraphSearchIndexReconciliationMetrics(
                    checkedSourceCount: 0,
                    addedSourceCount: 0,
                    changedSourceCount: 0,
                    deletedSourceCount: 0,
                    fullRebuild: false,
                    durationMilliseconds: Double(elapsed) / 1_000_000
                ),
                failure: nil
            )
        } catch is CancellationError {
            return nil
        } catch {
            BMLog.searchReadiness.error(
                "index_readiness path=slow graph=\(scope.graphID.uuidString, privacy: .private(mask: .hash)) reason=metadata_error"
            )
            return nil
        }
    }

    func persistInvalidation(
        scope: GraphScope,
        reason: GraphSearchIndexReconciliationReason
    ) async throws {
        if await store.isOpen == false {
            _ = try await store.open()
        }
        try await store.invalidateLifecycle(
            graphID: scope.graphID,
            reason: reason
        )
    }

    func storedReadiness(
        scope: GraphScope
    ) async -> GraphSearchStoredIndexReadiness {
        do {
            if await store.isOpen == false {
                _ = try await store.open()
            }
            let storedLifecycle = try await store.storedLifecycle(
                graphID: scope.graphID
            )
            guard let lifecycle = storedLifecycle,
                  lifecycle.hasUsableActiveGeneration
            else {
                return GraphSearchStoredIndexReadiness(
                    isUsable: false,
                    documentCount: nil
                )
            }
            return GraphSearchStoredIndexReadiness(
                isUsable: true,
                documentCount: lifecycle.documentCount
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
        forceFullRebuild: Bool,
        forceReconciliation: Bool
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

            if forceReconciliation == false,
               let fastResult = await fastPath(scope: scope, reason: reason) {
                return fastResult
            }
            try Task.checkCancellation()

            let sourceRevision = try await sourceReader.searchSourceRevision(
                in: scope
            )
            let storedLifecycle: GraphSearchStoredIndexLifecycle?
            do {
                storedLifecycle = try await store.storedLifecycle(
                    graphID: scope.graphID
                )
            } catch {
                // Unknown or undecodable lifecycle metadata must never strand
                // an otherwise recoverable graph. Preserve active rows, discard
                // only lifecycle/staging metadata, then rebuild transactionally.
                try await store.resetLifecycleMetadata(graphID: scope.graphID)
                storedLifecycle = nil
                BMLog.searchReadiness.notice(
                    "index_readiness path=slow graph=\(scope.graphID.uuidString, privacy: .private(mask: .hash)) reason=invalid_lifecycle_metadata"
                )
            }
            if let storedLifecycle, storedLifecycle.hasUsableActiveGeneration {
                previouslyUsable = true
                previousDocumentCount = storedLifecycle.documentCount
            }
            let persistedForceFullRebuild = storedLifecycle?.invalidationReason
                == .indexFailure
            let lifecycleGenerationIsInconsistent = storedLifecycle.map {
                $0.lifecycleState == .rebuilding
                    || $0.stagingGeneration != nil
                    || ($0.lifecycleState == .ready
                        && $0.invalidationReason != nil)
                    || ($0.lifecycleState == .invalidated
                        && $0.invalidationReason == nil)
            } ?? false
            let lifecycleRequiresRebuild = storedLifecycle == nil
                || storedLifecycle?.activeGeneration == nil
                || lifecycleGenerationIsInconsistent
                || storedLifecycle?.indexFormatVersion
                    != GraphSearchIndexSchema.currentVersion
                || storedLifecycle?.sourceManifestFormatVersion
                    != GraphSearchSourceManifestSchema.currentVersion

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
                    sourceRevision: sourceRevision,
                    startedAt: startedAt
                )
            }

            guard forceFullRebuild == false,
                  persistedForceFullRebuild == false,
                  lifecycleRequiresRebuild == false,
                  let storedManifest,
                  storedManifest.isCompatible
            else {
                return await rebuildResult(
                    scope: scope,
                    reason: reason,
                    checkedSourceCount: 0,
                    previousUsable: previouslyUsable,
                    previousDocumentCount: previousDocumentCount,
                    sourceRevision: sourceRevision,
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

            let revisionAfterBuild = try await sourceReader.searchSourceRevision(
                in: scope
            )
            guard revisionAfterBuild == sourceRevision else {
                throw GraphSearchIndexerError.sourceRevisionChangedDuringRebuild(
                    graphID: scope.graphID
                )
            }

            if storedManifest == currentManifest {
                if let sourceRevision {
                    try await store.markLifecycleReady(
                        graphID: scope.graphID,
                        sourceRevision: sourceRevision,
                        documentCount: currentManifest.documentCount
                    )
                }
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
                    sourceRevision: sourceRevision,
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
            let revisionBeforePublish = try await sourceReader.searchSourceRevision(
                in: scope
            )
            guard revisionBeforePublish == sourceRevision else {
                throw GraphSearchIndexerError.sourceRevisionChangedDuringRebuild(
                    graphID: scope.graphID
                )
            }
            if let sourceRevision {
                try await store.markLifecycleReady(
                    graphID: scope.graphID,
                    sourceRevision: sourceRevision,
                    documentCount: currentManifest.documentCount
                )
            }
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
            BMLog.searchCancellation.notice(
                "index_reconciliation outcome=cancelled reason=\(reason.rawValue, privacy: .public) usable=\(previouslyUsable, privacy: .public)"
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
        sourceRevision: UUID?,
        startedAt: UInt64
    ) async -> GraphSearchIndexReadinessResult {
        do {
            try Task.checkCancellation()
            if let sourceRevision {
                try await indexer.rebuild(
                    scope: scope,
                    sourceRevision: sourceRevision
                )
            } else {
                try await indexer.rebuild(scope: scope)
            }
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
        BMLog.searchReconciliation.info(
            "index_reconciliation graph=\(result.graphID.uuidString, privacy: .private(mask: .hash)) reason=\(result.reason.rawValue, privacy: .public) outcome=\(result.outcome.rawValue, privacy: .public) usable=\(result.isIndexUsable, privacy: .public) checked=\(metrics?.checkedSourceCount ?? 0, privacy: .public) added=\(metrics?.addedSourceCount ?? 0, privacy: .public) changed=\(metrics?.changedSourceCount ?? 0, privacy: .public) deleted=\(metrics?.deletedSourceCount ?? 0, privacy: .public) full_rebuild=\(metrics?.fullRebuild ?? false, privacy: .public) duration_ms=\(metrics?.durationMilliseconds ?? 0, format: .fixed(precision: 2))"
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
