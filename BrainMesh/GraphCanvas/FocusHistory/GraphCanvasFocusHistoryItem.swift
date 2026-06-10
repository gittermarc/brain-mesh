//
//  GraphCanvasFocusHistoryItem.swift
//  BrainMesh
//
//  Local focus-history item for GraphCanvas.
//

import Foundation

nonisolated struct GraphCanvasFocusHistoryItem: Codable, Hashable, Identifiable, Sendable {
    let graphID: UUID
    let entityID: UUID
    let label: String
    let focusedAt: Date

    var id: String {
        GraphCanvasFocusHistoryIdentity(graphID: graphID, entityID: entityID).id
    }
}

nonisolated struct GraphCanvasFocusHistoryIdentity: Hashable, Sendable {
    let graphID: UUID
    let entityID: UUID

    var id: String {
        "\(graphID.uuidString)|\(entityID.uuidString)"
    }
}

nonisolated extension GraphCanvasFocusHistoryItem {
    var identity: GraphCanvasFocusHistoryIdentity {
        GraphCanvasFocusHistoryIdentity(graphID: graphID, entityID: entityID)
    }
}
