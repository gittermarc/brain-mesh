//
//  GraphSearchIndexStore+Schema.swift
//  BrainMesh
//
//  Database location, schema lifecycle, integrity checks and safe replacement.
//

import Foundation
import os

extension GraphSearchIndexStore {
    func openStore() throws -> GraphSearchIndexManifest {
        if connection != nil {
            return try manifest()
        }

        let startedAt = Self.uptimeNanoseconds()
        let databaseURL = try resolveAndPrepareDatabaseURL()

        do {
            let openedConnection = try GraphSearchSQLiteConnection(databaseURL: databaseURL)
            connection = openedConnection
            resolvedDatabaseURL = databaseURL
            try configure(openedConnection)
            let storedVersion = try readUserVersion(from: openedConnection)

            if storedVersion == 0 {
                if try hasExistingUserSchema(in: openedConnection) {
                    try closeForReplacement()
                    try removeDatabaseFiles(at: databaseURL)
                    return try openFreshDatabaseAndLog(
                        at: databaseURL,
                        startedAt: startedAt,
                        reason: "unversioned-schema"
                    )
                }

                let manifest = try initializeFreshSchema(
                    connection: openedConnection,
                    databaseURL: databaseURL
                )
                logOpen(manifest: manifest, startedAt: startedAt)
                return manifest
            }

            guard storedVersion == GraphSearchIndexSchema.currentVersion else {
                BMLog.search.notice(
                    "Search index schema incompatible stored=\(storedVersion) expected=\(GraphSearchIndexSchema.currentVersion); rebuilding"
                )
                try closeForReplacement()
                try removeDatabaseFiles(at: databaseURL)
                return try openFreshDatabaseAndLog(
                    at: databaseURL,
                    startedAt: startedAt,
                    reason: "schema-version"
                )
            }

            try verifyIntegrity(of: openedConnection)
            let backend = try readStoredBackend(from: openedConnection)
            try verifyRequiredSchema(in: openedConnection, backend: backend)

            activeBackend = backend
            try applyBackupExclusionIfRequired(to: databaseURL)

            let manifest = try readManifest(
                connection: openedConnection,
                backend: backend
            )
            logOpen(manifest: manifest, startedAt: startedAt)
            return manifest
        } catch let error as GraphSearchSQLiteError {
            if error.isCorruption {
                BMLog.search.error(
                    "Search index corruption detected operation=\(error.operation, privacy: .public) code=\(error.code) extended=\(error.extendedCode); rebuilding"
                )
                try closeForReplacement()
                try removeDatabaseFiles(at: databaseURL)
                return try openFreshDatabaseAndLog(
                    at: databaseURL,
                    startedAt: startedAt,
                    reason: "corruption"
                )
            }
            if error.isFTS5Unavailable
                || error.isFTSTokenizerUnavailable
                || error.isSearchSchemaUnavailable {
                BMLog.search.notice(
                    "Stored search backend or schema unavailable operation=\(error.operation, privacy: .public) code=\(error.code); rebuilding"
                )
                try closeForReplacement()
                try removeDatabaseFiles(at: databaseURL)
                return try openFreshDatabaseAndLog(
                    at: databaseURL,
                    startedAt: startedAt,
                    reason: "backend-or-schema-unavailable"
                )
            }
            let mappedError = mapSQLiteError(error)
            do {
                try closeForReplacement()
            } catch {
                BMLog.search.error("Search index close after open failure")
            }
            throw mappedError
        } catch let error as GraphSearchIndexStoreError {
            switch error {
            case .invalidStoredValue:
                BMLog.search.error(
                    "Search index metadata invalid; rebuilding version=\(GraphSearchIndexSchema.currentVersion)"
                )
                try closeForReplacement()
                try removeDatabaseFiles(at: databaseURL)
                return try openFreshDatabaseAndLog(
                    at: databaseURL,
                    startedAt: startedAt,
                    reason: "invalid-metadata"
                )
            default:
                do {
                    try closeForReplacement()
                } catch {
                    BMLog.search.error("Search index close after metadata failure")
                }
                throw error
            }
        }
    }

