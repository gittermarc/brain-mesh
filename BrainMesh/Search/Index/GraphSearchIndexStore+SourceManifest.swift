//
//  GraphSearchIndexStore+SourceManifest.swift
//  BrainMesh
//
//  Transactional persistence and validation of graph-scoped source manifests.
//

import Foundation
import os

nonisolated struct GraphSearchIndexSourceReplacement: Sendable {
    let sourceReference: GraphSearchSourceReference
    let documents: [GraphSearchDocument]
    let manifestEntry: GraphSearchSourceManifestEntry

    init(
        sourceReference: GraphSearchSourceReference,
        documents: [GraphSearchDocument],
        manifestEntry: GraphSearchSourceManifestEntry
    ) {
        self.sourceReference = sourceReference
        self.documents = documents.sorted { $0.documentID < $1.documentID }
        self.manifestEntry = manifestEntry
    }
}

extension GraphSearchIndexStore {
    func sourceManifest(in graphID: UUID) throws -> GraphSearchSourceManifest? {
        let connection = try requireConnection()
        return try mapSQLiteErrors {
            try readSourceManifest(
                graphID: graphID,
                connection: connection,
                validateDocuments: true
            )
        }
    }

    func sourceManifestEntry(
        for reference: GraphSearchSourceReference
    ) throws -> GraphSearchSourceManifestEntry? {
        let connection = try requireConnection()
        return try mapSQLiteErrors {
            let statement = try connection.prepare(
                """
                SELECT content_hash, document_count
                FROM graph_search_source_manifest_entries
                WHERE graph_id = ? AND source_kind = ? AND source_id = ?
                LIMIT 1
                """,
                operation: "read-source-manifest-entry"
            )
            try statement.bind(reference.graphID.uuidString.lowercased(), at: 1)
            try statement.bind(reference.sourceKind.rawValue, at: 2)
            try statement.bind(reference.sourceID.uuidString.lowercased(), at: 3)
            guard try statement.step() else { return nil }
            guard let contentHash = statement.columnText(at: 0) else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "source_manifest_content_hash"
                )
            }
            let documentCount = statement.columnInt(at: 1)
            guard documentCount >= 0 else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "source_manifest_document_count"
                )
            }
            return GraphSearchSourceManifestEntry(
                graphID: reference.graphID,
                sourceKind: reference.sourceKind,
                sourceID: reference.sourceID,
                contentHash: contentHash,
                documentCount: documentCount
            )
        }
    }

    func replaceDocuments(
        in graphID: UUID,
        with documents: [GraphSearchDocument],
        sourceManifest: GraphSearchSourceManifest
    ) throws {
        _ = try requireConnection()
        let startedAt = Self.uptimeNanoseconds()

        guard sourceManifest.graphID == graphID else {
            throw GraphSearchIndexStoreError.invalidGraphReplacement(
                expected: graphID,
                actual: sourceManifest.graphID
            )
        }
        try sourceManifest.validateStructure()
        guard sourceManifest.isCompatible else {
            throw GraphSearchIndexStoreError.incompatibleSourceManifest(
                formatVersion: sourceManifest.formatVersion,
                indexSchemaVersion: sourceManifest.indexSchemaVersion
            )
        }
        guard sourceManifest.documentCount == documents.count else {
            throw GraphSearchIndexStoreError.invalidSourceManifest(
                reason: "The manifest document count does not match the replacement payload."
            )
        }
        for document in documents where document.graphID != graphID {
            throw GraphSearchIndexStoreError.invalidGraphReplacement(
                expected: graphID,
                actual: document.graphID
            )
        }
        try validateDocuments(documents)
        try validateIncomingDocuments(
            documents,
            against: sourceManifest
        )

        try withTransaction(operation: "replace-graph-with-source-manifest") { store in
            let transactionConnection = try store.requireConnection()
            try store.deleteGraphDocuments(
                graphID: graphID,
                connection: transactionConnection,
                operation: "replace-manifest-graph-delete"
            )
            try store.cancellationCheck()
            try store.writeDocuments(documents, connection: transactionConnection)
            try store.writeSourceManifest(
                sourceManifest,
                connection: transactionConnection
            )
            try store.deleteLifecycleRows(
                graphID: graphID,
                connection: transactionConnection
            )
        }

        BMLog.search.info(
            "Search index replaced graph with source manifest documents=\(documents.count, privacy: .public) sources=\(sourceManifest.sourceCount, privacy: .public) version=\(GraphSearchIndexSchema.currentVersion, privacy: .public) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }

    func replaceDocuments(
        for sourceReference: GraphSearchSourceReference,
        with documents: [GraphSearchDocument],
        manifestEntry: GraphSearchSourceManifestEntry?
    ) throws {
        let connection = try requireConnection()
        let startedAt = Self.uptimeNanoseconds()

        for document in documents where document.sourceReference != sourceReference {
            throw GraphSearchIndexStoreError.invalidSourceReplacement(
                expected: sourceReference,
                actual: document.sourceReference
            )
        }
        if let manifestEntry,
           manifestEntry.sourceReference != sourceReference {
            throw GraphSearchIndexStoreError.invalidSourceReplacement(
                expected: sourceReference,
                actual: manifestEntry.sourceReference
            )
        }
        if let manifestEntry,
           manifestEntry.documentCount != documents.count {
            throw GraphSearchIndexStoreError.invalidSourceManifest(
                reason: "The source entry document count does not match its replacement payload."
            )
        }
        try validateDocuments(documents)
        if let manifestEntry {
            let expectedEntry = try GraphSearchSourceManifestEntry.make(
                reference: sourceReference,
                documents: documents
            )
            guard expectedEntry == manifestEntry else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "The source replacement documents do not match their manifest hash."
                )
            }
        } else if documents.isEmpty == false {
            throw GraphSearchIndexStoreError.invalidSourceManifest(
                reason: "Documents cannot be stored for a source that is absent from the manifest."
            )
        }

        let existingManifest = try mapSQLiteErrors {
            try readSourceManifest(
                graphID: sourceReference.graphID,
                connection: connection,
                validateDocuments: false
            )
        }
        guard let existingManifest else {
            throw GraphSearchIndexStoreError.sourceManifestMissing(
                graphID: sourceReference.graphID
            )
        }
        guard existingManifest.isCompatible else {
            throw GraphSearchIndexStoreError.incompatibleSourceManifest(
                formatVersion: existingManifest.formatVersion,
                indexSchemaVersion: existingManifest.indexSchemaVersion
            )
        }

        var entries = existingManifest.entryMap
        if let manifestEntry {
            entries[sourceReference] = manifestEntry
        } else {
            entries.removeValue(forKey: sourceReference)
        }
        let updatedManifest = try GraphSearchSourceManifest(
            graphID: sourceReference.graphID,
            entries: Array(entries.values)
        )

        try withTransaction(operation: "replace-source-with-manifest") { store in
            let transactionConnection = try store.requireConnection()
            try store.deleteSourceDocuments(
                sourceReference,
                connection: transactionConnection,
                operation: "replace-manifest-source-delete"
            )
            try store.cancellationCheck()
            try store.writeDocuments(documents, connection: transactionConnection)
            try store.writeSourceManifest(
                updatedManifest,
                connection: transactionConnection
            )
        }

        BMLog.search.info(
            "Search index replaced source with manifest documents=\(documents.count, privacy: .public) sourcePresent=\(manifestEntry != nil, privacy: .public) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }

    func reconcile(
        graphID: UUID,
        replacements: [GraphSearchIndexSourceReplacement],
        deletions: [GraphSearchSourceReference],
        expectedSourceManifest: GraphSearchSourceManifest,
        sourceManifest: GraphSearchSourceManifest
    ) throws {
        _ = try requireConnection()
        let startedAt = Self.uptimeNanoseconds()

        guard sourceManifest.graphID == graphID else {
            throw GraphSearchIndexStoreError.invalidGraphReplacement(
                expected: graphID,
                actual: sourceManifest.graphID
            )
        }
        try sourceManifest.validateStructure()
        guard sourceManifest.isCompatible else {
            throw GraphSearchIndexStoreError.incompatibleSourceManifest(
                formatVersion: sourceManifest.formatVersion,
                indexSchemaVersion: sourceManifest.indexSchemaVersion
            )
        }
        try expectedSourceManifest.validateStructure()
        guard expectedSourceManifest.graphID == graphID else {
            throw GraphSearchIndexStoreError.invalidGraphReplacement(
                expected: graphID,
                actual: expectedSourceManifest.graphID
            )
        }
        guard expectedSourceManifest.isCompatible else {
            throw GraphSearchIndexStoreError.incompatibleSourceManifest(
                formatVersion: expectedSourceManifest.formatVersion,
                indexSchemaVersion: expectedSourceManifest.indexSchemaVersion
            )
        }

        let manifestEntries = sourceManifest.entryMap
        var replacementReferences = Set<GraphSearchSourceReference>()
        replacementReferences.reserveCapacity(replacements.count)
        for replacement in replacements {
            guard replacementReferences.insert(replacement.sourceReference).inserted else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "A reconciliation source replacement is duplicated."
                )
            }
            guard replacement.sourceReference.graphID == graphID else {
                throw GraphSearchIndexStoreError.invalidGraphReplacement(
                    expected: graphID,
                    actual: replacement.sourceReference.graphID
                )
            }
            guard replacement.manifestEntry.sourceReference == replacement.sourceReference else {
                throw GraphSearchIndexStoreError.invalidSourceReplacement(
                    expected: replacement.sourceReference,
                    actual: replacement.manifestEntry.sourceReference
                )
            }
            guard replacement.documents.count == replacement.manifestEntry.documentCount else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "A reconciliation replacement has a mismatched document count."
                )
            }
            guard manifestEntries[replacement.sourceReference] == replacement.manifestEntry else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "A reconciliation replacement does not match the final manifest."
                )
            }
            let expectedEntry = try GraphSearchSourceManifestEntry.make(
                reference: replacement.sourceReference,
                documents: replacement.documents
            )
            guard expectedEntry == replacement.manifestEntry else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "A reconciliation replacement does not match its document hashes."
                )
            }
            for document in replacement.documents
            where document.sourceReference != replacement.sourceReference {
                throw GraphSearchIndexStoreError.invalidSourceReplacement(
                    expected: replacement.sourceReference,
                    actual: document.sourceReference
                )
            }
            try validateDocuments(replacement.documents)
        }
        var deletionReferences = Set<GraphSearchSourceReference>()
        deletionReferences.reserveCapacity(deletions.count)
        for deletion in deletions {
            guard deletionReferences.insert(deletion).inserted else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "A reconciliation source deletion is duplicated."
                )
            }
            guard deletion.graphID == graphID else {
                throw GraphSearchIndexStoreError.invalidGraphReplacement(
                    expected: graphID,
                    actual: deletion.graphID
                )
            }
            guard manifestEntries[deletion] == nil else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "A deleted reconciliation source is still present in the final manifest."
                )
            }
        }
        guard replacementReferences.isDisjoint(with: deletionReferences) else {
            throw GraphSearchIndexStoreError.invalidSourceManifest(
                reason: "A reconciliation source cannot be replaced and deleted together."
            )
        }

        let sortedReplacements = replacements.sorted {
            Self.sourceReferenceSort($0.sourceReference, $1.sourceReference)
        }
        let sortedDeletions = deletions.sorted(by: Self.sourceReferenceSort)

        try withTransaction(operation: "reconcile-source-manifest") { store in
            let transactionConnection = try store.requireConnection()
            try store.validateCurrentSourceManifestRevision(
                expectedSourceManifest,
                connection: transactionConnection
            )
            for (index, deletion) in sortedDeletions.enumerated() {
                if index.isMultiple(of: store.batchSize) {
                    try store.cancellationCheck()
                }
                try store.deleteSourceDocuments(
                    deletion,
                    connection: transactionConnection,
                    operation: "reconcile-delete-source"
                )
            }
            for (index, replacement) in sortedReplacements.enumerated() {
                if index.isMultiple(of: store.batchSize) {
                    try store.cancellationCheck()
                }
                try store.deleteSourceDocuments(
                    replacement.sourceReference,
                    connection: transactionConnection,
                    operation: "reconcile-replace-source-delete"
                )
                try store.writeDocuments(
                    replacement.documents,
                    connection: transactionConnection
                )
            }
            try store.writeSourceManifest(
                sourceManifest,
                connection: transactionConnection
            )
            try store.deleteLifecycleRows(
                graphID: graphID,
                connection: transactionConnection
            )
        }

        BMLog.search.info(
            "Search index reconciliation committed replacements=\(replacements.count, privacy: .public) deletions=\(deletions.count, privacy: .public) sources=\(sourceManifest.sourceCount, privacy: .public) durationMS=\(Self.elapsedMilliseconds(since: startedAt), format: .fixed(precision: 2))"
        )
    }
}

