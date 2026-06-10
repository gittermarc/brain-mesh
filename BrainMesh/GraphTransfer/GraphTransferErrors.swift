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
    case backupPackageWriteFailed(underlying: String)
    case backupAttachmentReadFailed(attachmentID: UUID, underlying: String)
    case backupAttachmentWriteFailed(attachmentID: UUID, underlying: String)
    case backupManifestWriteFailed(underlying: String)

    // Validation
    case invalidFormat
    case unsupportedVersion(found: Int)

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
        case .backupPackageWriteFailed:
            return "Das Full-Backup-Paket konnte nicht erstellt werden."
        case .backupAttachmentReadFailed:
            return "Ein Anhang konnte nicht für das Full Backup gelesen werden."
        case .backupAttachmentWriteFailed:
            return "Ein Anhang konnte nicht in das Full Backup geschrieben werden."
        case .backupManifestWriteFailed:
            return "Das Full-Backup-Manifest konnte nicht geschrieben werden."

        case .invalidFormat:
            return "Diese Datei ist keine gültige BrainMesh-.bmgraph-Datei."
        case .unsupportedVersion:
            return "Diese .bmgraph-Datei wurde mit einer neueren BrainMesh-Version erstellt."

        case .graphNotFound:
            return "Der gewählte Graph wurde nicht gefunden."
        }
    }
}
