//
//  GraphTransferImportCoordinator+Progress.swift
//  BrainMesh
//
//  Import checkpoint, batch-save and progress helpers.
//

import Foundation
import SwiftData

nonisolated extension GraphTransferImportCoordinator {

    func performCheckpoint(index: Int, cancellationStride: Int, yieldStride: Int) async throws {
        if index % cancellationStride == 0 {
            try Task.checkCancellation()
        }
        if index % yieldStride == 0 {
            await Task.yield()
        }
    }

    func recordInsertion() throws {
        insertedSinceLastSave += 1
        try maybeSave()
    }

    func maybeSave() throws {
        if insertedSinceLastSave >= GraphTransferService.ImportTuning.saveBatchSize {
            try saveContext()
            insertedSinceLastSave = 0
        }
    }

    func saveContext() throws {
        do {
            try context.save()
        } catch {
            throw GraphTransferError.saveFailed(underlying: String(describing: error))
        }
    }

    func reportPhaseStepIfNeeded(
        phase: GraphTransferProgress.Phase,
        noun: String,
        index: Int,
        total: Int,
        stride: Int
    ) {
        guard shouldReportProgress(index: index, total: total, stride: stride) else {
            return
        }
        progress?(GraphTransferImportProgressFactory.phaseStep(
            phase,
            completed: index + 1,
            total: total,
            noun: noun
        ))
    }

    func shouldReportProgress(index: Int, total: Int, stride: Int) -> Bool {
        index % stride == 0 || index + 1 == total
    }
}