extension GraphSearchIndexStore {
    func readSourceManifest(
        graphID: UUID,
        connection: GraphSearchSQLiteConnection,
        validateDocuments: Bool
    ) throws -> GraphSearchSourceManifest? {
        let graphIDText = graphID.uuidString.lowercased()
        let headerStatement = try connection.prepare(
            """
            SELECT format_version, index_schema_version, source_count,
                   document_count, aggregate_hash
            FROM graph_search_source_manifests
            WHERE graph_id = ?
            LIMIT 1
            """,
            operation: "read-source-manifest-header"
        )
        try headerStatement.bind(graphIDText, at: 1)
        guard try headerStatement.step() else { return nil }
        let storedFormatVersion = headerStatement.columnInt(at: 0)
        let storedIndexSchemaVersion = headerStatement.columnInt(at: 1)
        let storedSourceCount = headerStatement.columnInt(at: 2)
        let storedDocumentCount = headerStatement.columnInt(at: 3)
        guard let aggregateHash = headerStatement.columnText(at: 4) else {
            throw GraphSearchIndexStoreError.invalidStoredValue(
                column: "source_manifest_aggregate_hash"
            )
        }

        let entryStatement = try connection.prepare(
            """
            SELECT source_kind, source_id, content_hash, document_count
            FROM graph_search_source_manifest_entries
            WHERE graph_id = ?
            ORDER BY source_kind ASC, source_id ASC
            """,
            operation: "read-source-manifest-entries"
        )
        try entryStatement.bind(graphIDText, at: 1)
        var entries: [GraphSearchSourceManifestEntry] = []
        while try entryStatement.step() {
            if entries.count.isMultiple(of: batchSize) {
                try cancellationCheck()
            }
            guard let sourceKindRaw = entryStatement.columnText(at: 0),
                  let sourceKind = GraphSearchSourceKind(rawValue: sourceKindRaw)
            else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "source_manifest_source_kind"
                )
            }
            guard let sourceIDRaw = entryStatement.columnText(at: 1),
                  let sourceID = UUID(uuidString: sourceIDRaw)
            else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "source_manifest_source_id"
                )
            }
            guard let contentHash = entryStatement.columnText(at: 2) else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "source_manifest_content_hash"
                )
            }
            entries.append(
                GraphSearchSourceManifestEntry(
                    graphID: graphID,
                    sourceKind: sourceKind,
                    sourceID: sourceID,
                    contentHash: contentHash,
                    documentCount: entryStatement.columnInt(at: 3)
                )
            )
        }

        let countStatement = try connection.prepare(
            """
            SELECT source_kind, source_count
            FROM graph_search_source_manifest_counts
            WHERE graph_id = ?
            ORDER BY source_kind ASC
            """,
            operation: "read-source-manifest-counts"
        )
        try countStatement.bind(graphIDText, at: 1)
        var counts: [GraphSearchSourceKindCount] = []
        while try countStatement.step() {
            guard let sourceKindRaw = countStatement.columnText(at: 0),
                  let sourceKind = GraphSearchSourceKind(rawValue: sourceKindRaw)
            else {
                throw GraphSearchIndexStoreError.invalidStoredValue(
                    column: "source_manifest_count_kind"
                )
            }
            counts.append(
                GraphSearchSourceKindCount(
                    sourceKind: sourceKind,
                    count: countStatement.columnInt(at: 1)
                )
            )
        }

        let manifest = GraphSearchSourceManifest(
            storedFormatVersion: storedFormatVersion,
            storedIndexSchemaVersion: storedIndexSchemaVersion,
            graphID: graphID,
            sourceCount: storedSourceCount,
            documentCount: storedDocumentCount,
            countsBySourceKind: counts,
            entries: entries,
            aggregateHash: aggregateHash
        )
        do {
            try manifest.validateStructure()
            if validateDocuments {
                try validateManifestDocuments(manifest, connection: connection)
            }
        } catch let error as GraphSearchSourceManifestError {
            throw GraphSearchIndexStoreError.invalidSourceManifest(
                reason: error.localizedDescription
            )
        }
        return manifest
    }

    func validateCurrentSourceManifestRevision(
        _ expected: GraphSearchSourceManifest,
        connection: GraphSearchSQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            SELECT format_version, index_schema_version, source_count,
                   document_count, aggregate_hash
            FROM graph_search_source_manifests
            WHERE graph_id = ?
            LIMIT 1
            """,
            operation: "validate-source-manifest-revision"
        )
        try statement.bind(expected.graphID.uuidString.lowercased(), at: 1)
        guard try statement.step(),
              statement.columnInt(at: 0) == expected.formatVersion,
              statement.columnInt(at: 1) == expected.indexSchemaVersion,
              statement.columnInt(at: 2) == expected.sourceCount,
              statement.columnInt(at: 3) == expected.documentCount,
              statement.columnText(at: 4) == expected.aggregateHash
        else {
            throw GraphSearchIndexStoreError.sourceManifestChangedDuringReconciliation(
                graphID: expected.graphID
            )
        }
    }

    func writeSourceManifest(
        _ manifest: GraphSearchSourceManifest,
        connection: GraphSearchSQLiteConnection
    ) throws {
        try manifest.validateStructure()
        let graphIDText = manifest.graphID.uuidString.lowercased()
        let deleteStatement = try connection.prepare(
            "DELETE FROM graph_search_source_manifests WHERE graph_id = ?",
            operation: "delete-source-manifest"
        )
        try deleteStatement.bind(graphIDText, at: 1)
        try deleteStatement.stepExpectingDone()

        let headerStatement = try connection.prepare(
            """
            INSERT INTO graph_search_source_manifests(
                graph_id, format_version, index_schema_version,
                source_count, document_count, aggregate_hash
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
            operation: "insert-source-manifest-header"
        )
        try headerStatement.bind(graphIDText, at: 1)
        try headerStatement.bind(manifest.formatVersion, at: 2)
        try headerStatement.bind(manifest.indexSchemaVersion, at: 3)
        try headerStatement.bind(manifest.sourceCount, at: 4)
        try headerStatement.bind(manifest.documentCount, at: 5)
        try headerStatement.bind(manifest.aggregateHash, at: 6)
        try headerStatement.stepExpectingDone()

        let entryStatement = try connection.prepare(
            """
            INSERT INTO graph_search_source_manifest_entries(
                graph_id, source_kind, source_id, content_hash, document_count
            ) VALUES (?, ?, ?, ?, ?)
            """,
            operation: "insert-source-manifest-entry"
        )
        for (index, entry) in manifest.entries.enumerated() {
            if index.isMultiple(of: batchSize) {
                try cancellationCheck()
            }
            try entryStatement.bind(graphIDText, at: 1)
            try entryStatement.bind(entry.sourceKind.rawValue, at: 2)
            try entryStatement.bind(entry.sourceID.uuidString.lowercased(), at: 3)
            try entryStatement.bind(entry.contentHash, at: 4)
            try entryStatement.bind(entry.documentCount, at: 5)
            try entryStatement.stepExpectingDone()
            try entryStatement.reset()
        }

        let countStatement = try connection.prepare(
            """
            INSERT INTO graph_search_source_manifest_counts(
                graph_id, source_kind, source_count
            ) VALUES (?, ?, ?)
            """,
            operation: "insert-source-manifest-count"
        )
        for count in manifest.countsBySourceKind {
            try countStatement.bind(graphIDText, at: 1)
            try countStatement.bind(count.sourceKind.rawValue, at: 2)
            try countStatement.bind(count.count, at: 3)
            try countStatement.stepExpectingDone()
            try countStatement.reset()
        }
        try cancellationCheck()
    }

    func deleteSourceManifest(
        graphID: UUID,
        connection: GraphSearchSQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            "DELETE FROM graph_search_source_manifests WHERE graph_id = ?",
            operation: "invalidate-source-manifest"
        )
        try statement.bind(graphID.uuidString.lowercased(), at: 1)
        try statement.stepExpectingDone()
    }

    func deleteSourceDocuments(
        _ reference: GraphSearchSourceReference,
        connection: GraphSearchSQLiteConnection,
        operation: String
    ) throws {
        let statement = try connection.prepare(
            """
            DELETE FROM graph_search_documents
            WHERE graph_id = ? AND source_kind = ? AND source_id = ?
            """,
            operation: operation
        )
        try statement.bind(reference.graphID.uuidString.lowercased(), at: 1)
        try statement.bind(reference.sourceKind.rawValue, at: 2)
        try statement.bind(reference.sourceID.uuidString.lowercased(), at: 3)
        try statement.stepExpectingDone()
    }

    func deleteGraphDocuments(
        graphID: UUID,
        connection: GraphSearchSQLiteConnection,
        operation: String
    ) throws {
        let statement = try connection.prepare(
            "DELETE FROM graph_search_documents WHERE graph_id = ?",
            operation: operation
        )
        try statement.bind(graphID.uuidString.lowercased(), at: 1)
        try statement.stepExpectingDone()
    }

    func validateManifestDocuments(
        _ manifest: GraphSearchSourceManifest,
        connection: GraphSearchSQLiteConnection
    ) throws {
        let statement = try connection.prepare(
            """
            SELECT \(Self.documentSelectColumns)
            FROM graph_search_documents
            WHERE graph_id = ?
            ORDER BY source_kind ASC, source_id ASC, document_id ASC
            """,
            operation: "validate-source-manifest-documents"
        )
        try statement.bind(manifest.graphID.uuidString.lowercased(), at: 1)

        var fingerprintsBySource: [
            GraphSearchSourceReference: [GraphSearchSourceDocumentFingerprint]
        ] = [:]
        fingerprintsBySource.reserveCapacity(manifest.sourceCount)
        var observedDocumentCount = 0
        while try statement.step() {
            if observedDocumentCount.isMultiple(of: batchSize) {
                try cancellationCheck()
            }
            let document = try decodeDocument(from: statement)
            guard document.graphID == manifest.graphID else {
                throw GraphSearchIndexStoreError.invalidGraphReplacement(
                    expected: manifest.graphID,
                    actual: document.graphID
                )
            }
            guard try document.recomputedContentHash() == document.contentHash else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "A stored document content hash does not match its index-relevant values."
                )
            }
            fingerprintsBySource[document.sourceReference, default: []].append(
                GraphSearchSourceDocumentFingerprint(
                    documentID: document.documentID,
                    contentHash: document.contentHash
                )
            )
            observedDocumentCount += 1
        }

        guard observedDocumentCount == manifest.documentCount else {
            throw GraphSearchIndexStoreError.invalidSourceManifest(
                reason: "The graph document count does not match the source manifest."
            )
        }
        let entryMap = manifest.entryMap
        guard fingerprintsBySource.keys.allSatisfy({ entryMap[$0] != nil }) else {
            throw GraphSearchIndexStoreError.invalidSourceManifest(
                reason: "Stored documents contain a source that is absent from the manifest."
            )
        }
        for entry in manifest.entries {
            let expectedEntry = try GraphSearchSourceManifestEntry.make(
                reference: entry.sourceReference,
                fingerprints: fingerprintsBySource[entry.sourceReference, default: []]
            )
            guard expectedEntry == entry else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "Stored document fingerprints do not match the source manifest."
                )
            }
        }
    }

    func validateIncomingDocuments(
        _ documents: [GraphSearchDocument],
        against manifest: GraphSearchSourceManifest
    ) throws {
        var documentsBySource: [
            GraphSearchSourceReference: [GraphSearchDocument]
        ] = [:]
        documentsBySource.reserveCapacity(manifest.sourceCount)
        for document in documents {
            documentsBySource[document.sourceReference, default: []].append(document)
        }

        let entryMap = manifest.entryMap
        guard documentsBySource.keys.allSatisfy({ entryMap[$0] != nil }) else {
            throw GraphSearchIndexStoreError.invalidSourceManifest(
                reason: "The replacement contains documents for an unmanifested source."
            )
        }
        for entry in manifest.entries {
            let expectedEntry = try GraphSearchSourceManifestEntry.make(
                reference: entry.sourceReference,
                documents: documentsBySource[entry.sourceReference, default: []]
            )
            guard expectedEntry == entry else {
                throw GraphSearchIndexStoreError.invalidSourceManifest(
                    reason: "The replacement documents do not match the source manifest."
                )
            }
        }
    }

    nonisolated static func sourceReferenceSort(
        _ lhs: GraphSearchSourceReference,
        _ rhs: GraphSearchSourceReference
    ) -> Bool {
        if lhs.sourceKind.rawValue != rhs.sourceKind.rawValue {
            return lhs.sourceKind.rawValue < rhs.sourceKind.rawValue
        }
        return lhs.sourceID.uuidString < rhs.sourceID.uuidString
    }
}
