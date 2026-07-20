//
//  GraphBootstrap.swift
//  BrainMesh
//
//  Created by Marc Fechner on 15.12.25.
//

import Foundation
import SwiftData

nonisolated enum GraphBootstrapError: LocalizedError, Equatable, Sendable {
    case missingGraphScope

    var errorDescription: String? {
        "Eine Bootstrap-Reparatur konnte keinem Graphen zugeordnet werden."
    }
}

@MainActor
enum GraphBootstrap {
    static func integrityRepairBatches(
        graphIDs: Set<UUID>
    ) throws -> [GraphMutationBatch] {
        try graphIDs
            .sorted { lhs, rhs in lhs.uuidString < rhs.uuidString }
            .map { graphID in
                try GraphMutationBatchFactory.graphIntegrityRepair(graphID: graphID)
            }
    }
}
