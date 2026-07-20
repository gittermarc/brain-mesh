//
//  GraphTransferImportTypes.swift
//  BrainMesh
//
//  Types for file inspection + import progress/result.
//

import Foundation

nonisolated enum ImportMode: Sendable {
    case asNewGraphRemap
    case asReplacementRemap

    var completionKind: GraphTransferImportCompletionKind {
        switch self {
        case .asNewGraphRemap:
            return .imported
        case .asReplacementRemap:
            return .replaced
        }
    }
}

nonisolated enum GraphTransferImportCompletionKind: Sendable {
    case imported
    case replaced
}

nonisolated enum GraphTransferPreviewKind: String, Codable, Equatable, Sendable {
    case graphStructure
    case fullBackup

    var title: String {
        switch self {
        case .graphStructure:
            return "Struktur-Export"
        case .fullBackup:
            return "Full Backup"
        }
    }

    var filenameExtension: String {
        switch self {
        case .graphStructure:
            return "bmgraph"
        case .fullBackup:
            return GraphBackupFormat.filenameExtension
        }
    }
}

nonisolated enum GraphBackupPreviewWarningSeverity: String, Codable, Equatable, Sendable {
    case warning
    case blocking

    var title: String {
        switch self {
        case .warning:
            return "Hinweis"
        case .blocking:
            return "Problem"
        }
    }
}

nonisolated struct GraphBackupPreviewWarning: Codable, Equatable, Sendable {
    var severity: GraphBackupPreviewWarningSeverity
    var code: String
    var message: String

    init(severity: GraphBackupPreviewWarningSeverity, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
    }

    static func warning(code: String, message: String) -> GraphBackupPreviewWarning {
        GraphBackupPreviewWarning(severity: .warning, code: code, message: message)
    }

    static func blocking(code: String, message: String) -> GraphBackupPreviewWarning {
        GraphBackupPreviewWarning(severity: .blocking, code: code, message: message)
    }

    var stableID: String {
        "\(severity.rawValue)-\(code)-\(message)"
    }
}

nonisolated struct ImportPreview: Sendable {
    var kind: GraphTransferPreviewKind
    var graphName: String
    var exportedAt: Date
    var version: Int
    var counts: CountsDTO
    var attachmentCount: Int
    var attachmentBytes: Int64
    var warnings: [GraphBackupPreviewWarning]
    var blockingProblems: [GraphBackupPreviewWarning]

    init(
        kind: GraphTransferPreviewKind = .graphStructure,
        graphName: String,
        exportedAt: Date,
        version: Int,
        counts: CountsDTO,
        attachmentCount: Int = 0,
        attachmentBytes: Int64 = 0,
        warnings: [GraphBackupPreviewWarning] = [],
        blockingProblems: [GraphBackupPreviewWarning] = []
    ) {
        self.kind = kind
        self.graphName = graphName
        self.exportedAt = exportedAt
        self.version = version
        self.counts = counts
        self.attachmentCount = attachmentCount
        self.attachmentBytes = attachmentBytes
        self.warnings = warnings
        self.blockingProblems = blockingProblems
    }

    var canStartImport: Bool {
        blockingProblems.isEmpty
    }

    var isFullBackup: Bool {
        kind == .fullBackup
    }

    var attachmentBytesText: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: attachmentBytes)
    }
}

nonisolated struct ImportResult: Sendable {
    var newGraphID: UUID
    var insertedCounts: CountsDTO
    var skippedLinks: Int
    var importedAttachments: Int
    var skippedAttachments: Int
    var warnings: [String]

    init(
        newGraphID: UUID,
        insertedCounts: CountsDTO,
        skippedLinks: Int,
        importedAttachments: Int = 0,
        skippedAttachments: Int = 0,
        warnings: [String] = []
    ) {
        self.newGraphID = newGraphID
        self.insertedCounts = insertedCounts
        self.skippedLinks = skippedLinks
        self.importedAttachments = importedAttachments
        self.skippedAttachments = skippedAttachments
        self.warnings = warnings
    }
}

nonisolated struct GraphTransferCoreImportResult: Sendable {
    var newGraphID: UUID
    var entityIDMap: [UUID: UUID]
    var attributeIDMap: [UUID: UUID]
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
        case attachments
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

    static func importingAttachmentsStart(total: Int) -> GraphTransferProgress {
        GraphTransferProgress(phase: .attachments, completed: 0, total: total, label: "Anhänge werden importiert…")
    }

    static func importingAttachmentStep(completed: Int, total: Int) -> GraphTransferProgress {
        GraphTransferProgress(
            phase: .attachments,
            completed: completed,
            total: total,
            label: "Anhänge: \(completed)/\(total)"
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
