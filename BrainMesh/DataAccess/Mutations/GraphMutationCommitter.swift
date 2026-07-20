//
//  GraphMutationCommitter.swift
//  BrainMesh
//
//  Single save-then-publish boundary for committed graph mutations.
//

import Foundation
import SwiftData

#if canImport(os)
import os
#endif

nonisolated enum GraphMutationCommitterError: LocalizedError, Equatable, Sendable {
    case emptyBatchGroup
    case duplicateGraphScope

    var errorDescription: String? {
        switch self {
        case .emptyBatchGroup:
            return "Eine Mutation-Batch-Gruppe darf nicht leer sein."
        case .duplicateGraphScope:
            return "Eine Mutation-Batch-Gruppe darf pro Graph nur einen Batch enthalten."
        }
    }
}

/// Commits pending SwiftData changes and publishes their already prepared technical mutation batch.
///
/// Construction is intentionally nonisolated so the committer can be used as a default argument
/// under the project's MainActor-by-default setting. Normal UI writes use the explicitly
/// MainActor-isolated `ModelContext` overloads. Actor-owned import contexts use the caller-isolated
/// closure overload so their non-Sendable SwiftData state never crosses an actor boundary.
/// Publication starts only after a successful save. A publication diagnostic never changes the
/// successful persistence result.
nonisolated struct GraphMutationCommitter {
    typealias SaveOperation = @MainActor (ModelContext) throws -> Void

    private let publisher: any GraphMutationPublishing
    private let saveOperation: SaveOperation

    init(
        publisher: any GraphMutationPublishing = GraphMutationEventBus.shared,
        saveOperation: @escaping SaveOperation = { context in
            try context.save()
        }
    ) {
        self.publisher = publisher
        self.saveOperation = saveOperation
    }

    /// Saves pending changes and then publishes exactly one graph-scoped batch.
    ///
    /// Cancellation is observed immediately before the irreversible save phase. There is no
    /// cancellation check after a successful save so the corresponding post-commit event cannot
    /// be lost merely because the initiating task was cancelled at that point.
    @MainActor
    @discardableResult
    func commit(
        _ batch: GraphMutationBatch,
        in modelContext: ModelContext
    ) async throws -> GraphMutationPublishReceipt {
        let receipts = try await commit([batch], in: modelContext)
        guard let receipt = receipts.first else {
            throw GraphMutationCommitterError.emptyBatchGroup
        }
        return receipt
    }

    /// Saves one atomic maintenance transaction and publishes one batch per affected graph.
    ///
    /// This overload is reserved for the rare case where one existing atomic SwiftData save must
    /// touch multiple graph scopes. Batches are sorted by technical graph ID and each graph may
    /// occur only once. No cancellation check occurs after the successful save.
    @MainActor
    @discardableResult
    func commit(
        _ batches: [GraphMutationBatch],
        in modelContext: ModelContext
    ) async throws -> [GraphMutationPublishReceipt] {
        try await commitPrepared(
            batches,
            save: {
                try saveOperation(modelContext)
            },
            rollback: {
                modelContext.rollback()
            }
        )
    }

    /// Commits an actor-owned context without moving that context across executors.
    ///
    /// The nonescaping closures execute on the caller's current isolation. This is used by the
    /// GraphTransfer importer, whose `ModelContext` belongs to its import executor rather than the
    /// MainActor. It is still the same save-then-publish implementation and the same injected
    /// publisher as every other mutation path.
    @discardableResult
    nonisolated(nonsending) func commitCallerIsolated(
        _ batch: GraphMutationBatch,
        save: () throws -> Void,
        rollback: () -> Void
    ) async throws -> GraphMutationPublishReceipt {
        let receipts = try await commitPrepared(
            [batch],
            save: save,
            rollback: rollback
        )
        guard let receipt = receipts.first else {
            throw GraphMutationCommitterError.emptyBatchGroup
        }
        return receipt
    }

    @discardableResult
    private nonisolated(nonsending) func commitPrepared(
        _ batches: [GraphMutationBatch],
        save: () throws -> Void,
        rollback: () -> Void
    ) async throws -> [GraphMutationPublishReceipt] {
        let orderedBatches: [GraphMutationBatch]
        do {
            orderedBatches = try orderedUniqueBatches(batches)
        } catch {
            rollback()
            throw error
        }

        do {
            try Task.checkCancellation()
        } catch {
            rollback()
            logCancelledBeforeSave()
            throw error
        }

        do {
            try save()
        } catch {
            rollback()
            logSaveFailure()
            throw error
        }

        var receipts: [GraphMutationPublishReceipt] = []
        receipts.reserveCapacity(orderedBatches.count)

        for batch in orderedBatches {
            let receipt = await publisher.publishCommitted(batch)
            GraphMutationPublicationDiagnostics.logIfNeeded(receipt)
            receipts.append(receipt)
        }

        return receipts
    }

    private func orderedUniqueBatches(
        _ batches: [GraphMutationBatch]
    ) throws -> [GraphMutationBatch] {
        guard batches.isEmpty == false else {
            throw GraphMutationCommitterError.emptyBatchGroup
        }

        var seenGraphIDs = Set<UUID>()
        for batch in batches {
            guard seenGraphIDs.insert(batch.graphID).inserted else {
                throw GraphMutationCommitterError.duplicateGraphScope
            }
        }

        return batches.sorted { lhs, rhs in
            lhs.graphID.uuidString < rhs.graphID.uuidString
        }
    }

    private func logCancelledBeforeSave() {
        #if canImport(os)
        BMLog.mutationEvents.debug(
            "Mutation commit cancelled before SwiftData save"
        )
        #endif
    }

    private func logSaveFailure() {
        #if canImport(os)
        BMLog.mutationEvents.error(
            "Mutation SwiftData save failed; no batch was published"
        )
        #endif
    }
}
