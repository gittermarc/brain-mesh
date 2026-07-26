//
//  GraphTransferErrors.swift
//  BrainMesh
//

import Foundation

enum GraphTransferError: Error, Sendable {
    case notConfigured
    case notImplemented

    // File IO
    case fileAccessDenied
    case readFailed(underlying: String)
    case writeFailed(underlying: String)
    case decodeFailed(underlying: String)
    case saveFailed(underlying: String)
    case importCleanupFailed
    case backupPackageWriteFailed(underlying: String)
    case backupAttachmentReadFailed(attachmentID: UUID, underlying: String)
    case backupAttachmentWriteFailed(attachmentID: UUID, underlying: String)
    case backupManifestWriteFailed(underlying: String)
    case backupManifestReadFailed(underlying: String)
    case backupCoreGraphMissing(filename: String)
    case backupCoreGraphInvalid(underlying: String)
    case backupCoreGraphMismatch
    case backupAttachmentMissing(attachmentID: UUID)
    case backupAttachmentSizeMismatch(attachmentID: UUID, expected: Int64, actual: Int64)
    case backupAttachmentChecksumMismatch(attachmentID: UUID)
    case invalidBackupFormat
    case unsupportedBackupVersion(found: Int)
    case fullBackupImportNotAvailable

    // Validation
    case invalidFormat
    case unsupportedVersion(found: Int)
    case invalidDetailData

    // Domain
    case graphNotFound(graphID: UUID)
}

extension GraphTransferError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Export & Import ist noch nicht bereit."
        case .notImplemented:
            return "Diese Transfer-Funktion ist in dieser Version nicht verfügbar."

        case .fileAccessDenied:
            return "BrainMesh hat keinen Zugriff auf die ausgewählte Datei."
        case .readFailed:
            return "Die Datei konnte nicht gelesen werden."
        case .writeFailed:
            return "Die Exportdatei konnte nicht erstellt werden."
        case .decodeFailed:
            return "Die .bmgraph-Datei konnte nicht gelesen werden."
        case .saveFailed:
            return "Der Import konnte nicht gespeichert werden."
        case .importCleanupFailed:
            return "Ein unvollständiger Import konnte nicht vollständig bereinigt werden."
        case .backupPackageWriteFailed:
            return "Das Full-Backup-Paket konnte nicht erstellt werden."
        case .backupAttachmentReadFailed:
            return "Ein Anhang konnte nicht für das Full Backup gelesen werden."
        case .backupAttachmentWriteFailed:
            return "Ein Anhang konnte nicht in das Full Backup geschrieben werden."
        case .backupManifestWriteFailed:
            return "Das Full-Backup-Manifest konnte nicht geschrieben werden."
        case .backupManifestReadFailed:
            return "Das Full-Backup-Manifest konnte nicht gelesen werden."
        case .backupCoreGraphMissing:
            return "Die Graph-Struktur fehlt im Full Backup."
        case .backupCoreGraphInvalid:
            return "Die Graph-Struktur im Full Backup konnte nicht geprüft werden."
        case .backupCoreGraphMismatch:
            return "Manifest und Graph-Struktur im Full Backup passen nicht zusammen."
        case .backupAttachmentMissing:
            return "Ein Anhang fehlt im Full Backup und wurde übersprungen."
        case .backupAttachmentSizeMismatch:
            return "Ein Anhang im Full Backup hat eine unerwartete Dateigröße und wurde übersprungen."
        case .backupAttachmentChecksumMismatch:
            return "Ein Anhang im Full Backup wirkt beschädigt und wurde übersprungen."
        case .invalidBackupFormat:
            return "Diese Datei ist kein gültiges BrainMesh-Full-Backup."
        case .unsupportedBackupVersion:
            return "Dieses Full Backup wurde mit einer neueren BrainMesh-Version erstellt."
        case .fullBackupImportNotAvailable:
            return "Full-Backup-Import ist für diese Datei nicht möglich."

        case .invalidFormat:
            return "Diese Datei ist keine gültige BrainMesh-.bmgraph-Datei."
        case .unsupportedVersion:
            return "Diese .bmgraph-Datei wurde mit einer neueren BrainMesh-Version erstellt."
        case .invalidDetailData:
            return "Die Detaildaten der Importdatei sind nicht eindeutig oder graphkonsistent."

        case .graphNotFound:
            return "Der gewählte Graph wurde nicht gefunden."
        }
    }
}
