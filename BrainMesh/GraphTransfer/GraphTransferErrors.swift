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
            return "GraphTransferService is not configured"
        case .notImplemented:
            return "Graph transfer is not implemented yet"

        case .fileAccessDenied:
            return "File access denied"
        case .readFailed(let underlying):
            return "Failed to read import file (\(underlying))"
        case .writeFailed(let underlying):
            return "Failed to write export file (\(underlying))"
        case .decodeFailed(let underlying):
            return "Failed to decode export file (\(underlying))"
        case .saveFailed(let underlying):
            return "Failed to save imported records (\(underlying))"

        case .invalidFormat:
            return "Invalid export format"
        case .unsupportedVersion(let found):
            return "Unsupported export version (found \(found))"

        case .graphNotFound(let graphID):
            return "Graph not found (\(graphID.uuidString))"
        }
    }
}
