//
//  GraphSearchIndexStore+Operations.swift
//  BrainMesh
//
//  Transactional document writes, graph isolation, reads and text search.
//

import Foundation
import os

nonisolated struct GraphSearchDocumentQueryResult: Sendable {
    let documents: [GraphSearchDocument]
    let isComplete: Bool
}

extension GraphSearchIndexStore {
    func upsert(_ documents: [GraphSearchDocument]) throws {
        _ = try requireConnection()
        guard documents.isEmpty == false else { return }
        let startedAt = Self.uptimeNanoseconds()

        try validateDocuments(documents)
        let affectedGraphIDs = Array(Set(documents.map(\.graphID))).sorted {
            $0.uuidString < $1.uuidString
        }
        try withTransaction(operation: "upsert-documents") { store in
            let transactionConnection = try store.requireConnection()
            try store.writeDocuments(documents, connection: transactionConnection)
            for graphID in affectedGraphIDs {
                try store.deleteSourceManifest(
                    graphID: graphID,
                    connection: transactionConnection
                )
            }
        }

        BMLog.search.info(
            "Search index upserted documents=\(documents.count) version=\(GraphSearchIndexSchema.currentVersion) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }

    @discardableResult
    func deleteDocuments(
        for sourceReference: GraphSearchSourceReference
    ) throws -> Int {
        _ = try requireConnection()
        let startedAt = Self.uptimeNanoseconds()
        let deletedCount = try withTransaction(
            operation: "delete-source-documents"
        ) { store in
            let transactionConnection = try store.requireConnection()
            try store.cancellationCheck()
            let statement = try transactionConnection.prepare(
                """
                DELETE FROM graph_search_documents
                WHERE graph_id = ? AND source_kind = ? AND source_id = ?
                """,
                operation: "delete-source-documents"
            )
            try statement.bind(sourceReference.graphID.uuidString.lowercased(), at: 1)
            try statement.bind(sourceReference.sourceKind.rawValue, at: 2)
            try statement.bind(sourceReference.sourceID.uuidString.lowercased(), at: 3)
            try statement.stepExpectingDone()
            let deletedDocuments = try transactionConnection.changes()
            try store.deleteSourceManifest(
                graphID: sourceReference.graphID,
                connection: transactionConnection
            )
            try store.cancellationCheck()
            return deletedDocuments
        }

        BMLog.search.info(
            "Search index deleted source documents=\(deletedCount) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
        return deletedCount
    }

    func replaceDocuments(
        for sourceReference: GraphSearchSourceReference,
        with documents: [GraphSearchDocument]
    ) throws {
        _ = try requireConnection()
        let startedAt = Self.uptimeNanoseconds()

        for document in documents where document.sourceReference != sourceReference {
            throw GraphSearchIndexStoreError.invalidSourceReplacement(
                expected: sourceReference,
                actual: document.sourceReference
            )
        }
        try validateDocuments(documents)

        try withTransaction(operation: "replace-source") { store in
            let transactionConnection = try store.requireConnection()
            try store.cancellationCheck()
            let deleteStatement = try transactionConnection.prepare(
                """
                DELETE FROM graph_search_documents
                WHERE graph_id = ? AND source_kind = ? AND source_id = ?
                """,
                operation: "replace-source-delete"
            )
            try deleteStatement.bind(sourceReference.graphID.uuidString.lowercased(), at: 1)
            try deleteStatement.bind(sourceReference.sourceKind.rawValue, at: 2)
            try deleteStatement.bind(sourceReference.sourceID.uuidString.lowercased(), at: 3)
            try deleteStatement.stepExpectingDone()
            try store.cancellationCheck()
            try store.writeDocuments(documents, connection: transactionConnection)
            try store.deleteSourceManifest(
                graphID: sourceReference.graphID,
                connection: transactionConnection
            )
        }

        BMLog.search.info(
            "Search index replaced source documents=\(documents.count) version=\(GraphSearchIndexSchema.currentVersion) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }

    func replaceDocuments(
        in graphID: UUID,
        with documents: [GraphSearchDocument]
    ) throws {
        _ = try requireConnection()
        let startedAt = Self.uptimeNanoseconds()

        for document in documents where document.graphID != graphID {
            throw GraphSearchIndexStoreError.invalidGraphReplacement(
                expected: graphID,
                actual: document.graphID
            )
        }
        try validateDocuments(documents)

        try withTransaction(operation: "replace-graph") { store in
            let transactionConnection = try store.requireConnection()
            try store.cancellationCheck()
            let deleteStatement = try transactionConnection.prepare(
                "DELETE FROM graph_search_documents WHERE graph_id = ?",
                operation: "replace-graph-delete"
            )
            try deleteStatement.bind(graphID.uuidString.lowercased(), at: 1)
            try deleteStatement.stepExpectingDone()
            try store.cancellationCheck()
            try store.writeDocuments(documents, connection: transactionConnection)
            try store.deleteSourceManifest(
                graphID: graphID,
                connection: transactionConnection
            )
        }

        BMLog.search.info(
            "Search index replaced graph documents=\(documents.count) version=\(GraphSearchIndexSchema.currentVersion) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }

    @discardableResult
    func deleteGraph(_ graphID: UUID) throws -> Int {
        _ = try requireConnection()
        let startedAt = Self.uptimeNanoseconds()
        let deletedCount = try withTransaction(
            operation: "delete-graph"
        ) { store in
            let transactionConnection = try store.requireConnection()
            try store.cancellationCheck()
            try store.deleteSourceManifest(
                graphID: graphID,
                connection: transactionConnection
            )
            let statement = try transactionConnection.prepare(
                "DELETE FROM graph_search_documents WHERE graph_id = ?",
                operation: "delete-graph-documents"
            )
            try statement.bind(graphID.uuidString.lowercased(), at: 1)
            try statement.stepExpectingDone()
            let deletedDocuments = try transactionConnection.changes()
            try store.cancellationCheck()
            return deletedDocuments
        }

        BMLog.search.info(
            "Search index deleted graph documents=\(deletedCount) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
        return deletedCount
    }

    func search(
        in graphID: UUID,
        text: String,
        limit: Int
    ) throws -> [GraphSearchIndexHit] {
        try searchDocuments(graphIDs: [graphID], text: text, limit: limit)
    }

    func search(
        in graphIDs: [UUID],
        text: String,
        limit: Int
    ) throws -> [GraphSearchIndexHit] {
        let normalizedGraphIDs = Self.normalizedGraphIDs(graphIDs)
        guard normalizedGraphIDs.isEmpty == false else { return [] }
        guard normalizedGraphIDs.count <= Self.maximumScopedGraphCount else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "search_graph_scope"
            )
        }
        return try searchDocuments(
            graphIDs: normalizedGraphIDs,
            text: text,
            limit: limit
        )
    }

    func searchAcrossGraphs(
        text: String,
        limit: Int
    ) throws -> [GraphSearchIndexHit] {
        try searchDocuments(graphIDs: nil, text: text, limit: limit)
    }

    func matchingDocuments(
        in graphID: UUID,
        text: String,
        documentKinds: Set<GraphSearchDocumentKind>,
        limit: Int
    ) throws -> GraphSearchDocumentQueryResult {
        let connection = try requireConnection()
        let query = BMSearch.fold(text)
        guard query.isEmpty == false else {
            return GraphSearchDocumentQueryResult(
                documents: [],
                isComplete: true
            )
        }

        let safeLimit = max(0, min(limit, Self.maximumSearchLimit))
        guard safeLimit > 0 else {
            return GraphSearchDocumentQueryResult(
                documents: [],
                isComplete: false
            )
        }

        let sortedDocumentKinds = documentKinds.sorted {
            if $0.sortPrecedence != $1.sortPrecedence {
                return $0.sortPrecedence < $1.sortPrecedence
            }
            return $0.rawValue < $1.rawValue
        }
        guard sortedDocumentKinds.isEmpty == false else {
            return GraphSearchDocumentQueryResult(
                documents: [],
                isComplete: true
            )
        }

        let queryNgrams = Self.queryNgrams(for: query)
        guard queryNgrams.isEmpty == false else {
            return GraphSearchDocumentQueryResult(
                documents: [],
                isComplete: true
            )
        }

        let startedAt = Self.uptimeNanoseconds()
        return try mapSQLiteErrors {
            try cancellationCheck()

            let documentKindPlaceholders = Array(
                repeating: "?",
                count: sortedDocumentKinds.count
            ).joined(separator: ", ")
            let ngramPlaceholders = Array(
                repeating: "?",
                count: queryNgrams.count
            ).joined(separator: ", ")
            let statement = try connection.prepare(
                """
                SELECT \(Self.documentSelectColumns)
                FROM graph_search_documents
                WHERE graph_id = ?
                  AND document_kind IN (\(documentKindPlaceholders))
                  AND instr(normalized_search_text, ?) > 0
                  AND document_id IN (
                      SELECT document_id
                      FROM graph_search_ngrams
                      WHERE graph_id = ?
                        AND gram IN (\(ngramPlaceholders))
                      GROUP BY document_id
                      HAVING COUNT(DISTINCT gram) = ?
                  )
                ORDER BY document_id ASC
                LIMIT ?
                """,
                operation: "search-filtered-graph-documents"
            )

            var bindingIndex: Int32 = 1
            try statement.bind(
                graphID.uuidString.lowercased(),
                at: bindingIndex
            )
            bindingIndex += 1
            for documentKind in sortedDocumentKinds {
                try statement.bind(documentKind.rawValue, at: bindingIndex)
                bindingIndex += 1
            }
            try statement.bind(query, at: bindingIndex)
            bindingIndex += 1
            try statement.bind(
                graphID.uuidString.lowercased(),
                at: bindingIndex
            )
            bindingIndex += 1
            for ngram in queryNgrams {
                try statement.bind(ngram, at: bindingIndex)
                bindingIndex += 1
            }
            try statement.bind(queryNgrams.count, at: bindingIndex)
            bindingIndex += 1
            try statement.bind(safeLimit + 1, at: bindingIndex)

            let fetchedDocuments = try decodeAllDocuments(from: statement)
            try cancellationCheck()
            let isComplete = fetchedDocuments.count <= safeLimit
            let documents = isComplete
                ? fetchedDocuments
                : Array(fetchedDocuments.prefix(safeLimit))

            BMLog.search.info(
                "Search index filtered query documents=\(documents.count) complete=\(isComplete) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
            )
            return GraphSearchDocumentQueryResult(
                documents: documents,
                isComplete: isComplete
            )
        }
    }

    func document(id documentID: String) throws -> GraphSearchDocument? {
        let connection = try requireConnection()
        return try mapSQLiteErrors {
            let statement = try connection.prepare(
                """
                SELECT \(Self.documentSelectColumns)
                FROM graph_search_documents
                WHERE document_id = ?
                LIMIT 1
                """,
                operation: "read-document"
            )
            try statement.bind(documentID, at: 1)
            guard try statement.step() else { return nil }
            return try decodeDocument(from: statement)
        }
    }

    func documents(in graphID: UUID) throws -> [GraphSearchDocument] {
        let connection = try requireConnection()
        return try mapSQLiteErrors {
            let statement = try connection.prepare(
                """
                SELECT \(Self.documentSelectColumns)
                FROM graph_search_documents
                WHERE graph_id = ?
                ORDER BY document_id ASC
                """,
                operation: "read-graph-documents"
            )
            try statement.bind(graphID.uuidString.lowercased(), at: 1)
            return try decodeAllDocuments(from: statement)
        }
    }

    func documents(
        for sourceReference: GraphSearchSourceReference
    ) throws -> [GraphSearchDocument] {
        let connection = try requireConnection()
        return try mapSQLiteErrors {
            let statement = try connection.prepare(
                """
                SELECT \(Self.documentSelectColumns)
                FROM graph_search_documents
                WHERE graph_id = ? AND source_kind = ? AND source_id = ?
                ORDER BY document_id ASC
                """,
                operation: "read-source-documents"
            )
            try statement.bind(sourceReference.graphID.uuidString.lowercased(), at: 1)
            try statement.bind(sourceReference.sourceKind.rawValue, at: 2)
            try statement.bind(sourceReference.sourceID.uuidString.lowercased(), at: 3)
            return try decodeAllDocuments(from: statement)
        }
    }

    func sourceReferences(
        in graphID: UUID
    ) throws -> [GraphSearchSourceReference] {
        let connection = try requireConnection()
        return try mapSQLiteErrors {
            let statement = try connection.prepare(
                """
                SELECT DISTINCT source_kind, source_id
                FROM graph_search_documents
                WHERE graph_id = ?
                ORDER BY source_kind ASC, source_id ASC
                """,
                operation: "read-source-references"
            )
            try statement.bind(graphID.uuidString.lowercased(), at: 1)

            var references: [GraphSearchSourceReference] = []
            while try statement.step() {
                try cancellationCheck()
                guard let sourceKindRaw = statement.columnText(at: 0),
                      let sourceKind = GraphSearchSourceKind(rawValue: sourceKindRaw)
                else {
                    throw GraphSearchIndexStoreError.invalidStoredValue(
                        column: "source_kind"
                    )
                }
                guard let sourceIDRaw = statement.columnText(at: 1),
                      let sourceID = UUID(uuidString: sourceIDRaw)
                else {
                    throw GraphSearchIndexStoreError.invalidStoredValue(
                        column: "source_id"
                    )
                }
                references.append(
                    GraphSearchSourceReference(
                        graphID: graphID,
                        sourceKind: sourceKind,
                        sourceID: sourceID
                    )
                )
            }
            return references
        }
    }

    func detailValueSourceReferences(
        in graphID: UUID,
        fieldID: UUID
    ) throws -> [GraphSearchSourceReference] {
        let connection = try requireConnection()
        return try mapSQLiteErrors {
            let statement = try connection.prepare(
                """
                SELECT DISTINCT source_id
                FROM graph_search_documents
                WHERE graph_id = ? AND source_kind = ? AND field_id = ?
                ORDER BY source_id ASC
                """,
                operation: "read-detail-value-source-references"
            )
            try statement.bind(graphID.uuidString.lowercased(), at: 1)
            try statement.bind(GraphSearchSourceKind.detailValue.rawValue, at: 2)
            try statement.bind(fieldID.uuidString.lowercased(), at: 3)

            var references: [GraphSearchSourceReference] = []
            while try statement.step() {
                try cancellationCheck()
                guard let sourceIDRaw = statement.columnText(at: 0),
                      let sourceID = UUID(uuidString: sourceIDRaw)
                else {
                    throw GraphSearchIndexStoreError.invalidStoredValue(
                        column: "source_id"
                    )
                }
                references.append(
                    GraphSearchSourceReference(
                        graphID: graphID,
                        sourceKind: .detailValue,
                        sourceID: sourceID
                    )
                )
            }
            return references
        }
    }

    func documentCount(in graphID: UUID? = nil) throws -> Int {
        let connection = try requireConnection()
        return try mapSQLiteErrors {
            let statement: GraphSearchSQLiteStatement
            if let graphID {
                statement = try connection.prepare(
                    "SELECT COUNT(*) FROM graph_search_documents WHERE graph_id = ?",
                    operation: "count-graph-documents"
                )
                try statement.bind(graphID.uuidString.lowercased(), at: 1)
            } else {
                statement = try connection.prepare(
                    "SELECT COUNT(*) FROM graph_search_documents",
                    operation: "count-all-documents"
                )
            }
            guard try statement.step() else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "document_count"
                )
            }
            return statement.columnInt(at: 0)
        }
    }

    func manifest() throws -> GraphSearchIndexManifest {
        let connection = try requireConnection()
        let backend = try requireBackend()
        return try mapSQLiteErrors {
            try readManifest(connection: connection, backend: backend)
        }
    }
}

extension GraphSearchIndexStore {
    func validateDocuments(_ documents: [GraphSearchDocument]) throws {
        for (index, document) in documents.enumerated() {
            if index.isMultiple(of: batchSize) {
                try cancellationCheck()
            }
            try document.validateForStorage()
        }
        try cancellationCheck()
    }

    func writeDocuments(
        _ documents: [GraphSearchDocument],
        connection: GraphSearchSQLiteConnection
    ) throws {
        guard documents.isEmpty == false else {
            try cancellationCheck()
            return
        }

        let upsertStatement = try connection.prepare(
            """
            INSERT INTO graph_search_documents(
                document_id,
                graph_id,
                document_kind,
                source_kind,
                source_id,
                owner_kind_raw,
                owner_id,
                node_kind_raw,
                node_id,
                field_id,
                title,
                subtitle,
                normalized_search_text,
                ranking_boost,
                ranking_json,
                presentation_json,
                navigation_json,
                evidence_json,
                attachment_json,
                content_hash,
                index_schema_version
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(document_id) DO UPDATE SET
                graph_id = excluded.graph_id,
                document_kind = excluded.document_kind,
                source_kind = excluded.source_kind,
                source_id = excluded.source_id,
                owner_kind_raw = excluded.owner_kind_raw,
                owner_id = excluded.owner_id,
                node_kind_raw = excluded.node_kind_raw,
                node_id = excluded.node_id,
                field_id = excluded.field_id,
                title = excluded.title,
                subtitle = excluded.subtitle,
                normalized_search_text = excluded.normalized_search_text,
                ranking_boost = excluded.ranking_boost,
                ranking_json = excluded.ranking_json,
                presentation_json = excluded.presentation_json,
                navigation_json = excluded.navigation_json,
                evidence_json = excluded.evidence_json,
                attachment_json = excluded.attachment_json,
                content_hash = excluded.content_hash,
                index_schema_version = excluded.index_schema_version
            """,
            operation: "upsert-document"
        )
        let deleteNgramsStatement = try connection.prepare(
            "DELETE FROM graph_search_ngrams WHERE document_id = ?",
            operation: "delete-document-ngrams"
        )
        let insertNgramStatement = try connection.prepare(
            """
            INSERT INTO graph_search_ngrams(document_id, graph_id, gram)
            VALUES (?, ?, ?)
            """,
            operation: "insert-document-ngram"
        )

        var batchStart = 0
        while batchStart < documents.count {
            try cancellationCheck()
            let batchEnd = min(documents.count, batchStart + batchSize)

            for documentIndex in batchStart..<batchEnd {
                let document = documents[documentIndex]
                try bindDocument(document, to: upsertStatement)
                try upsertStatement.stepExpectingDone()
                try upsertStatement.reset()

                try deleteNgramsStatement.bind(document.documentID, at: 1)
                try deleteNgramsStatement.stepExpectingDone()
                try deleteNgramsStatement.reset()

                let grams = Self.indexedNgrams(for: document.normalizedSearchText)
                    .sorted()
                for (gramIndex, gram) in grams.enumerated() {
                    if gramIndex.isMultiple(of: 256) {
                        try cancellationCheck()
                    }
                    try insertNgramStatement.bind(document.documentID, at: 1)
                    try insertNgramStatement.bind(
                        document.graphID.uuidString.lowercased(),
                        at: 2
                    )
                    try insertNgramStatement.bind(gram, at: 3)
                    try insertNgramStatement.stepExpectingDone()
                    try insertNgramStatement.reset()
                }
            }

            try cancellationCheck()
            batchStart = batchEnd
        }
        try cancellationCheck()
    }

    func bindDocument(
        _ document: GraphSearchDocument,
        to statement: GraphSearchSQLiteStatement
    ) throws {
        let rankingJSON = try encodeMetadata(
            document.ranking,
            type: "ranking"
        )
        let presentationJSON = try encodeMetadata(
            document.presentation,
            type: "presentation"
        )
        let navigationJSON = try encodeMetadata(
            document.navigation,
            type: "navigation"
        )
        let evidenceJSON = try encodeMetadata(
            document.evidence,
            type: "evidence"
        )
        let attachmentJSON: String?
        if let attachmentMetadata = document.attachmentMetadata {
            attachmentJSON = try encodeMetadata(
                attachmentMetadata,
                type: "attachment"
            )
        } else {
            attachmentJSON = nil
        }

        try statement.bind(document.documentID, at: 1)
        try statement.bind(document.graphID.uuidString.lowercased(), at: 2)
        try statement.bind(document.documentKind.rawValue, at: 3)
        try statement.bind(document.sourceKind.rawValue, at: 4)
        try statement.bind(document.sourceID.uuidString.lowercased(), at: 5)
        try statement.bind(document.ownerKindRaw, at: 6)
        try statement.bind(document.ownerID?.uuidString.lowercased(), at: 7)
        try statement.bind(document.nodeKindRaw, at: 8)
        try statement.bind(document.nodeID?.uuidString.lowercased(), at: 9)
        try statement.bind(document.fieldID?.uuidString.lowercased(), at: 10)
        try statement.bind(document.title, at: 11)
        try statement.bind(document.subtitle, at: 12)
        try statement.bind(document.normalizedSearchText, at: 13)
        try statement.bind(document.ranking.boost, at: 14)
        try statement.bind(rankingJSON, at: 15)
        try statement.bind(presentationJSON, at: 16)
        try statement.bind(navigationJSON, at: 17)
        try statement.bind(evidenceJSON, at: 18)
        try statement.bind(attachmentJSON, at: 19)
        try statement.bind(document.contentHash, at: 20)
        try statement.bind(document.indexSchemaVersion, at: 21)
    }

    func searchDocuments(
        graphIDs: [UUID]?,
        text: String,
        limit: Int
    ) throws -> [GraphSearchIndexHit] {
        let connection = try requireConnection()
        let backend = try requireBackend()
        let query = BMSearch.fold(text)
        guard query.isEmpty == false else { return [] }

        let safeLimit = max(0, min(limit, Self.maximumSearchLimit))
        guard safeLimit > 0 else { return [] }
        let startedAt = Self.uptimeNanoseconds()
        let candidateLimit = Self.internalCandidateLimit(for: safeLimit)
        let graphIDSet = graphIDs.map(Set.init)

        return try mapSQLiteErrors {
            try cancellationCheck()
            var candidateIDs = try candidateDocumentIDsUsingNgrams(
                connection: connection,
                graphIDs: graphIDs,
                query: query,
                limit: candidateLimit
            )

            if backend.usesFTS5 {
                let ftsIDs = try candidateDocumentIDsUsingFTS5(
                    connection: connection,
                    backend: backend,
                    graphIDs: graphIDs,
                    query: query,
                    limit: candidateLimit
                )
                candidateIDs.formUnion(ftsIDs)
            }
            if candidateIDs.count > candidateLimit {
                candidateIDs = Set(candidateIDs.sorted().prefix(candidateLimit))
            }

            let candidates = try fetchDocuments(
                withIDs: candidateIDs,
                connection: connection
            )
            var hits: [GraphSearchIndexHit] = []
            hits.reserveCapacity(candidates.count)
            for (index, document) in candidates.enumerated() {
                if index.isMultiple(of: batchSize) {
                    try cancellationCheck()
                }
                guard document.normalizedSearchText.contains(query) else {
                    continue
                }
                if let graphIDSet,
                   graphIDSet.contains(document.graphID) == false {
                    continue
                }
                hits.append(
                    GraphSearchIndexHit(
                        document: document,
                        score: Self.searchScore(for: document, query: query)
                    )
                )
            }

            hits.sort(by: Self.hitSort)
            try cancellationCheck()
            let result = Array(hits.prefix(safeLimit))
            BMLog.search.info(
                "Search index query backend=\(backend.rawValue, privacy: .public) candidates=\(candidateIDs.count) results=\(result.count) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
            )
            return result
        }
    }

    func candidateDocumentIDsUsingFTS5(
        connection: GraphSearchSQLiteConnection,
        backend: GraphSearchIndexBackend,
        graphIDs: [UUID]?,
        query: String,
        limit: Int
    ) throws -> Set<String> {
        let matchExpression: String?
        switch backend {
        case .fts5Trigram:
            guard query.count >= 3 else { return [] }
            matchExpression = Self.quotedFTS5Phrase(query)
        case .fts5Unicode:
            matchExpression = Self.unicodeFTS5Expression(query)
        case .indexedFallback:
            matchExpression = nil
        }
        guard let matchExpression, matchExpression.isEmpty == false else {
            return []
        }

        let graphClause = Self.graphScopeClause(
            column: "d.graph_id",
            graphIDs: graphIDs
        )
        let statement = try connection.prepare(
            """
            SELECT d.document_id
            FROM graph_search_fts
            JOIN graph_search_documents AS d
              ON d.rowid = graph_search_fts.rowid
            WHERE graph_search_fts MATCH ?
              AND instr(d.normalized_search_text, ?) > 0
              \(graphClause.sql)
            ORDER BY d.document_id ASC
            LIMIT ?
            """,
            operation: graphIDs == nil ? "search-fts-global" : "search-fts-scoped"
        )
        var bindingIndex: Int32 = 1
        try statement.bind(matchExpression, at: bindingIndex)
        bindingIndex += 1
        try statement.bind(query, at: bindingIndex)
        bindingIndex += 1
        bindingIndex = try Self.bindGraphScope(
            graphClause.values,
            to: statement,
            startingAt: bindingIndex
        )
        try statement.bind(max(1, limit), at: bindingIndex)

        var documentIDs = Set<String>()
        while try statement.step() {
            try cancellationCheck()
            guard let documentID = statement.columnText(at: 0) else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "document_id"
                )
            }
            documentIDs.insert(documentID)
        }
        return documentIDs
    }

    func candidateDocumentIDsUsingNgrams(
        connection: GraphSearchSQLiteConnection,
        graphIDs: [UUID]?,
        query: String,
        limit: Int
    ) throws -> Set<String> {
        let grams = Self.queryNgrams(for: query)
        guard grams.isEmpty == false else { return [] }

        var intersection: Set<String>?
        for gram in grams {
            try cancellationCheck()
            let graphClause = Self.graphScopeClause(
                column: "graph_id",
                graphIDs: graphIDs
            )
            let statement = try connection.prepare(
                """
                SELECT document_id
                FROM graph_search_ngrams
                WHERE gram = ?
                  \(graphClause.sql)
                ORDER BY document_id ASC
                LIMIT ?
                """,
                operation: graphIDs == nil ? "search-ngram-global" : "search-ngram-scoped"
            )
            var bindingIndex: Int32 = 1
            try statement.bind(gram, at: bindingIndex)
            bindingIndex += 1
            bindingIndex = try Self.bindGraphScope(
                graphClause.values,
                to: statement,
                startingAt: bindingIndex
            )
            try statement.bind(max(1, limit), at: bindingIndex)

            var matches = Set<String>()
            while try statement.step() {
                if matches.count.isMultiple(of: batchSize) {
                    try cancellationCheck()
                }
                guard let documentID = statement.columnText(at: 0) else {
                    throw GraphSearchIndexStoreError.invalidStoredValue(
                        column: "document_id"
                    )
                }
                matches.insert(documentID)
            }

            if let currentIntersection = intersection {
                intersection = currentIntersection.intersection(matches)
            } else {
                intersection = matches
            }

            if intersection?.isEmpty == true {
                return []
            }
        }
        return intersection ?? []
    }

    func fetchDocuments(
        withIDs documentIDs: Set<String>,
        connection: GraphSearchSQLiteConnection
    ) throws -> [GraphSearchDocument] {
        guard documentIDs.isEmpty == false else { return [] }
        try cancellationCheck()
        let sortedIDs = documentIDs.sorted()
        let placeholders = Array(repeating: "?", count: sortedIDs.count)
            .joined(separator: ", ")
        let statement = try connection.prepare(
            """
            SELECT \(Self.documentSelectColumns)
            FROM graph_search_documents
            WHERE document_id IN (\(placeholders))
            ORDER BY document_id ASC
            """,
            operation: "fetch-search-documents"
        )
        for (offset, documentID) in sortedIDs.enumerated() {
            try statement.bind(documentID, at: Int32(offset + 1))
        }
        let documents = try decodeAllDocuments(from: statement)
        try cancellationCheck()
        return documents
    }

    func decodeAllDocuments(
        from statement: GraphSearchSQLiteStatement
    ) throws -> [GraphSearchDocument] {
        var documents: [GraphSearchDocument] = []
        while try statement.step() {
            if documents.count.isMultiple(of: batchSize) {
                try cancellationCheck()
            }
            documents.append(try decodeDocument(from: statement))
        }
        return documents
    }

    func decodeDocument(
        from statement: GraphSearchSQLiteStatement
    ) throws -> GraphSearchDocument {
        guard let storedDocumentID = statement.columnText(at: 0) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "document_id")
        }
        let graphID = try Self.requiredUUID(
            statement.columnText(at: 1),
            column: "graph_id"
        )
        guard let documentKindRaw = statement.columnText(at: 2),
              let documentKind = GraphSearchDocumentKind(rawValue: documentKindRaw)
        else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "document_kind")
        }
        guard let sourceKindRaw = statement.columnText(at: 3),
              let sourceKind = GraphSearchSourceKind(rawValue: sourceKindRaw)
        else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "source_kind")
        }
        let sourceID = try Self.requiredUUID(
            statement.columnText(at: 4),
            column: "source_id"
        )

        let ownerKindRaw = statement.columnNullableInt(at: 5)
        let ownerKind: NodeKind?
        if let ownerKindRaw {
            guard let decodedOwnerKind = NodeKind(rawValue: ownerKindRaw) else {
                throw GraphSearchIndexStoreError.invalidStoredValue(column: "owner_kind_raw")
            }
            ownerKind = decodedOwnerKind
        } else {
            ownerKind = nil
        }
        let ownerID = try Self.optionalUUID(
            statement.columnText(at: 6),
            column: "owner_id"
        )

        let nodeKindRaw = statement.columnNullableInt(at: 7)
        let nodeKind: NodeKind?
        if let nodeKindRaw {
            guard let decodedNodeKind = NodeKind(rawValue: nodeKindRaw) else {
                throw GraphSearchIndexStoreError.invalidStoredValue(column: "node_kind_raw")
            }
            nodeKind = decodedNodeKind
        } else {
            nodeKind = nil
        }
        let nodeID = try Self.optionalUUID(
            statement.columnText(at: 8),
            column: "node_id"
        )
        let fieldID = try Self.optionalUUID(
            statement.columnText(at: 9),
            column: "field_id"
        )

        guard let title = statement.columnText(at: 10) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "title")
        }
        guard let subtitle = statement.columnText(at: 11) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "subtitle")
        }
        guard let normalizedSearchText = statement.columnText(at: 12) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "normalized_search_text"
            )
        }
        let storedRankingBoost = statement.columnInt(at: 13)
        let ranking: GraphSearchRankingMetadata = try decodeMetadata(
            statement.columnText(at: 14),
            type: "ranking"
        )
        guard ranking.boost == storedRankingBoost else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "ranking_boost")
        }
        let presentation: GraphSearchPresentationMetadata = try decodeMetadata(
            statement.columnText(at: 15),
            type: "presentation"
        )
        let navigation: GraphSearchNavigationMetadata = try decodeMetadata(
            statement.columnText(at: 16),
            type: "navigation"
        )
        let evidence: GraphSearchEvidenceMetadata = try decodeMetadata(
            statement.columnText(at: 17),
            type: "evidence"
        )
        let attachmentMetadata: GraphSearchAttachmentMetadata?
        if let attachmentJSON = statement.columnText(at: 18) {
            attachmentMetadata = try decodeMetadata(
                attachmentJSON,
                type: "attachment"
            )
        } else {
            attachmentMetadata = nil
        }
        guard let contentHash = statement.columnText(at: 19) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "content_hash")
        }
        let indexSchemaVersion = statement.columnInt(at: 20)

        let document = GraphSearchDocument(
            graphID: graphID,
            documentKind: documentKind,
            sourceKind: sourceKind,
            sourceID: sourceID,
            ownerKind: ownerKind,
            ownerID: ownerID,
            nodeKind: nodeKind,
            nodeID: nodeID,
            fieldID: fieldID,
            title: title,
            subtitle: subtitle,
            searchableText: normalizedSearchText,
            ranking: ranking,
            presentation: presentation,
            navigation: navigation,
            evidence: evidence,
            attachmentMetadata: attachmentMetadata,
            contentHash: contentHash,
            indexSchemaVersion: indexSchemaVersion
        )
        guard document.documentID == storedDocumentID else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: "document_id")
        }
        guard document.normalizedSearchText == normalizedSearchText else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "normalized_search_text"
            )
        }
        try document.validateForStorage()
        return document
    }

    func encodeMetadata<T: Encodable>(
        _ value: T,
        type: String
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(value)
            guard let string = String(data: data, encoding: .utf8) else {
                throw GraphSearchIndexStoreError.metadataEncoding(type: type)
            }
            return string
        } catch let error as GraphSearchIndexStoreError {
            throw error
        } catch {
            throw GraphSearchIndexStoreError.metadataEncoding(type: type)
        }
    }

    func decodeMetadata<T: Decodable>(
        _ string: String?,
        type: String
    ) throws -> T {
        guard let string else {
            throw GraphSearchIndexStoreError.metadataDecoding(type: type)
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(string.utf8))
        } catch {
            throw GraphSearchIndexStoreError.metadataDecoding(type: type)
        }
    }

    func mapSQLiteErrors<T>(
        _ body: () throws -> T
    ) throws -> T {
        do {
            return try body()
        } catch let error as GraphSearchSQLiteError {
            let mappedError = try mapOperationSQLiteError(error)
            throw mappedError
        } catch let error as GraphSearchIndexStoreError {
            try recoverIfStoredIndexIsInvalid(error)
            throw error
        }
    }
}

