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

        case .invalidFormat:
            return "Diese Datei ist keine gültige BrainMesh-.bmgraph-Datei."
        case .unsupportedVersion:
            return "Diese .bmgraph-Datei wurde mit einer neueren BrainMesh-Version erstellt."

        case .graphNotFound:
            return "Der gewählte Graph wurde nicht gefunden."
        }
    }
}