    func openFreshDatabase(at databaseURL: URL) throws -> GraphSearchIndexManifest {
        let openedConnection: GraphSearchSQLiteConnection
        do {
            openedConnection = try GraphSearchSQLiteConnection(databaseURL: databaseURL)
            try configure(openedConnection)
        } catch let error as GraphSearchSQLiteError {
            throw mapSQLiteError(error)
        }

        connection = openedConnection
        resolvedDatabaseURL = databaseURL

        do {
            return try initializeFreshSchema(
                connection: openedConnection,
                databaseURL: databaseURL
            )
        } catch {
            do {
                try openedConnection.close()
                connection = nil
                activeBackend = nil
            } catch let closeError as GraphSearchSQLiteError {
                BMLog.search.error(
                    "Search index close after initialization failure code=\(closeError.code) extended=\(closeError.extendedCode)"
                )
            }
            throw error
        }
    }

    func initializeFreshSchema(
        connection: GraphSearchSQLiteConnection,
        databaseURL: URL
    ) throws -> GraphSearchIndexManifest {
        let now = Date()
        let backend: GraphSearchIndexBackend

        do {
            backend = try withTransaction(
                operation: "initialize-schema"
            ) { store in
                let transactionConnection = try store.requireConnection()
                try store.createBaseSchema(in: transactionConnection)
                let selectedBackend = try store.createSearchBackend(in: transactionConnection)
                try store.insertManifest(
                    connection: transactionConnection,
                    backend: selectedBackend,
                    createdAt: now,
                    rebuiltAt: now
                )
                try transactionConnection.execute(
                    "PRAGMA application_id = \(GraphSearchIndexSchema.sqliteApplicationID)",
                    operation: "set-application-id"
                )
                try transactionConnection.execute(
                    "PRAGMA user_version = \(GraphSearchIndexSchema.currentVersion)",
                    operation: "set-user-version"
                )
                return selectedBackend
            }
        } catch let error as GraphSearchSQLiteError {
            throw mapSQLiteError(error)
        }

        activeBackend = backend
        try applyBackupExclusionIfRequired(to: databaseURL)
        return try readManifest(connection: connection, backend: backend)
    }