extension GraphSearchIndexStore {
    nonisolated static let documentSelectColumns = """
        document_id,
        graph_id,
        document_kind,
        source_kind,
        source_id,
        owner_kind_raw,
        owner_id,
        node_kind_raw,
        node_id,
        field_id,
        title,
        subtitle,
        normalized_search_text,
        ranking_boost,
        ranking_json,
        presentation_json,
        navigation_json,
        evidence_json,
        attachment_json,
        content_hash,
        index_schema_version
        """

    nonisolated static func internalCandidateLimit(for resultLimit: Int) -> Int {
        let multiplied = max(0, resultLimit).multipliedReportingOverflow(
            by: searchCandidateMultiplier
        )
        let expanded = multiplied.overflow ? Int.max : multiplied.partialValue
        return min(
            maximumSearchLimit,
            max(minimumSearchCandidateLimit, expanded)
        )
    }

    nonisolated static func normalizedGraphIDs(_ graphIDs: [UUID]) -> [UUID] {
        Array(Set(graphIDs)).sorted { lhs, rhs in
            lhs.uuidString < rhs.uuidString
        }
    }

    nonisolated static func graphScopeClause(
        column: String,
        graphIDs: [UUID]?
    ) -> (sql: String, values: [UUID]) {
        guard let graphIDs else { return ("", []) }
        let normalized = normalizedGraphIDs(graphIDs)
        guard normalized.isEmpty == false else {
            return ("AND 0 = 1", [])
        }
        let placeholders = Array(repeating: "?", count: normalized.count)
            .joined(separator: ", ")
        return ("AND \(column) IN (\(placeholders))", normalized)
    }

