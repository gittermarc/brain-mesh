//
//  GraphTransferPresentation.swift
//  BrainMesh
//
//  Small value-only presentation helpers for transfer UI copy.
//

import Foundation
import UniformTypeIdentifiers

nonisolated enum GraphTransferExportKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case graphStructure
    case fullBackup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphStructure:
            return "Struktur-Export"
        case .fullBackup:
            return "Vollbackup"
        }
    }

    var shortTitle: String {
        switch self {
        case .graphStructure:
            return ".bmgraph"
        case .fullBackup:
            return ".bmbackup"
        }
    }

    var fileExtension: String {
        switch self {
        case .graphStructure:
            return UTType.brainMeshGraphFilenameExtension
        case .fullBackup:
            return UTType.brainMeshBackupFilenameExtension
        }
    }

    var contentType: UTType {
        switch self {
        case .graphStructure:
            return .brainMeshGraph
        case .fullBackup:
            return .brainMeshBackup
        }
    }

    var systemImage: String {
        switch self {
        case .graphStructure:
            return "doc.text"
        case .fullBackup:
            return "shippingbox"
        }
    }

    var defaultFilename: String {
        switch self {
        case .graphStructure:
            return "BrainMesh-Graph"
        case .fullBackup:
            return "BrainMesh-Vollbackup"
        }
    }
}

nonisolated struct GraphTransferAttachmentEstimate: Equatable, Sendable {
    static let largeBackupThresholdBytes: Int64 = 250 * 1024 * 1024
    static let empty = GraphTransferAttachmentEstimate(count: 0, byteCount: 0)

    var count: Int
    var byteCount: Int64

    init(count: Int, byteCount: Int64) {
        self.count = max(0, count)
        self.byteCount = max(0, byteCount)
    }

    var hasAttachments: Bool {
        count > 0
    }

    var isLargeBackup: Bool {
        byteCount >= Self.largeBackupThresholdBytes
    }

    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var compactSummary: String {
        if count == 0 {
            return "Keine Anhänge im aktiven Graph gefunden."
        }
        let noun = count == 1 ? "Anhang-Datei" : "Anhang-Dateien"
        return "\(count) \(noun), ca. \(formattedByteCount)"
    }
}