    func createBaseSchema(in connection: GraphSearchSQLiteConnection) throws {
        try connection.execute(
            """
            CREATE TABLE graph_search_documents (
                storage_id INTEGER PRIMARY KEY,
                document_id TEXT NOT NULL UNIQUE,
                graph_id TEXT NOT NULL,
                document_kind TEXT NOT NULL,
                source_kind TEXT NOT NULL,
                source_id TEXT NOT NULL,
                owner_kind_raw INTEGER,
                owner_id TEXT,
                node_kind_raw INTEGER,
                node_id TEXT,
                field_id TEXT,
                title TEXT NOT NULL,
                subtitle TEXT NOT NULL,
                normalized_search_text TEXT NOT NULL,
                ranking_boost INTEGER NOT NULL,
                ranking_json TEXT NOT NULL,
                navigation_json TEXT NOT NULL,
                evidence_json TEXT NOT NULL,
                attachment_json TEXT,
                content_hash TEXT NOT NULL,
                index_schema_version INTEGER NOT NULL,
                CHECK ((owner_kind_raw IS NULL) = (owner_id IS NULL)),
                CHECK ((node_kind_raw IS NULL) = (node_id IS NULL))
            )
            """,
            operation: "create-documents-table"
        )
        try connection.execute(
            "CREATE INDEX graph_search_documents_graph_idx ON graph_search_documents(graph_id, document_kind, document_id)",
            operation: "create-documents-graph-index"
        )
        try connection.execute(
            "CREATE INDEX graph_search_documents_source_idx ON graph_search_documents(graph_id, source_kind, source_id)",
            operation: "create-documents-source-index"
        )
        try connection.execute(
            "CREATE INDEX graph_search_documents_owner_idx ON graph_search_documents(graph_id, owner_kind_raw, owner_id)",
            operation: "create-documents-owner-index"
        )
        try connection.execute(
            "CREATE INDEX graph_search_documents_node_idx ON graph_search_documents(graph_id, node_kind_raw, node_id)",
            operation: "create-documents-node-index"
        )
        try connection.execute(
            "CREATE INDEX graph_search_documents_field_idx ON graph_search_documents(graph_id, field_id)",
            operation: "create-documents-field-index"
        )
        try connection.execute(
            """
            CREATE TABLE graph_search_ngrams (
                document_id TEXT NOT NULL,
                graph_id TEXT NOT NULL,
                gram TEXT NOT NULL,
                PRIMARY KEY (document_id, gram),
                FOREIGN KEY (document_id)
                    REFERENCES graph_search_documents(document_id)
                    ON DELETE CASCADE
            ) WITHOUT ROWID
            """,
            operation: "create-ngrams-table"
        )
        try connection.execute(
            "CREATE INDEX graph_search_ngrams_graph_idx ON graph_search_ngrams(graph_id, gram, document_id)",
            operation: "create-ngrams-graph-index"
        )
        try connection.execute(
            "CREATE INDEX graph_search_ngrams_global_idx ON graph_search_ngrams(gram, document_id, graph_id)",
            operation: "create-ngrams-global-index"
        )
        try connection.execute(
            """
            CREATE TABLE graph_search_manifest (
                id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
                schema_version INTEGER NOT NULL,
                backend TEXT NOT NULL,
                created_at REAL NOT NULL,
                rebuilt_at REAL NOT NULL
            )
            """,
            operation: "create-manifest-table"
        )
        try connection.execute(
            """
            CREATE TABLE graph_search_source_manifests (
                graph_id TEXT PRIMARY KEY NOT NULL,
                format_version INTEGER NOT NULL,
                index_schema_version INTEGER NOT NULL,
                source_count INTEGER NOT NULL,
                document_count INTEGER NOT NULL,
                aggregate_hash TEXT NOT NULL,
                CHECK (source_count >= 0),
                CHECK (document_count >= 0)
            ) WITHOUT ROWID
            """,
            operation: "create-source-manifests-table"
        )
        try connection.execute(
            """
            CREATE TABLE graph_search_source_manifest_entries (
                graph_id TEXT NOT NULL,
                source_kind TEXT NOT NULL,
                source_id TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                document_count INTEGER NOT NULL,
                PRIMARY KEY (graph_id, source_kind, source_id),
                FOREIGN KEY (graph_id)
                    REFERENCES graph_search_source_manifests(graph_id)
                    ON DELETE CASCADE,
                CHECK (document_count >= 0)
            ) WITHOUT ROWID
            """,
            operation: "create-source-manifest-entries-table"
        )
        try connection.execute(
            """
            CREATE TABLE graph_search_source_manifest_counts (
                graph_id TEXT NOT NULL,
                source_kind TEXT NOT NULL,
                source_count INTEGER NOT NULL,
                PRIMARY KEY (graph_id, source_kind),
                FOREIGN KEY (graph_id)
                    REFERENCES graph_search_source_manifests(graph_id)
                    ON DELETE CASCADE,
                CHECK (source_count >= 0)
            ) WITHOUT ROWID
            """,
            operation: "create-source-manifest-counts-table"
        )
    }

    func createSearchBackend(
        in connection: GraphSearchSQLiteConnection
    ) throws -> GraphSearchIndexBackend {
        guard backendPreference == .automatic else {
            return .indexedFallback
        }

        do {
            try createFTS5Schema(
                in: connection,
                tokenizer: "trigram",
                operationSuffix: "trigram"
            )
            return .fts5Trigram
        } catch let error as GraphSearchSQLiteError {
            if error.isFTS5Unavailable {
                BMLog.search.notice(
                    "FTS5 unavailable code=\(error.code); using indexed fallback"
                )
                return .indexedFallback
            }
            guard error.isFTSTokenizerUnavailable else {
                throw error
            }
            BMLog.search.notice(
                "FTS5 trigram tokenizer unavailable code=\(error.code); trying unicode61"
            )
        }

        do {
            try createFTS5Schema(
                in: connection,
                tokenizer: "unicode61 remove_diacritics 2",
                operationSuffix: "unicode61"
            )
            return .fts5Unicode
        } catch let error as GraphSearchSQLiteError {
            if error.isFTS5Unavailable || error.isFTSTokenizerUnavailable {
                BMLog.search.notice(
                    "FTS5 unicode tokenizer unavailable code=\(error.code); using indexed fallback"
                )
                return .indexedFallback
            }
            throw error
        }
    }