    static func bindGraphScope(
        _ graphIDs: [UUID],
        to statement: GraphSearchSQLiteStatement,
        startingAt startIndex: Int32
    ) throws -> Int32 {
        var bindingIndex = startIndex
        for graphID in graphIDs {
            try statement.bind(
                graphID.uuidString.lowercased(),
                at: bindingIndex
            )
            bindingIndex += 1
        }
        return bindingIndex
    }

    nonisolated static func indexedNgrams(for text: String) -> Set<String> {
        let characters = Array(text)
        guard characters.isEmpty == false else { return [] }

        var grams = Set<String>()
        grams.reserveCapacity(min(characters.count * 3, 8_192))
        for length in 1...3 where characters.count >= length {
            for start in 0...(characters.count - length) {
                grams.insert(String(characters[start..<(start + length)]))
            }
        }
        return grams
    }

    nonisolated static func queryNgrams(for query: String) -> [String] {
        let characters = Array(query)
        guard characters.isEmpty == false else { return [] }
        if characters.count <= 2 {
            return [query]
        }

        var grams = Set<String>()
        for start in 0...(characters.count - 3) {
            grams.insert(String(characters[start..<(start + 3)]))
            if grams.count == 32 {
                break
            }
        }
        return grams.sorted()
    }

    nonisolated static func quotedFTS5Phrase(_ query: String) -> String {
        let escaped = query.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    nonisolated static func unicodeFTS5Expression(_ query: String) -> String? {
        let tokens = searchTokens(in: query)
        guard tokens.isEmpty == false else { return nil }
        return tokens.map { token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\"*"
        }.joined(separator: " AND ")
    }

    nonisolated static func searchTokens(in text: String) -> [String] {
        var tokens: [String] = []
        var current = ""

        for character in text {
            if character.isLetter || character.isNumber {
                current.append(character)
            } else if current.isEmpty == false {
                tokens.append(current)
                current = ""
            }
        }
        if current.isEmpty == false {
            tokens.append(current)
        }
        return tokens
    }

    nonisolated static func searchScore(
        for document: GraphSearchDocument,
        query: String
    ) -> Int {
        var bestBaseScore: Int?
        for field in document.ranking.fields where field.foldedText.isEmpty == false {
            let quality: Int?
            if field.foldedText == query {
                quality = 0
            } else if field.foldedText.hasPrefix(query) {
                quality = 1
            } else if field.foldedText.contains(query) {
                quality = 2
            } else {
                quality = nil
            }
            guard let quality else { continue }
            let baseScore = field.priority.rawValue * 3 + quality
            if let currentBestBaseScore = bestBaseScore {
                bestBaseScore = min(currentBestBaseScore, baseScore)
            } else {
                bestBaseScore = baseScore
            }
        }

        let normalizedBase = bestBaseScore ?? 100
        let baseScore = normalizedBase * 10_000
        let (score, overflow) = baseScore.subtractingReportingOverflow(
            document.ranking.boost
        )
        if overflow {
            return document.ranking.boost > 0 ? Int.min : Int.max
        }
        return score
    }

    nonisolated static func hitSort(
        _ lhs: GraphSearchIndexHit,
        _ rhs: GraphSearchIndexHit
    ) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score < rhs.score
        }
        if lhs.document.documentKind.sortPrecedence != rhs.document.documentKind.sortPrecedence {
            return lhs.document.documentKind.sortPrecedence
                < rhs.document.documentKind.sortPrecedence
        }
        let lhsTitle = BMSearch.fold(lhs.document.title)
        let rhsTitle = BMSearch.fold(rhs.document.title)
        if lhsTitle != rhsTitle {
            return lhsTitle < rhsTitle
        }
        let lhsSubtitle = BMSearch.fold(lhs.document.subtitle)
        let rhsSubtitle = BMSearch.fold(rhs.document.subtitle)
        if lhsSubtitle != rhsSubtitle {
            return lhsSubtitle < rhsSubtitle
        }
        return lhs.document.documentID < rhs.document.documentID
    }

    nonisolated static func requiredUUID(
        _ rawValue: String?,
        column: String
    ) throws -> UUID {
        guard let rawValue, let uuid = UUID(uuidString: rawValue) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: column)
        }
        return uuid
    }

    nonisolated static func optionalUUID(
        _ rawValue: String?,
        column: String
    ) throws -> UUID? {
        guard let rawValue else { return nil }
        guard let uuid = UUID(uuidString: rawValue) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(column: column)
        }
        return uuid
    }
}
