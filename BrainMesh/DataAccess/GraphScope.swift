//
//  GraphScope.swift
//  BrainMesh
//
//  Non-optional graph identity used by the centralized read layer.
//

import Foundation

nonisolated struct GraphScope: Hashable, Sendable, Identifiable {
    let graphID: UUID

    var id: UUID {
        graphID
    }

    init(graphID: UUID) {
        self.graphID = graphID
    }

    init?(_ uuidString: String) {
        guard let graphID = UUID(uuidString: uuidString) else {
            return nil
        }
        self.graphID = graphID
    }
}