    func createFTS5Schema(
        in connection: GraphSearchSQLiteConnection,
        tokenizer: String,
        operationSuffix: String
    ) throws {
        let createTableSQL: String
        switch tokenizer {
        case "trigram":
            createTableSQL = "CREATE VIRTUAL TABLE graph_search_fts USING fts5(normalized_search_text, tokenize = 'trigram')"
        case "unicode61 remove_diacritics 2":
            createTableSQL = "CREATE VIRTUAL TABLE graph_search_fts USING fts5(normalized_search_text, tokenize = 'unicode61 remove_diacritics 2')"
        default:
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "fts-tokenizer")
        }

        try connection.execute(
            createTableSQL,
            operation: "create-fts-\(operationSuffix)"
        )
        try connection.execute(
            """
            CREATE TRIGGER graph_search_documents_fts_insert
            AFTER INSERT ON graph_search_documents
            BEGIN
                INSERT INTO graph_search_fts(rowid, normalized_search_text)
                VALUES (new.rowid, new.normalized_search_text);
            END
            """,
            operation: "create-fts-insert-trigger"
        )
        try connection.execute(
            """
            CREATE TRIGGER graph_search_documents_fts_delete
            AFTER DELETE ON graph_search_documents
            BEGIN
                DELETE FROM graph_search_fts WHERE rowid = old.rowid;
            END
            """,
            operation: "create-fts-delete-trigger"
        )
        try connection.execute(
            """
            CREATE TRIGGER graph_search_documents_fts_update
            AFTER UPDATE OF normalized_search_text ON graph_search_documents
            BEGIN
                DELETE FROM graph_search_fts WHERE rowid = old.rowid;
                INSERT INTO graph_search_fts(rowid, normalized_search_text)
                VALUES (new.rowid, new.normalized_search_text);
            END
            """,
            operation: "create-fts-update-trigger"
        )
    }

    func insertManifest(
        connection: GraphSearchSQLiteConnection,
        backend: GraphSearchIndexBackend,
        createdAt: Date,
        rebuiltAt: Date
    ) throws {
        let statement = try connection.prepare(
            """
            INSERT INTO graph_search_manifest(
                id,
                schema_version,
                backend,
                created_at,
                rebuilt_at
            ) VALUES (1, ?, ?, ?, ?)
            """,
            operation: "insert-manifest"
        )
        try statement.bind(GraphSearchIndexSchema.currentVersion, at: 1)
        try statement.bind(backend.rawValue, at: 2)
        try statement.bind(createdAt.timeIntervalSince1970, at: 3)
        try statement.bind(rebuiltAt.timeIntervalSince1970, at: 4)
        try statement.stepExpectingDone()
    }

    func configure(_ connection: GraphSearchSQLiteConnection) throws {
        try connection.execute(
            "PRAGMA foreign_keys = ON",
            operation: "enable-foreign-keys"
        )
        try connection.setBusyTimeout(milliseconds: 5_000)
        try connection.execute(
            "PRAGMA synchronous = NORMAL",
            operation: "set-synchronous"
        )
        try connection.execute(
            "PRAGMA temp_store = MEMORY",
            operation: "set-temp-store"
        )

        let statement = try connection.prepare(
            "PRAGMA journal_mode = WAL",
            operation: "set-journal-mode"
        )
        guard try statement.step(),
              statement.columnText(at: 0)?.localizedCaseInsensitiveCompare("wal") == .orderedSame
        else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "journal_mode")
        }
    }

    func readUserVersion(
        from connection: GraphSearchSQLiteConnection
    ) throws -> Int {
        let statement = try connection.prepare(
            "PRAGMA user_version",
            operation: "read-user-version"
        )
        guard try statement.step() else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "user_version")
        }
        return statement.columnInt(at: 0)
    }

    func hasExistingUserSchema(
        in connection: GraphSearchSQLiteConnection
    ) throws -> Bool {
        let statement = try connection.prepare(
            """
            SELECT COUNT(*)
            FROM sqlite_master
            WHERE type IN ('table', 'view')
              AND name NOT LIKE 'sqlite_%'
            """,
            operation: "detect-existing-schema"
        )
        guard try statement.step() else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "sqlite_master")
        }
        return statement.columnInt(at: 0) > 0
    }

    func verifyIntegrity(
        of connection: GraphSearchSQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            "PRAGMA quick_check(1)",
            operation: "quick-check"
        )
        guard try statement.step(), statement.columnText(at: 0) == "ok" else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "quick_check")
        }

        let foreignKeyStatement = try connection.prepare(
            "PRAGMA foreign_key_check",
            operation: "foreign-key-check"
        )
        guard try foreignKeyStatement.step() == false else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "foreign_key_check"
            )
        }
    }

    func readStoredBackend(
        from connection: GraphSearchSQLiteConnection
    ) throws -> GraphSearchIndexBackend {
        let statement = try connection.prepare(
            "SELECT backend, schema_version FROM graph_search_manifest WHERE id = 1",
            operation: "read-stored-backend"
        )
        guard try statement.step() else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "manifest")
        }
        guard let rawBackend = statement.columnText(at: 0),
              let backend = GraphSearchIndexBackend(rawValue: rawBackend)
        else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "backend")
        }
        guard statement.columnInt(at: 1) == GraphSearchIndexSchema.currentVersion else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "schema_version")
        }
        return backend
    }

    func verifyRequiredSchema(
        in connection: GraphSearchSQLiteConnection,
        backend: GraphSearchIndexBackend
    ) throws {
        let applicationIDStatement = try connection.prepare(
            "PRAGMA application_id",
            operation: "read-application-id"
        )
        guard try applicationIDStatement.step(),
              applicationIDStatement.columnInt(at: 0) == GraphSearchIndexSchema.sqliteApplicationID
        else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "application_id")
        }

        var requiredObjects: [(type: String, name: String)] = [
            ("table", "graph_search_documents"),
            ("table", "graph_search_ngrams"),
            ("table", "graph_search_manifest"),
            ("table", "graph_search_source_manifests"),
            ("table", "graph_search_source_manifest_entries"),
            ("table", "graph_search_source_manifest_counts"),
            ("index", "graph_search_documents_graph_idx"),
            ("index", "graph_search_documents_source_idx"),
            ("index", "graph_search_documents_owner_idx"),
            ("index", "graph_search_documents_node_idx"),
            ("index", "graph_search_documents_field_idx"),
            ("index", "graph_search_ngrams_graph_idx"),
            ("index", "graph_search_ngrams_global_idx")
        ]
        if backend.usesFTS5 {
            requiredObjects.append(contentsOf: [
                (type: "table", name: "graph_search_fts"),
                (type: "trigger", name: "graph_search_documents_fts_insert"),
                (type: "trigger", name: "graph_search_documents_fts_delete"),
                (type: "trigger", name: "graph_search_documents_fts_update")
            ])
        }

        for object in requiredObjects {
            let statement = try connection.prepare(
                "SELECT 1 FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1",
                operation: "verify-schema-object"
            )
            try statement.bind(object.type, at: 1)
            try statement.bind(object.name, at: 2)
            guard try statement.step() else {
                throw GraphSearchIndexStoreError.invalidStoredValue(column: object.name)
            }
        }
    }

    func readManifest(
        connection: GraphSearchSQLiteConnection,
        backend: GraphSearchIndexBackend
    ) throws -> GraphSearchIndexManifest {
        let metadataStatement = try connection.prepare(
            "SELECT schema_version, created_at, rebuilt_at FROM graph_search_manifest WHERE id = 1",
            operation: "read-manifest-metadata"
        )
        guard try metadataStatement.step() else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "manifest")
        }
        let schemaVersion = metadataStatement.columnInt(at: 0)
        guard schemaVersion == GraphSearchIndexSchema.currentVersion else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "schema_version")
        }
        let createdAtInterval = metadataStatement.columnDouble(at: 1)
        let rebuiltAtInterval = metadataStatement.columnDouble(at: 2)
        guard createdAtInterval.isFinite, rebuiltAtInterval.isFinite else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "manifest_dates")
        }

        let countStatement = try connection.prepare(
            "SELECT COUNT(*), COUNT(DISTINCT graph_id) FROM graph_search_documents",
            operation: "read-manifest-counts"
        )
        guard try countStatement.step() else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "document_count")
        }

        return GraphSearchIndexManifest(
            schemaVersion: schemaVersion,
            backend: backend,
            documentCount: countStatement.columnInt(at: 0),
            graphCount: countStatement.columnInt(at: 1),
            createdAt: Date(timeIntervalSince1970: createdAtInterval),
            rebuiltAt: Date(timeIntervalSince1970: rebuiltAtInterval)
        )
    }

    func resolveAndPrepareDatabaseURL() throws -> URL {
        if let configuredDatabaseURL {
            try createDirectoryIfNeeded(
                at: configuredDatabaseURL.deletingLastPathComponent()
            )
            resolvedDatabaseURL = configuredDatabaseURL
            return configuredDatabaseURL
        }

        let applicationSupportURL: URL
        do {
            applicationSupportURL = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw GraphSearchIndexStoreError.fileSystem(
                operation: "resolve-application-support",
                reason: error.localizedDescription
            )
        }

        let directoryURL = applicationSupportURL
            .appendingPathComponent("BrainMesh", isDirectory: true)
            .appendingPathComponent("Search", isDirectory: true)
            .appendingPathComponent("Index", isDirectory: true)
        try createDirectoryIfNeeded(at: directoryURL)
        try excludeFromBackup(directoryURL)

        let databaseURL = directoryURL.appendingPathComponent(
            "GraphSearchIndex.sqlite",
            isDirectory: false
        )
        resolvedDatabaseURL = databaseURL
        return databaseURL
    }

    func createDirectoryIfNeeded(at directoryURL: URL) throws {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            throw GraphSearchIndexStoreError.fileSystem(
                operation: "create-directory",
                reason: error.localizedDescription
            )
        }
    }

    func applyBackupExclusionIfRequired(to databaseURL: URL) throws {
        guard configuredDatabaseURL == nil else { return }
        try excludeFromBackup(databaseURL.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            try excludeFromBackup(databaseURL)
        }
    }

    func excludeFromBackup(_ url: URL) throws {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try mutableURL.setResourceValues(values)
        } catch {
            throw GraphSearchIndexStoreError.fileSystem(
                operation: "exclude-from-backup",
                reason: error.localizedDescription
            )
        }
    }

    func removeDatabaseFiles(at databaseURL: URL) throws {
        let fileURLs = [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-journal")
        ]

        for fileURL in fileURLs where FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch {
                throw GraphSearchIndexStoreError.fileSystem(
                    operation: "remove-index-file",
                    reason: error.localizedDescription
                )
            }
        }
    }

    func closeForReplacement() throws {
        guard let connection else { return }
        do {
            try connection.closeForReplacement()
            self.connection = nil
            activeBackend = nil
        } catch let error as GraphSearchSQLiteError {
            throw mapSQLiteError(error)
        }
    }

    func requireConnection() throws -> GraphSearchSQLiteConnection {
        guard let connection else {
            throw GraphSearchIndexStoreError.notOpen
        }
        return connection
    }

    func requireBackend() throws -> GraphSearchIndexBackend {
        guard let activeBackend else {
            throw GraphSearchIndexStoreError.notOpen
        }
        return activeBackend
    }

    func withTransaction<T>(
        operation: String,
        body: (isolated GraphSearchIndexStore) throws -> T
    ) throws -> T {
        let connection = try requireConnection()
        do {
            try connection.execute(
                "BEGIN IMMEDIATE TRANSACTION",
                operation: "\(operation)-begin"
            )
        } catch let error as GraphSearchSQLiteError {
            let mappedError = try mapOperationSQLiteError(error)
            throw mappedError
        }

        do {
            let result = try body(self)
            try connection.execute(
                "COMMIT TRANSACTION",
                operation: "\(operation)-commit"
            )
            return result
        } catch {
            var rollbackFailure: GraphSearchSQLiteError?
            do {
                try connection.execute(
                    "ROLLBACK TRANSACTION",
                    operation: "\(operation)-rollback"
                )
            } catch let rollbackError as GraphSearchSQLiteError {
                rollbackFailure = rollbackError
                BMLog.search.error(
                    "Search index rollback failed operation=\(rollbackError.operation, privacy: .public) code=\(rollbackError.code) extended=\(rollbackError.extendedCode)"
                )
            }

            if let rollbackFailure, activeBackend != nil {
                try replaceInvalidIndexAfterOperation(
                    reason: "rollback-failure",
                    sqliteError: rollbackFailure
                )
                if let sqliteError = error as? GraphSearchSQLiteError {
                    throw mapSQLiteError(sqliteError)
                }
                throw error
            }

            if let sqliteError = error as? GraphSearchSQLiteError {
                let mappedError = try mapOperationSQLiteError(sqliteError)
                throw mappedError
            }
            throw error
        }
    }

    func mapOperationSQLiteError(
        _ error: GraphSearchSQLiteError
    ) throws -> GraphSearchIndexStoreError {
        let requiresReplacement = error.isCorruption
            || error.isFTS5Unavailable
            || error.isFTSTokenizerUnavailable
            || error.isSearchSchemaUnavailable
        if requiresReplacement, activeBackend != nil {
            try replaceInvalidIndexAfterOperation(
                reason: error.isCorruption
                    ? "sqlite-corruption"
                    : "backend-or-schema-unavailable",
                sqliteError: error
            )
        }
        return mapSQLiteError(error)
    }

    func recoverIfStoredIndexIsInvalid(
        _ error: GraphSearchIndexStoreError
    ) throws {
        let shouldRecover: Bool
        switch error {
        case .invalidStoredValue,
             .metadataDecoding,
             .invalidDocument,
             .incompatibleDocumentSchemaVersion:
            shouldRecover = true
        default:
            shouldRecover = false
        }

        guard shouldRecover, activeBackend != nil else { return }
        try replaceInvalidIndexAfterOperation(
            reason: "invalid-stored-data",
            sqliteError: nil
        )
    }

    func replaceInvalidIndexAfterOperation(
        reason: String,
        sqliteError: GraphSearchSQLiteError?
    ) throws {
        let startedAt = Self.uptimeNanoseconds()
        let databaseURL = try resolveAndPrepareDatabaseURL()

        if let sqliteError {
            if sqliteError.isCorruption {
                BMLog.search.error(
                    "Search index operation detected corruption operation=\(sqliteError.operation, privacy: .public) code=\(sqliteError.code) extended=\(sqliteError.extendedCode); rebuilding"
                )
            } else {
                BMLog.search.error(
                    "Search index operation detected unrecoverable SQLite state operation=\(sqliteError.operation, privacy: .public) code=\(sqliteError.code) extended=\(sqliteError.extendedCode); rebuilding"
                )
            }
        } else {
            BMLog.search.error(
                "Search index operation detected invalid stored data version=\(GraphSearchIndexSchema.currentVersion); rebuilding"
            )
        }

        try closeForReplacement()
        try removeDatabaseFiles(at: databaseURL)
        let manifest = try openFreshDatabase(at: databaseURL)
        BMLog.search.info(
            "Search index operation recovery complete reason=\(reason, privacy: .public) version=\(manifest.schemaVersion) backend=\(manifest.backend.rawValue, privacy: .public) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }

    func mapSQLiteError(
        _ error: GraphSearchSQLiteError
    ) -> GraphSearchIndexStoreError {
        GraphSearchIndexStoreError.sqlite(
            operation: error.operation,
            code: error.code,
            extendedCode: error.extendedCode
        )
    }

    func openFreshDatabaseAndLog(
        at databaseURL: URL,
        startedAt: UInt64,
        reason: String
    ) throws -> GraphSearchIndexManifest {
        let manifest = try openFreshDatabase(at: databaseURL)
        BMLog.search.info(
            "Search index replacement complete reason=\(reason, privacy: .public) version=\(manifest.schemaVersion) backend=\(manifest.backend.rawValue, privacy: .public) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
        return manifest
    }

    func logOpen(
        manifest: GraphSearchIndexManifest,
        startedAt: UInt64
    ) {
        BMLog.search.info(
            "Search index opened version=\(manifest.schemaVersion) backend=\(manifest.backend.rawValue, privacy: .public) documents=\(manifest.documentCount) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }

    nonisolated static func uptimeNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    nonisolated static func elapsedMilliseconds(since start: UInt64) -> Double {
        let elapsed = DispatchTime.now().uptimeNanoseconds &- start
        return Double(elapsed) / 1_000_000
    }
}
