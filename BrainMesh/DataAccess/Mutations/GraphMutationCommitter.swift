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

/// Commits pending SwiftData changes and publishes their already prepared technical mutation batch.
///
/// The committer is intentionally MainActor-isolated because `ModelContext` and SwiftData models
/// must not cross actor boundaries. Publication starts only after a successful save. A publication
/// diagnostic never changes the successful persistence result.
@MainActor
struct GraphMutationCommitter {
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
    @discardableResult
    func commit(
        _ batch: GraphMutationBatch,
        in modelContext: ModelContext
    ) async throws -> GraphMutationPublishReceipt {
        do {
            try Task.checkCancellation()
        } catch {
            modelContext.rollback()
            logCancelledBeforeSave()
            throw error
        }

        do {
            try saveOperation(modelContext)
        } catch {
            modelContext.rollback()
            logSaveFailure()
            throw error
        }

        let receipt = await publisher.publishCommitted(batch)
        logPublishProblemIfNeeded(receipt)
        return receipt
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

    private func logPublishProblemIfNeeded(
        _ receipt: GraphMutationPublishReceipt
    ) {
        guard receipt.hasPublicationProblem else {
            return
        }

        #if canImport(os)
        switch receipt.disposition {
        case .published:
            BMLog.mutationEvents.notice(
                "Committed batch publication had delivery issues subscribers=\(receipt.subscriberCount, privacy: .public) dropped=\(receipt.droppedSubscriberCount, privacy: .public) terminated=\(receipt.terminatedSubscriberCount, privacy: .public)"
            )
        case .busFinished:
            BMLog.mutationEvents.error(
                "Committed batch was not published because the event bus is finished"
            )
        case .sequenceExhausted:
            BMLog.mutationEvents.error(
                "Committed batch was not published because the delivery sequence is exhausted"
            )
        }
        #endif
    }
}
