//
//  GraphTransferImportTypes.swift
//  BrainMesh
//
//  Types for file inspection + import progress/result.
//

import Foundation

nonisolated enum ImportMode: Sendable {
    case asNewGraphRemap
}

nonisolated struct ImportPreview: Sendable {
    var graphName: String
    var exportedAt: Date
    var version: Int
    var counts: CountsDTO
}

nonisolated struct ImportResult: Sendable {
    var newGraphID: UUID
    var insertedCounts: CountsDTO
    var skippedLinks: Int
}

nonisolated struct GraphTransferProgress: Sendable {

    nonisolated enum Phase: Sendable {
        case inspecting
        case creatingGraph
        case entities
        case fields
        case attributes
        case values
        case links
        case saving
        case done
    }

    var phase: Phase
    var completed: Int
    var total: Int?
    var fraction: Double?
    var label: String

    init(phase: Phase, completed: Int, total: Int? = nil, label: String) {
        self.phase = phase
        self.completed = completed
        self.total = total
        self.label = label

        if let total, total > 0 {
            self.fraction = Double(completed) / Double(total)
        } else {
            self.fraction = nil
        }
    }
}
