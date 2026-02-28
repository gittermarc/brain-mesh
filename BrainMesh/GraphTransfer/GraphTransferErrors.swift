//
//  GraphTransferErrors.swift
//  BrainMesh
//

import Foundation

enum GraphTransferError: Error {
    case notConfigured
    case notImplemented

    case fileAccessDenied

    case invalidFormat(expected: String, actual: String)
    case unsupportedVersion(expected: Int, actual: Int)
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
        case .invalidFormat(let expected, let actual):
            return "Invalid export format (expected \(expected), got \(actual))"
        case .unsupportedVersion(let expected, let actual):
            return "Unsupported export version (expected \(expected), got \(actual))"
        }
    }
}
