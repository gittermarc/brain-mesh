//
//  GraphSearchIndexStore.swift
//  BrainMesh
//
//  Actor-isolated local SQLite store for reconstructable graph search documents.
//

import Foundation
import os

nonisolated enum GraphSearchIndexBackend: String, Codable, CaseIterable, Sendable {
    case fts5Trigram = "fts5-trigram"
    case fts5Unicode = "fts5-unicode61"
    case indexedFallback = "indexed-fallback"

    var usesFTS5: Bool {
        switch self {
        case .fts5Trigram, .fts5Unicode:
            return true
        case .indexedFallback:
            return false
        }
    }
}

nonisolated enum GraphSearchIndexBackendPreference: Equatable, Sendable {
    case automatic
    case indexedFallback
}

nonisolated struct GraphSearchIndexManifest: Equatable, Sendable {
    let schemaVersion: Int
    let backend: GraphSearchIndexBackend
    let documentCount: Int
    let graphCount: Int
    let createdAt: Date
    let rebuiltAt: Date
}

nonisolated enum GraphSearchIndexStoreError: Error, Sendable {
    case notOpen
    case invalidDocument(reason: String)
    case invalidGraphReplacement(expected: UUID, actual: UUID)
    case invalidSourceReplacement(
        expected: GraphSearchSourceReference,
        actual: GraphSearchSourceReference
    )
    case incompatibleDocumentSchemaVersion(expected: Int, actual: Int)
    case invalidStoredValue(column: String)
    case metadataEncoding(type: String)
    case metadataDecoding(type: String)
    case fileSystem(operation: String, reason: String)
    case sqlite(operation: String, code: Int32, extendedCode: Int32)
}

extension GraphSearchIndexStoreError: LocalizedError {
    nonisolated var errorDescription: String? {
        switch self {
        case .notOpen:
            return "The graph search index store is not open."
        case .invalidDocument(let reason):
            return "The graph search document is invalid: \(reason)"
        case .invalidGraphReplacement(let expected, let actual):
            return "A graph replacement document belongs to \(actual.uuidString) instead of \(expected.uuidString)."
        case .invalidSourceReplacement(let expected, let actual):
            return "A source replacement document belongs to \(actual.sourceKind.rawValue)/\(actual.sourceID.uuidString) instead of \(expected.sourceKind.rawValue)/\(expected.sourceID.uuidString)."
        case .incompatibleDocumentSchemaVersion(let expected, let actual):
            return "The graph search document schema version \(actual) is incompatible with version \(expected)."
        case .invalidStoredValue(let column):
            return "The graph search index contains an invalid value in column \(column)."
        case .metadataEncoding(let type):
            return "The graph search index could not encode \(type) metadata."
        case .metadataDecoding(let type):
            return "The graph search index could not decode \(type) metadata."
        case .fileSystem(let operation, let reason):
            return "The graph search index file operation \(operation) failed: \(reason)"
        case .sqlite(let operation, let code, let extendedCode):
            return "SQLite operation \(operation) failed with code \(code) (extended \(extendedCode))."
        }
    }
}

actor GraphSearchIndexStore {
    static let defaultBatchSize = 128
    static let maximumSearchLimit = 500

    let configuredDatabaseURL: URL?
    let backendPreference: GraphSearchIndexBackendPreference
    let batchSize: Int
    let cancellationCheck: @Sendable () throws -> Void

    var resolvedDatabaseURL: URL?
    var connection: GraphSearchSQLiteConnection?
    var activeBackend: GraphSearchIndexBackend?

    init(
        databaseURL: URL? = nil,
        backendPreference: GraphSearchIndexBackendPreference = .automatic,
        batchSize: Int = GraphSearchIndexStore.defaultBatchSize,
        cancellationCheck: @escaping @Sendable () throws -> Void = {
            try Task.checkCancellation()
        }
    ) {
        self.configuredDatabaseURL = databaseURL
        self.backendPreference = backendPreference
        self.batchSize = max(1, batchSize)
        self.cancellationCheck = cancellationCheck
    }

    var isOpen: Bool {
        connection != nil
    }

    var databaseURL: URL? {
        resolvedDatabaseURL
    }

    func open() throws -> GraphSearchIndexManifest {
        try openStore()
    }

    func close() throws {
        guard let connection else { return }
        do {
            try connection.close()
            self.connection = nil
            activeBackend = nil
        } catch let error as GraphSearchSQLiteError {
            throw mapSQLiteError(error)
        }
    }

    func rebuild() throws -> GraphSearchIndexManifest {
        let startedAt = Self.uptimeNanoseconds()
        let databaseURL = try resolveAndPrepareDatabaseURL()
        try closeForReplacement()
        try removeDatabaseFiles(at: databaseURL)
        let manifest = try openFreshDatabase(at: databaseURL)
        BMLog.search.info(
            "Search index rebuilt version=\(manifest.schemaVersion) backend=\(manifest.backend.rawValue, privacy: .public) documents=\(manifest.documentCount) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
        return manifest
    }

    func clear() throws {
        _ = try requireConnection()
        let startedAt = Self.uptimeNanoseconds()
        try withTransaction(operation: "clear-store") { store in
            let connection = try store.requireConnection()
            try store.cancellationCheck()
            try connection.execute(
                "DELETE FROM graph_search_documents",
                operation: "clear-documents"
            )
            try store.cancellationCheck()
        }
        BMLog.search.info(
            "Search index cleared durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }
}
