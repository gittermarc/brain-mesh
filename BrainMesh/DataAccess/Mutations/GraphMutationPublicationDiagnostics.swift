//
//  GraphMutationPublicationDiagnostics.swift
//  BrainMesh
//
//  Data-minimal diagnostics shared by post-commit publishers.
//

import Foundation

#if canImport(os)
import os
#endif

nonisolated enum GraphMutationPublicationDiagnostics {
    static func logIfNeeded(_ receipt: GraphMutationPublishReceipt) {
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