nonisolated enum GraphTransferExportCopy {

    static func confirmMessage(
        kind: GraphTransferExportKind,
        activeGraphName: String,
        includeNotes: Bool,
        includeIcons: Bool,
        includeHeaderImages: Bool,
        includeAttachments: Bool,
        attachmentEstimate: GraphTransferAttachmentEstimate
    ) -> String {
        var parts: [String] = []
        parts.append("Aktiver Graph: \(activeGraphName)")
        parts.append("Dateityp: \(kind.shortTitle) · \(kind.title)")

        switch kind {
        case .graphStructure:
            parts.append("Enthalten: Graph-Struktur, Entitäten, Attribute, Links, Details-Felder und Details-Werte.")
            appendCoreOptions(
                includeNotes: includeNotes,
                includeIcons: includeIcons,
                includeHeaderImages: includeHeaderImages,
                to: &parts
            )
            parts.append("Nicht enthalten: separate Anhänge, Dateien, Videos, Galerie-Bilder, Graph-Schutz und Pro-Status.")

        case .fullBackup:
            parts.append("Enthalten: Graph-Struktur plus Backup-Manifest.")
            appendCoreOptions(
                includeNotes: includeNotes,
                includeIcons: includeIcons,
                includeHeaderImages: includeHeaderImages,
                to: &parts
            )
            if includeAttachments {
                parts.append("Anhänge: \(attachmentEstimate.compactSummary)")
                if attachmentEstimate.isLargeBackup {
                    parts.append("Hinweis: Dieses Backup kann wegen großer Anhänge länger dauern und viel Speicher benötigen.")
                }
            } else {
                parts.append("Anhänge sind für dieses Vollbackup ausgeschaltet.")
            }
            parts.append("Nicht enthalten: Graph-Schutz, Passwörter, Biometrie-Einstellungen und Pro-Status.")
        }

        return parts.joined(separator: "\n")
    }

    static func readySummary(
        kind: GraphTransferExportKind,
        counts: CountsDTO,
        attachmentCount: Int,
        attachmentBytes: Int64,
        warningCount: Int
    ) -> String {
        var parts: [String] = []
        parts.append(kind == .graphStructure ? "Graph-Struktur-Export" : "Vollbackup")
        parts.append("\(counts.entities) Entitäten")
        parts.append("\(counts.attributes) Attribute")
        parts.append("\(counts.links) Links")
        parts.append("\(counts.detailFieldDefinitions) Details-Felder")
        parts.append("\(counts.detailFieldValues) Details-Werte")

        switch kind {
        case .graphStructure:
            parts.append("keine separaten Anhänge")
        case .fullBackup:
            let bytesText = ByteCountFormatter.string(fromByteCount: attachmentBytes, countStyle: .file)
            parts.append("\(attachmentCount) Anhänge")
            parts.append(bytesText)
            if warningCount > 0 {
                let warningNoun = warningCount == 1 ? "Hinweis" : "Hinweise"
                parts.append("\(warningCount) \(warningNoun)")
            }
        }

        return parts.joined(separator: " · ")
    }

    private static func appendCoreOptions(
        includeNotes: Bool,
        includeIcons: Bool,
        includeHeaderImages: Bool,
        to parts: inout [String]
    ) {
        var selectedOptions: [String] = []
        if includeNotes { selectedOptions.append("Notizen") }
        if includeIcons { selectedOptions.append("Icons") }
        if includeHeaderImages { selectedOptions.append("Headerbilder von Entitäten/Attributen") }

        if selectedOptions.isEmpty {
            parts.append("Keine Zusatzoptionen ausgewählt.")
        } else {
            parts.append("Zusätzlich ausgewählt: \(selectedOptions.joined(separator: ", ")).")
        }
    }
}

nonisolated enum GraphTransferPreviewCopy {

    static func headline(for preview: ImportPreview) -> String {
        switch preview.kind {
        case .graphStructure:
            return "Struktur-Export importieren"
        case .fullBackup:
            return "Vollbackup importieren"
        }
    }

    static func scopeSummary(for preview: ImportPreview) -> String {
        switch preview.kind {
        case .graphStructure:
            return "Diese .bmgraph-Datei wird als neuer Graph importiert. Separate Anhänge sind in diesem Format nicht enthalten."
        case .fullBackup:
            return "Dieses .bmbackup-Paket wird als neuer Graph importiert. Anhänge werden wiederhergestellt, soweit die Paketdateien vollständig und prüfbar sind."
        }
    }

    static func issueSummary(for preview: ImportPreview) -> String? {
        if preview.blockingProblems.isEmpty == false {
            return "\(preview.blockingProblems.count) blockierende Problem(e). Import ist nicht möglich."
        }
        if preview.warnings.isEmpty == false {
            return "\(preview.warnings.count) Hinweis(e). Der Import kann starten, einzelne Anhänge können aber übersprungen werden."
        }
        return nil
    }

    static func resultTitle(for result: ImportResult) -> String {
        if result.skippedAttachments > 0 || result.warnings.isEmpty == false || result.skippedLinks > 0 {
            return "Import teilweise abgeschlossen"
        }
        return "Import abgeschlossen"
    }

    static func resultSummary(for result: ImportResult) -> String {
        var parts: [String] = []
        parts.append("\(result.insertedCounts.entities) Entitäten")
        parts.append("\(result.insertedCounts.attributes) Attribute")
        parts.append("\(result.insertedCounts.links) Links")
        if result.importedAttachments > 0 || result.skippedAttachments > 0 {
            parts.append("\(result.importedAttachments) importierte Anhänge")
        }
        if result.skippedAttachments > 0 {
            parts.append("\(result.skippedAttachments) übersprungen")
        }
        return parts.joined(separator: " · ")
    }
}
