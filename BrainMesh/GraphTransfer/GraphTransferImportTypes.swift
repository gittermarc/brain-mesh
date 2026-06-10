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

    nonisolated enum Phase: Sendable, Equatable {
        case inspecting
        case creatingGraph
        case exportingGraph
        case backupAttachments
        case backupManifest
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

nonisolated enum GraphTransferExportProgressFactory {

    static func exportingGraph() -> GraphTransferProgress {
        GraphTransferProgress(phase: .exportingGraph, completed: 0, label: "Graph-Struktur wird exportiert")
    }

    static func backupAttachmentsStart(total: Int) -> GraphTransferProgress {
        GraphTransferProgress(phase: .backupAttachments, completed: 0, total: total, label: "Anhänge werden exportiert")
    }

    static func backupAttachmentStep(completed: Int, total: Int) -> GraphTransferProgress {
        GraphTransferProgress(
            phase: .backupAttachments,
            completed: completed,
            total: total,
            label: "Anhänge: \(completed)/\(total)"
        )
    }

    static func writingBackupManifest() -> GraphTransferProgress {
        GraphTransferProgress(phase: .backupManifest, completed: 0, label: "Backup-Manifest wird geschrieben")
    }

    static func done() -> GraphTransferProgress {
        GraphTransferProgress(phase: .done, completed: 1, total: 1, label: "Fertig")
    }
}

nonisolated enum GraphTransferImportProgressFactory {

    static func inspecting() -> GraphTransferProgress {
        GraphTransferProgress(phase: .inspecting, completed: 0, label: "Datei wird geprüft…")
    }

    static func creatingGraph() -> GraphTransferProgress {
        GraphTransferProgress(phase: .creatingGraph, completed: 0, label: "Neuer Graph wird angelegt…")
    }

    static func phaseStart(
        _ phase: GraphTransferProgress.Phase,
        total: Int,
        label: String
    ) -> GraphTransferProgress {
        GraphTransferProgress(phase: phase, completed: 0, total: total, label: label)
    }

    static func phaseStep(
        _ phase: GraphTransferProgress.Phase,
        completed: Int,
        total: Int,
        noun: String
    ) -> GraphTransferProgress {
        GraphTransferProgress(
            phase: phase,
            completed: completed,
            total: total,
            label: "\(noun): \(completed)/\(total)"
        )
    }

    static func saving() -> GraphTransferProgress {
        GraphTransferProgress(phase: .saving, completed: 0, label: "Speichere…")
    }

    static func done() -> GraphTransferProgress {
        GraphTransferProgress(phase: .done, completed: 1, total: 1, label: "Fertig")
    }
}

nonisolated enum GraphTransferImportNodeRemapper {
    static func remapNodeID(
        kindRaw: Int,
        oldID: UUID,
        entityIDMap: [UUID: UUID],
        attributeIDMap: [UUID: UUID]
    ) -> UUID? {
        if kindRaw == NodeKind.entity.rawValue {
            return entityIDMap[oldID]
        }
        if kindRaw == NodeKind.attribute.rawValue {
            return attributeIDMap[oldID]
        }
        return nil
    }
}

nonisolated enum GraphTransferImportDetailValueDeduper {
    static func shouldImport(fieldID: UUID, existingFieldIDs: Set<UUID>) -> Bool {
        existingFieldIDs.contains(fieldID) == false
    }
}
